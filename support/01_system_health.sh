#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - System Health Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Get CPU usage (top 5 processes)
cpu_procs=$(ps aux --sort=-%cpu | head -6 | tail -5 | awk "{print \"{\\\"pid\\\":\\\"\" \$2 \"\\\",\\\"user\\\":\\\"\" \$1 \"\\\",\\\"cpu\\\":\" \$3 \",\\\"mem\\\":\" \$4 \",\\\"cmd\\\":\\\"\" \$11 \"\\\"}\"}" | paste -sd "," -)

# Get memory info
mem_total=$(free -m | awk "/^Mem:/ {print \$2}")
mem_used=$(free -m | awk "/^Mem:/ {print \$3}")
mem_free=$(free -m | awk "/^Mem:/ {print \$4}")
mem_available=$(free -m | awk "/^Mem:/ {print \$7}")
mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")

# Get swap info
swap_total=$(free -m | awk "/^Swap:/ {print \$2}")
swap_used=$(free -m | awk "/^Swap:/ {print \$3}")
swap_percent=0
if [ "$swap_total" -gt 0 ]; then
    swap_percent=$(awk "BEGIN {printf \"%.1f\", ($swap_used/$swap_total)*100}")
fi

# Get load average
load_1=$(cat /proc/loadavg | awk "{print \$1}")
load_5=$(cat /proc/loadavg | awk "{print \$2}")
load_15=$(cat /proc/loadavg | awk "{print \$3}")

# Get CPU count for load context
cpu_count=$(nproc)

# Get uptime
uptime_seconds=$(cat /proc/uptime | awk "{print int(\$1)}")
uptime_days=$((uptime_seconds / 86400))
uptime_hours=$(((uptime_seconds % 86400) / 3600))
uptime_mins=$(((uptime_seconds % 3600) / 60))

# Get last boot time
last_boot=$(who -b 2>/dev/null | awk "{print \$3, \$4}" || echo "unknown")

# Output JSON
cat << EOF
{
  "script": "01_system_health",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "memory": {
    "total_mb": $mem_total,
    "used_mb": $mem_used,
    "free_mb": $mem_free,
    "available_mb": $mem_available,
    "percent_used": $mem_percent
  },
  "swap": {
    "total_mb": $swap_total,
    "used_mb": $swap_used,
    "percent_used": $swap_percent
  },
  "load_average": {
    "1min": $load_1,
    "5min": $load_5,
    "15min": $load_15,
    "cpu_count": $cpu_count,
    "high_load": $(awk "BEGIN {print ($load_1 > $cpu_count) ? \"true\" : \"false\"}")
  },
  "uptime": {
    "seconds": $uptime_seconds,
    "human": "${uptime_days}d ${uptime_hours}h ${uptime_mins}m",
    "last_boot": "$last_boot"
  },
  "top_cpu_processes": [$cpu_procs]
}
EOF
'
