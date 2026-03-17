#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - DNS Resolution Test
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check DNS resolver config
resolv_conf=""
nameservers=""
search_domains=""

if [ -f /etc/resolv.conf ]; then
    nameservers=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk "{print \$2}" | while read -r ns; do
        echo "\"$ns\""
    done | paste -sd "," - | tr -d "\n")
    
    search_domains=$(grep "^search" /etc/resolv.conf 2>/dev/null | sed "s/^search //" | xargs || echo "")
fi

# systemd-resolved status
resolved_running="false"
if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    resolved_running="true"
fi

# Test DNS resolution for common domains
dns_tests=""
test_domains=("google.com" "cloudflare.com" "github.com")

for domain in "${test_domains[@]}"; do
    start_time=$(date +%s%N)
    result=$(dig +short "$domain" A 2>/dev/null | head -1 || echo "")
    end_time=$(date +%s%N)
    
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    if [ -n "$result" ]; then
        status="ok"
    else
        status="failed"
        result="no response"
    fi
    
    dns_tests="$dns_tests{\"domain\":\"$domain\",\"result\":\"$result\",\"status\":\"$status\",\"time_ms\":$duration_ms},"
done
dns_tests=$(echo "$dns_tests" | sed "s/,$//" | tr -d "\n")

# Test reverse DNS
reverse_dns=""
my_ip=$(hostname -I 2>/dev/null | awk "{print \$1}" || echo "")
if [ -n "$my_ip" ]; then
    reverse=$(dig +short -x "$my_ip" 2>/dev/null | head -1 || echo "")
    reverse_dns="{\"ip\":\"$my_ip\",\"ptr\":\"${reverse:-none}\"}"
fi

# DNS cache stats (if using systemd-resolved)
cache_stats=""
if [ "$resolved_running" = "true" ]; then
    stats=$(resolvectl statistics 2>/dev/null | grep -E "Current|Cache" || echo "")
    if [ -n "$stats" ]; then
        cache_hit=$(echo "$stats" | grep "Cache Hit" | awk "{print \$NF}" || echo 0)
        cache_miss=$(echo "$stats" | grep "Cache Miss" | awk "{print \$NF}" || echo 0)
        cache_stats="{\"cache_hits\":$cache_hit,\"cache_misses\":$cache_miss}"
    fi
fi

# Check if local DNS server running
local_dns="false"
dns_services=("named" "bind9" "dnsmasq" "unbound")
for svc in "${dns_services[@]}"; do
    if systemctl is-active "$svc" >/dev/null 2>&1; then
        local_dns="true"
        break
    fi
done

# Test each nameserver individually
nameserver_tests=""
for ns in $(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk "{print \$2}"); do
    start_time=$(date +%s%N)
    result=$(dig +short @"$ns" google.com A +time=2 2>/dev/null | head -1 || echo "")
    end_time=$(date +%s%N)
    
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    if [ -n "$result" ]; then
        status="ok"
    else
        status="timeout"
    fi
    
    nameserver_tests="$nameserver_tests{\"nameserver\":\"$ns\",\"status\":\"$status\",\"time_ms\":$duration_ms},"
done
nameserver_tests=$(echo "$nameserver_tests" | sed "s/,$//" | tr -d "\n")

# DNSSEC check (basic)
dnssec_support="unknown"
dnssec_test=$(dig +dnssec google.com 2>/dev/null | grep -c "RRSIG" || echo 0)
if [ "$dnssec_test" -gt 0 ]; then
    dnssec_support="working"
else
    dnssec_support="not_working"
fi

# DNS over HTTPS/TLS check
doh_configured="false"
if grep -qi "DNSOverTLS" /etc/systemd/resolved.conf 2>/dev/null; then
    doh_configured="true"
fi

# Average resolution time
avg_time=0
total_time=0
count=0
for domain in google.com cloudflare.com; do
    time_taken=$(dig +short "$domain" +time=2 2>/dev/null | head -1 && echo "ok" || echo "")
    if [ -n "$time_taken" ]; then
        # Simple timing
        count=$((count + 1))
    fi
done

# Overall DNS health
dns_health="healthy"
failed_count=$(echo "$dns_tests" | grep -o "\"failed\"" | wc -l || echo 0)
if [ "$failed_count" -gt 0 ]; then
    dns_health="degraded"
fi
if [ "$failed_count" -gt 2 ]; then
    dns_health="critical"
fi

cat << EOF
{
  "script": "70_dns_resolution",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "health": "$dns_health",
  "resolvers": {
    "nameservers": [${nameservers:-}],
    "search_domains": "$search_domains",
    "systemd_resolved": $resolved_running,
    "local_dns_server": $local_dns
  },
  "resolution_tests": [${dns_tests:-}],
  "nameserver_tests": [${nameserver_tests:-}],
  "reverse_dns": ${reverse_dns:-null},
  "dnssec": "$dnssec_support",
  "dns_over_tls": $doh_configured,
  "cache_stats": ${cache_stats:-null}
}
EOF
'
