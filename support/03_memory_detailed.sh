#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Detailed Memory Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Get detailed memory info
mem_total=$(free -m | awk "/^Mem:/ {print \$2}")
mem_used=$(free -m | awk "/^Mem:/ {print \$3}")
mem_free=$(free -m | awk "/^Mem:/ {print \$4}")
mem_shared=$(free -m | awk "/^Mem:/ {print \$5}")
mem_buffers=$(free -m | awk "/^Mem:/ {print \$6}")
mem_available=$(free -m | awk "/^Mem:/ {print \$7}")
mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")

# Swap info
swap_total=$(free -m | awk "/^Swap:/ {print \$2}")
swap_used=$(free -m | awk "/^Swap:/ {print \$3}")
swap_free=$(free -m | awk "/^Swap:/ {print \$4}")
swap_percent=0
if [ "$swap_total" -gt 0 ]; then
    swap_percent=$(awk "BEGIN {printf \"%.1f\", ($swap_used/$swap_total)*100}")
fi

# Top 10 memory-consuming processes
mem_procs=""
while IFS= read -r line; do
    pid=$(echo "$line" | awk "{print \$1}")
    user=$(echo "$line" | awk "{print \$2}")
    rss=$(echo "$line" | awk "{print \$3}")
    percent=$(echo "$line" | awk "{print \$4}")
    cmd=$(echo "$line" | awk "{print \$5}")
    
    if [ -n "$mem_procs" ]; then
        mem_procs="$mem_procs,"
    fi
    mem_procs="$mem_procs{\"pid\":$pid,\"user\":\"$user\",\"rss_mb\":$rss,\"percent\":$percent,\"command\":\"$cmd\"}"
done < <(ps aux --sort=-rss | awk "NR>1 {printf \"%s %s %.0f %.1f %s\n\", \$2, \$1, \$6/1024, \$4, \$11}" | head -10)

# Check for OOM killer activity (recent)
oom_count=$(dmesg 2>/dev/null | grep -c "Out of memory" 2>/dev/null || true)
oom_count=${oom_count:-0}
oom_count=$((oom_count + 0))
oom_recent=""
if [ "$oom_count" -gt 0 ]; then
    oom_recent=$(dmesg 2>/dev/null | grep "Out of memory" | tail -3 | while read line; do echo "\"$(echo "$line" | sed "s/\"/\\\\\"/g")\""; done | paste -sd "," -)
fi

# Memory pressure indicator
mem_pressure="low"
if [ $(echo "$mem_percent > 90" | bc -l) -eq 1 ]; then
    mem_pressure="critical"
elif [ $(echo "$mem_percent > 80" | bc -l) -eq 1 ]; then
    mem_pressure="high"
elif [ $(echo "$mem_percent > 60" | bc -l) -eq 1 ]; then
    mem_pressure="medium"
fi

# Check swap activity (vmstat)
swap_in=$(vmstat 1 2 2>/dev/null | tail -1 | awk "{print \$7}" || echo "0")
swap_out=$(vmstat 1 2 2>/dev/null | tail -1 | awk "{print \$8}" || echo "0")

# Output JSON
cat << EOF
{
  "script": "03_memory_detailed",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "memory": {
    "total_mb": $mem_total,
    "used_mb": $mem_used,
    "free_mb": $mem_free,
    "shared_mb": $mem_shared,
    "buffers_cache_mb": $mem_buffers,
    "available_mb": $mem_available,
    "percent_used": $mem_percent,
    "pressure": "$mem_pressure"
  },
  "swap": {
    "total_mb": $swap_total,
    "used_mb": $swap_used,
    "free_mb": $swap_free,
    "percent_used": $swap_percent,
    "swap_in_kb_s": $swap_in,
    "swap_out_kb_s": $swap_out
  },
  "top_memory_processes": [$mem_procs],
  "oom_killer": {
    "recent_count": $((oom_count + 0)),
    "recent_events": [${oom_recent:-}]
  }
}
EOF
'
