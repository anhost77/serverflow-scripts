#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - CPU Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# CPU info
cpu_model=$(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d: -f2 | xargs || echo "unknown")
cpu_cores=$(nproc)
cpu_physical=$(cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l || echo 1)
[ "$cpu_physical" -eq 0 ] && cpu_physical=1

# Load average
load_1=$(cat /proc/loadavg | awk "{print \$1}")
load_5=$(cat /proc/loadavg | awk "{print \$2}")
load_15=$(cat /proc/loadavg | awk "{print \$3}")

# Current CPU usage (1 second sample)
cpu_usage=$(top -bn2 -d 0.5 | grep "Cpu(s)" | tail -1 | awk "{print 100 - \$8}" || echo 0)

# CPU usage breakdown
cpu_user=$(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | tr -d "%us," || echo 0)
cpu_system=$(top -bn1 | grep "Cpu(s)" | awk "{print \$4}" | tr -d "%sy," || echo 0)
cpu_iowait=$(top -bn1 | grep "Cpu(s)" | awk "{gsub(/%wa,/,\"\"); for(i=1;i<=NF;i++) if(\$i ~ /wa/) print \$(i-1)}" || echo 0)

# Top 10 CPU consuming processes
cpu_procs=""
while IFS= read -r line; do
    pid=$(echo "$line" | awk "{print \$1}")
    user=$(echo "$line" | awk "{print \$2}")
    cpu=$(echo "$line" | awk "{print \$3}")
    mem=$(echo "$line" | awk "{print \$4}")
    cmd=$(echo "$line" | awk "{print \$5}")
    
    if [ -n "$cpu_procs" ]; then
        cpu_procs="$cpu_procs,"
    fi
    cpu_procs="$cpu_procs{\"pid\":$pid,\"user\":\"$user\",\"cpu_percent\":$cpu,\"mem_percent\":$mem,\"command\":\"$cmd\"}"
done < <(ps aux --sort=-%cpu | awk "NR>1 {print \$2, \$1, \$3, \$4, \$11}" | head -10)

# Running processes count
procs_total=$(ps aux | wc -l)
procs_running=$(ps aux | awk "\$8 ~ /R/ {count++} END {print count+0}")

# CPU pressure indicator
cpu_pressure="low"
load_ratio=$(awk "BEGIN {printf \"%.2f\", $load_1 / $cpu_cores}")
if [ $(echo "$load_ratio > 2" | bc -l) -eq 1 ]; then
    cpu_pressure="critical"
elif [ $(echo "$load_ratio > 1" | bc -l) -eq 1 ]; then
    cpu_pressure="high"
elif [ $(echo "$load_ratio > 0.7" | bc -l) -eq 1 ]; then
    cpu_pressure="medium"
fi

# High IO wait check
io_pressure="low"
if [ $(echo "${cpu_iowait:-0} > 20" | bc -l 2>/dev/null) -eq 1 ]; then
    io_pressure="high"
elif [ $(echo "${cpu_iowait:-0} > 10" | bc -l 2>/dev/null) -eq 1 ]; then
    io_pressure="medium"
fi

# Output JSON
cat << EOF
{
  "script": "04_cpu_analysis",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "cpu_info": {
    "model": "$cpu_model",
    "cores": $cpu_cores,
    "physical_cpus": $cpu_physical
  },
  "load_average": {
    "1min": $load_1,
    "5min": $load_5,
    "15min": $load_15,
    "load_per_core": $load_ratio,
    "pressure": "$cpu_pressure"
  },
  "cpu_usage": {
    "total_percent": ${cpu_usage:-0},
    "user_percent": ${cpu_user:-0},
    "system_percent": ${cpu_system:-0},
    "iowait_percent": ${cpu_iowait:-0},
    "io_pressure": "$io_pressure"
  },
  "processes": {
    "total": $procs_total,
    "running": $procs_running
  },
  "top_cpu_processes": [$cpu_procs]
}
EOF
'
