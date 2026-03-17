#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - I/O Statistics
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check if iostat is available
iostat_available="false"
iostat_data=""

if command -v iostat &>/dev/null; then
    iostat_available="true"
    # Get device stats (1 sample)
    iostat_data=$(iostat -dx 1 1 2>/dev/null | awk "
    NR>3 && NF>0 {
        printf \"{\\\"device\\\":\\\"%s\\\",\\\"rrqm_s\\\":%.2f,\\\"wrqm_s\\\":%.2f,\\\"r_s\\\":%.2f,\\\"w_s\\\":%.2f,\\\"rkB_s\\\":%.2f,\\\"wkB_s\\\":%.2f,\\\"await\\\":%.2f,\\\"util\\\":%.2f},\", \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$10, \$NF
    }" | sed "s/,$//" | tr -d "\n")
fi

# Fallback: /proc/diskstats
disk_stats=$(cat /proc/diskstats 2>/dev/null | awk "
\$3 ~ /^(sd[a-z]|vd[a-z]|nvme[0-9]+n[0-9]+)$/ {
    printf \"{\\\"device\\\":\\\"%s\\\",\\\"reads\\\":%s,\\\"reads_merged\\\":%s,\\\"sectors_read\\\":%s,\\\"writes\\\":%s,\\\"writes_merged\\\":%s,\\\"sectors_written\\\":%s},\", \$3, \$4, \$5, \$6, \$8, \$9, \$10
}" | sed "s/,$//" | tr -d "\n")

# I/O wait from /proc/stat
cpu_line=$(head -1 /proc/stat)
total_cpu=$(echo "$cpu_line" | awk "{print \$2+\$3+\$4+\$5+\$6+\$7+\$8}")
iowait=$(echo "$cpu_line" | awk "{print \$6}")
iowait_percent=$(awk "BEGIN {printf \"%.1f\", ($iowait / $total_cpu) * 100}")

# Processes in D state (waiting for I/O)
d_state_procs=$(ps aux | awk "\$8 ~ /D/" | wc -l)
d_state_list=""
if [ "$d_state_procs" -gt 0 ]; then
    d_state_list=$(ps aux | awk "\$8 ~ /D/ {printf \"{\\\"pid\\\":%s,\\\"cmd\\\":\\\"%s\\\"},\", \$2, \$11}" | sed "s/,$//" | head -c 500 | tr -d "\n")
fi

# Top I/O processes (if iotop data available via /proc)
top_io=""
if [ -d /proc ]; then
    top_io=$(find /proc -maxdepth 1 -type d -name "[0-9]*" 2>/dev/null | while read pid_dir; do
        pid=$(basename "$pid_dir")
        if [ -f "$pid_dir/io" ] && [ -r "$pid_dir/io" ]; then
            read_bytes=$(grep "read_bytes:" "$pid_dir/io" 2>/dev/null | awk "{print \$2}" || echo 0)
            write_bytes=$(grep "write_bytes:" "$pid_dir/io" 2>/dev/null | awk "{print \$2}" || echo 0)
            cmd=$(cat "$pid_dir/comm" 2>/dev/null || echo "unknown")
            if [ "$read_bytes" -gt 0 ] || [ "$write_bytes" -gt 0 ]; then
                echo "$read_bytes $write_bytes $pid $cmd"
            fi
        fi
    done | sort -rn | head -10 | awk "{printf \"{\\\"pid\\\":%s,\\\"cmd\\\":\\\"%s\\\",\\\"read_bytes\\\":%s,\\\"write_bytes\\\":%s},\", \$3, \$4, \$1, \$2}" | sed "s/,$//" | tr -d "\n")
fi

# Check for I/O pressure
io_pressure="normal"
if [ "$d_state_procs" -gt 5 ] || [ "${iowait_percent%.*}" -gt 20 ]; then
    io_pressure="high"
fi
if [ "$d_state_procs" -gt 20 ] || [ "${iowait_percent%.*}" -gt 50 ]; then
    io_pressure="critical"
fi

cat << EOF
{
  "script": "07_io_stats",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "io_wait": {
    "percent": $iowait_percent,
    "pressure": "$io_pressure"
  },
  "d_state_processes": {
    "count": $d_state_procs,
    "processes": [${d_state_list:-}]
  },
  "iostat_available": $iostat_available,
  "iostat_data": [${iostat_data:-}],
  "disk_stats": [${disk_stats:-}],
  "top_io_processes": [${top_io:-}]
}
EOF
'
