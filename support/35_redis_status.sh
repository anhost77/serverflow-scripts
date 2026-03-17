#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Redis Status Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check if Redis is installed
redis_installed="false"
redis_path=$(which redis-cli 2>/dev/null || echo "")
if [ -n "$redis_path" ]; then
    redis_installed="true"
fi

# Service status
redis_running="false"
redis_status="not installed"
redis_pid=""
for service in redis redis-server redis6; do
    status=$(systemctl is-active $service 2>/dev/null || echo "not found")
    if [ "$status" = "active" ]; then
        redis_running="true"
        redis_status="running"
        redis_pid=$(systemctl show $service --property=MainPID --value 2>/dev/null || echo "")
        break
    elif [ "$status" != "not found" ]; then
        redis_status="$status"
    fi
done

# Redis version
redis_version=""
if [ "$redis_installed" = "true" ]; then
    redis_version=$(redis-cli --version 2>/dev/null | awk "{print \$2}" || echo "unknown")
fi

# Connection test
redis_connected="false"
redis_ping=""
if [ "$redis_running" = "true" ]; then
    redis_ping=$(redis-cli ping 2>/dev/null || echo "FAIL")
    if [ "$redis_ping" = "PONG" ]; then
        redis_connected="true"
    fi
fi

# Get Redis INFO stats
redis_info=""
memory_used=""
memory_peak=""
connected_clients=""
blocked_clients=""
keys_total=""
expired_keys=""
evicted_keys=""
hit_rate=""
uptime_seconds=""

if [ "$redis_connected" = "true" ]; then
    redis_info=$(redis-cli INFO 2>/dev/null || echo "")
    
    if [ -n "$redis_info" ]; then
        # Memory
        memory_used=$(echo "$redis_info" | grep "^used_memory_human:" | cut -d: -f2 | tr -d "\r" || echo "")
        memory_peak=$(echo "$redis_info" | grep "^used_memory_peak_human:" | cut -d: -f2 | tr -d "\r" || echo "")
        
        # Clients
        connected_clients=$(echo "$redis_info" | grep "^connected_clients:" | cut -d: -f2 | tr -d "\r" || echo "0")
        blocked_clients=$(echo "$redis_info" | grep "^blocked_clients:" | cut -d: -f2 | tr -d "\r" || echo "0")
        
        # Keyspace
        keyspace=$(echo "$redis_info" | grep "^db0:" || echo "")
        if [ -n "$keyspace" ]; then
            keys_total=$(echo "$keyspace" | grep -o "keys=[0-9]*" | cut -d= -f2 || echo "0")
            expired_keys=$(echo "$redis_info" | grep "^expired_keys:" | cut -d: -f2 | tr -d "\r" || echo "0")
            evicted_keys=$(echo "$redis_info" | grep "^evicted_keys:" | cut -d: -f2 | tr -d "\r" || echo "0")
        fi
        
        # Hit rate
        hits=$(echo "$redis_info" | grep "^keyspace_hits:" | cut -d: -f2 | tr -d "\r" || echo "0")
        misses=$(echo "$redis_info" | grep "^keyspace_misses:" | cut -d: -f2 | tr -d "\r" || echo "0")
        if [ "$hits" -gt 0 ] || [ "$misses" -gt 0 ]; then
            hit_rate=$(awk "BEGIN {printf \"%.2f\", ($hits / ($hits + $misses)) * 100}")
        fi
        
        # Uptime
        uptime_seconds=$(echo "$redis_info" | grep "^uptime_in_seconds:" | cut -d: -f2 | tr -d "\r" || echo "0")
    fi
fi

# Memory usage of Redis process
redis_mem_mb=""
if [ -n "$redis_pid" ] && [ "$redis_pid" != "0" ]; then
    redis_mem_kb=$(ps -o rss= -p "$redis_pid" 2>/dev/null || echo 0)
    redis_mem_mb=$((redis_mem_kb / 1024))
fi

# Port 6379 listener - escape quotes for JSON
listening_6379=$(ss -tlnp 2>/dev/null | grep ":6379 " | awk "{print \$NF}" | head -1 | sed "s/\"/\\\\\"/g" || echo "none")

# RDB/AOF persistence check
persistence_rdb="false"
persistence_aof="false"
if [ "$redis_connected" = "true" ]; then
    rdb_enabled=$(redis-cli CONFIG GET save 2>/dev/null | tail -1 || echo "")
    if [ -n "$rdb_enabled" ] && [ "$rdb_enabled" != '""' ]; then
        persistence_rdb="true"
    fi
    aof_enabled=$(redis-cli CONFIG GET appendonly 2>/dev/null | tail -1 || echo "no")
    if [ "$aof_enabled" = "yes" ]; then
        persistence_aof="true"
    fi
fi

# Recent errors from log
redis_errors=""
error_count=0
for log in /var/log/redis/redis-server.log /var/log/redis.log /var/log/redis/redis.log; do
    if [ -f "$log" ]; then
        error_count=$(tail -100 "$log" 2>/dev/null | grep -ci "error\|warning\|fatal" 2>/dev/null || true)
        error_count=${error_count:-0}
        error_count=$((error_count + 0))
        redis_errors=$(tail -20 "$log" 2>/dev/null | grep -i "error\|warning" | tail -3 | while read line; do echo "\"$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)\""; done | paste -sd "," -)
        break
    fi
done

# Output JSON
cat << EOF
{
  "script": "35_redis_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "redis": {
    "installed": $redis_installed,
    "version": "$redis_version",
    "running": $redis_running,
    "status": "$redis_status",
    "connected": $redis_connected,
    "pid": ${redis_pid:-null}
  },
  "memory": {
    "used": "${memory_used:-unknown}",
    "peak": "${memory_peak:-unknown}",
    "process_mb": ${redis_mem_mb:-null}
  },
  "clients": {
    "connected": ${connected_clients:-0},
    "blocked": ${blocked_clients:-0}
  },
  "keyspace": {
    "total_keys": ${keys_total:-0},
    "expired_keys": ${expired_keys:-0},
    "evicted_keys": ${evicted_keys:-0},
    "hit_rate_percent": ${hit_rate:-null}
  },
  "persistence": {
    "rdb_enabled": $persistence_rdb,
    "aof_enabled": $persistence_aof
  },
  "uptime_seconds": ${uptime_seconds:-0},
  "port_6379": "$listening_6379",
  "errors": {
    "recent_count": $error_count,
    "recent_entries": [${redis_errors:-}]
  }
}
EOF
'
