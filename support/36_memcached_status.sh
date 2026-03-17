#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Memcached Status
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check if memcached is installed and running
memcached_installed="false"
memcached_running="false"

if command -v memcached &>/dev/null; then
    memcached_installed="true"
fi

if systemctl is-active memcached >/dev/null 2>&1; then
    memcached_running="true"
fi

# Get memcached version
memcached_version=""
if [ "$memcached_installed" = "true" ]; then
    memcached_version=$(memcached -h 2>&1 | head -1 | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
fi

# Default connection settings
memcached_host="127.0.0.1"
memcached_port="11211"

# Get stats via nc/netcat
can_connect="false"
stats=""
total_items=0
bytes_used=0
bytes_limit=0
get_hits=0
get_misses=0
curr_connections=0
uptime_seconds=0
evictions=0

if [ "$memcached_running" = "true" ]; then
    # Try to get stats
    raw_stats=$(echo "stats" | nc -q 1 "$memcached_host" "$memcached_port" 2>/dev/null || echo "")
    
    if [ -n "$raw_stats" ]; then
        can_connect="true"
        
        # Parse key stats
        uptime_seconds=$(echo "$raw_stats" | grep "STAT uptime" | awk "{print \$3}" || echo 0)
        curr_connections=$(echo "$raw_stats" | grep "STAT curr_connections" | awk "{print \$3}" || echo 0)
        total_items=$(echo "$raw_stats" | grep "STAT curr_items" | awk "{print \$3}" || echo 0)
        bytes_used=$(echo "$raw_stats" | grep "STAT bytes " | awk "{print \$3}" || echo 0)
        bytes_limit=$(echo "$raw_stats" | grep "STAT limit_maxbytes" | awk "{print \$3}" || echo 0)
        get_hits=$(echo "$raw_stats" | grep "STAT get_hits" | awk "{print \$3}" || echo 0)
        get_misses=$(echo "$raw_stats" | grep "STAT get_misses" | awk "{print \$3}" || echo 0)
        evictions=$(echo "$raw_stats" | grep "STAT evictions" | awk "{print \$3}" || echo 0)
    fi
fi

# Calculate hit rate
hit_rate=0
total_gets=$((get_hits + get_misses))
if [ "$total_gets" -gt 0 ]; then
    hit_rate=$(awk "BEGIN {printf \"%.2f\", ($get_hits / $total_gets) * 100}")
fi

# Memory utilization
memory_utilization=0
if [ "$bytes_limit" -gt 0 ]; then
    memory_utilization=$(awk "BEGIN {printf \"%.2f\", ($bytes_used / $bytes_limit) * 100}")
fi

# Convert bytes to MB
bytes_used_mb=$(awk "BEGIN {printf \"%.2f\", $bytes_used / 1024 / 1024}")
bytes_limit_mb=$(awk "BEGIN {printf \"%.2f\", $bytes_limit / 1024 / 1024}")

# Uptime human readable
uptime_days=$((uptime_seconds / 86400))
uptime_hours=$(((uptime_seconds % 86400) / 3600))

# Get slab stats for more detail
slab_stats=""
if [ "$can_connect" = "true" ]; then
    raw_slabs=$(echo "stats slabs" | nc -q 1 "$memcached_host" "$memcached_port" 2>/dev/null || echo "")
    if [ -n "$raw_slabs" ]; then
        # Parse active slabs
        active_slabs=$(echo "$raw_slabs" | grep "STAT active_slabs" | awk "{print \$3}" || echo 0)
        total_malloced=$(echo "$raw_slabs" | grep "STAT total_malloced" | awk "{print \$3}" || echo 0)
        slab_stats="{\"active_slabs\":$active_slabs,\"total_malloced\":$total_malloced}"
    fi
fi

# Check config file
config_file=""
config_memory=""
config_connections=""
if [ -f /etc/memcached.conf ]; then
    config_file="/etc/memcached.conf"
    config_memory=$(grep "^-m" /etc/memcached.conf 2>/dev/null | awk "{print \$2}" || echo "")
    config_connections=$(grep "^-c" /etc/memcached.conf 2>/dev/null | awk "{print \$2}" || echo "")
elif [ -f /etc/sysconfig/memcached ]; then
    config_file="/etc/sysconfig/memcached"
fi

cat << EOF
{
  "script": "36_memcached_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "memcached": {
    "installed": $memcached_installed,
    "running": $memcached_running,
    "version": "$memcached_version",
    "can_connect": $can_connect
  },
  "connection": {
    "host": "$memcached_host",
    "port": $memcached_port,
    "current_connections": $curr_connections
  },
  "memory": {
    "used_mb": $bytes_used_mb,
    "limit_mb": $bytes_limit_mb,
    "utilization_percent": $memory_utilization
  },
  "items": {
    "current": $total_items,
    "evictions": $evictions
  },
  "performance": {
    "get_hits": $get_hits,
    "get_misses": $get_misses,
    "hit_rate_percent": $hit_rate
  },
  "uptime": {
    "seconds": $uptime_seconds,
    "human": "${uptime_days}d ${uptime_hours}h"
  },
  "slabs": ${slab_stats:-null},
  "config": {
    "file": "$config_file",
    "memory_mb": "${config_memory:-auto}",
    "max_connections": "${config_connections:-auto}"
  }
}
EOF
'
