#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Open Ports Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Get listening TCP ports
tcp_ports=""
tcp_count=0
if command -v ss &>/dev/null; then
    tcp_ports=$(ss -tlnp 2>/dev/null | tail -n +2 | while read -r line; do
        local_addr=$(echo "$line" | awk "{print \$4}")
        port=$(echo "$local_addr" | rev | cut -d: -f1 | rev)
        ip=$(echo "$local_addr" | rev | cut -d: -f2- | rev)
        
        # Get process info
        proc_info=$(echo "$line" | grep -oP "users:\(\(\"[^\"]+\"" | sed "s/users:((\"//;s/\"//" || echo "unknown")
        
        # Determine if listening on all interfaces
        exposed="false"
        if [ "$ip" = "*" ] || [ "$ip" = "0.0.0.0" ] || [ "$ip" = "::" ]; then
            exposed="true"
        fi
        
        echo "{\"port\":$port,\"protocol\":\"tcp\",\"address\":\"$ip\",\"process\":\"$proc_info\",\"exposed\":$exposed}"
    done | paste -sd "," - | tr -d "\n")
    tcp_count=$(ss -tlnp 2>/dev/null | tail -n +2 | wc -l || echo 0)
fi

# Get listening UDP ports
udp_ports=""
udp_count=0
if command -v ss &>/dev/null; then
    udp_ports=$(ss -ulnp 2>/dev/null | tail -n +2 | while read -r line; do
        local_addr=$(echo "$line" | awk "{print \$4}")
        port=$(echo "$local_addr" | rev | cut -d: -f1 | rev)
        ip=$(echo "$local_addr" | rev | cut -d: -f2- | rev)
        proc_info=$(echo "$line" | grep -oP "users:\(\(\"[^\"]+\"" | sed "s/users:((\"//;s/\"//" || echo "unknown")
        exposed="false"
        if [ "$ip" = "*" ] || [ "$ip" = "0.0.0.0" ] || [ "$ip" = "::" ]; then
            exposed="true"
        fi
        echo "{\"port\":$port,\"protocol\":\"udp\",\"address\":\"$ip\",\"process\":\"$proc_info\",\"exposed\":$exposed}"
    done | paste -sd "," - | tr -d "\n")
    udp_count=$(ss -ulnp 2>/dev/null | tail -n +2 | wc -l || echo 0)
fi

# Common dangerous ports check
dangerous_ports=""
dangerous_check=(
    "23:telnet"
    "21:ftp"
    "25:smtp"
    "110:pop3"
    "143:imap"
    "445:smb"
    "3389:rdp"
    "5900:vnc"
    "6379:redis"
    "27017:mongodb"
    "9200:elasticsearch"
    "11211:memcached"
)

for item in "${dangerous_check[@]}"; do
    port="${item%%:*}"
    service="${item##*:}"
    
    # Check if port is exposed on all interfaces
    if ss -tlnp 2>/dev/null | grep -E "0\.0\.0\.0:$port|\*:$port|:::$port" &>/dev/null; then
        dangerous_ports="$dangerous_ports{\"port\":$port,\"service\":\"$service\",\"status\":\"exposed\"},"
    fi
done
dangerous_ports=$(echo "$dangerous_ports" | sed "s/,$//" | tr -d "\n")

# External connectivity check (what'\''s reachable from outside)
# This is an approximation based on what'\''s bound to 0.0.0.0 or ::
exposed_services=""
exposed_services=$(ss -tlnp 2>/dev/null | grep -E "0\.0\.0\.0:|:::|\*:" | while read -r line; do
    port=$(echo "$line" | awk "{print \$4}" | rev | cut -d: -f1 | rev)
    proc=$(echo "$line" | grep -oP "users:\(\(\"[^\"]+\"" | sed "s/users:((\"//;s/\"//" || echo "unknown")
    
    # Map common ports to services
    service="unknown"
    case $port in
        22) service="ssh";;
        80) service="http";;
        443) service="https";;
        3306) service="mysql";;
        5432) service="postgresql";;
        6379) service="redis";;
        27017) service="mongodb";;
        8080) service="http-alt";;
        9000) service="php-fpm";;
        *) service="$proc";;
    esac
    
    echo "{\"port\":$port,\"service\":\"$service\",\"process\":\"$proc\"}"
done | paste -sd "," - | tr -d "\n")

# Count exposed vs local-only
exposed_count=$(ss -tlnp 2>/dev/null | grep -cE "0\.0\.0\.0:|:::|\*:" || echo 0)
local_only_count=$((tcp_count - exposed_count))

# Recent established connections count
established_count=$(ss -tn state established 2>/dev/null | wc -l || echo 0)

cat << EOF
{
  "script": "52_open_ports",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "summary": {
    "tcp_listening": $tcp_count,
    "udp_listening": $udp_count,
    "exposed_to_all": $exposed_count,
    "local_only": $local_only_count,
    "established_connections": $established_count
  },
  "tcp_ports": [${tcp_ports:-}],
  "udp_ports": [${udp_ports:-}],
  "exposed_services": [${exposed_services:-}],
  "dangerous_ports_exposed": [${dangerous_ports:-}]
}
EOF
'
