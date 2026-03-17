#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Network Connections
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Connection summary by state
established=$(ss -tan state established 2>/dev/null | wc -l)
time_wait=$(ss -tan state time-wait 2>/dev/null | wc -l)
close_wait=$(ss -tan state close-wait 2>/dev/null | wc -l)
listen=$(ss -tln 2>/dev/null | tail -n +2 | wc -l)

# Top remote IPs (established connections)
top_ips=$(ss -tan state established 2>/dev/null | awk "NR>1 {print \$4}" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort | uniq -c | sort -rn | head -10 | awk "{printf \"{\\\"ip\\\":\\\"%s\\\",\\\"count\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")

# Listening services (local ports)
listening=$(ss -tlnp 2>/dev/null | awk "NR>1 {
    split(\$4, a, \":\");
    port = a[length(a)];
    proc = \$6;
    gsub(/users:\(\(\"/, \"\", proc);
    gsub(/\".*/, \"\", proc);
    if (proc == \"\") proc = \"unknown\";
    printf \"{\\\"port\\\":%s,\\\"address\\\":\\\"%s\\\",\\\"process\\\":\\\"%s\\\"},\", port, \$4, proc
}" | sed "s/,$//" | tr -d "\n")

# Connections per port (top 10)
conn_per_port=$(ss -tan 2>/dev/null | awk "NR>1 {split(\$4, a, \":\"); print a[length(a)]}" | sort | uniq -c | sort -rn | head -10 | awk "{printf \"{\\\"port\\\":%s,\\\"connections\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")

# Total connections
total_conn=$(ss -tan 2>/dev/null | wc -l)

# UDP listeners
udp_listen=$(ss -uln 2>/dev/null | tail -n +2 | wc -l)

# Check for connection flood (>100 connections from single IP)
flood_warning="false"
max_conn_per_ip=$(ss -tan state established 2>/dev/null | awk "NR>1 {print \$4}" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort | uniq -c | sort -rn | head -1 | awk "{print \$1}")
if [ "${max_conn_per_ip:-0}" -gt 100 ]; then
    flood_warning="true"
fi

cat << EOF
{
  "script": "06_network_connections",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "summary": {
    "total_connections": $((total_conn - 1)),
    "established": $((established - 1)),
    "time_wait": $((time_wait - 1)),
    "close_wait": $((close_wait - 1)),
    "listening_tcp": $listen,
    "listening_udp": $udp_listen
  },
  "flood_warning": $flood_warning,
  "top_remote_ips": [${top_ips:-}],
  "listening_services": [${listening:-}],
  "connections_per_port": [${conn_per_port:-}]
}
EOF
'
