#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Process List
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Get total process count
process_count=$(ps aux | wc -l)

# Top 10 CPU consuming processes
top_cpu=$(ps aux --sort=-%cpu | head -11 | tail -10 | awk "{printf \"{\\\"pid\\\":%s,\\\"user\\\":\\\"%s\\\",\\\"cpu\\\":%.1f,\\\"mem\\\":%.1f,\\\"vsz\\\":%s,\\\"rss\\\":%s,\\\"stat\\\":\\\"%s\\\",\\\"cmd\\\":\\\"%s\\\"},\", \$2, \$1, \$3, \$4, \$5, \$6, \$8, \$11}" | sed "s/,$//" | tr -d "\n")

# Top 10 Memory consuming processes
top_mem=$(ps aux --sort=-%mem | head -11 | tail -10 | awk "{printf \"{\\\"pid\\\":%s,\\\"user\\\":\\\"%s\\\",\\\"cpu\\\":%.1f,\\\"mem\\\":%.1f,\\\"vsz\\\":%s,\\\"rss\\\":%s,\\\"stat\\\":\\\"%s\\\",\\\"cmd\\\":\\\"%s\\\"},\", \$2, \$1, \$3, \$4, \$5, \$6, \$8, \$11}" | sed "s/,$//" | tr -d "\n")

# Zombie processes
zombie_count=$(ps aux | awk "\$8 ~ /Z/ {print}" | wc -l)
zombies=""
if [ "$zombie_count" -gt 0 ]; then
    zombies=$(ps aux | awk "\$8 ~ /Z/ {printf \"{\\\"pid\\\":%s,\\\"ppid\\\":\\\"%s\\\",\\\"cmd\\\":\\\"%s\\\"},\", \$2, \$3, \$11}" | sed "s/,$//" | head -c 500)
fi

# Process states summary
running=$(ps aux | awk "\$8 ~ /R/ {print}" | wc -l)
sleeping=$(ps aux | awk "\$8 ~ /S/ {print}" | wc -l)
stopped=$(ps aux | awk "\$8 ~ /T/ {print}" | wc -l)
uninterruptible=$(ps aux | awk "\$8 ~ /D/ {print}" | wc -l)

# Users with most processes
top_users=$(ps aux | awk "NR>1 {print \$1}" | sort | uniq -c | sort -rn | head -5 | awk "{printf \"{\\\"user\\\":\\\"%s\\\",\\\"count\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")

cat << EOF
{
  "script": "05_process_list",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "summary": {
    "total_processes": $((process_count - 1)),
    "running": $running,
    "sleeping": $sleeping,
    "stopped": $stopped,
    "uninterruptible": $uninterruptible,
    "zombie": $zombie_count
  },
  "top_by_cpu": [$top_cpu],
  "top_by_memory": [$top_mem],
  "zombies": [$zombies],
  "top_users": [$top_users]
}
EOF
'
