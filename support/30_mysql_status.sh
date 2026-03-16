#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - MySQL/MariaDB Status Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Detect MySQL/MariaDB
mysql_installed="false"
mysql_type="none"
mysql_path=$(which mysql 2>/dev/null || echo "")
if [ -n "$mysql_path" ]; then
    mysql_installed="true"
    if mysql --version 2>/dev/null | grep -qi "mariadb"; then
        mysql_type="mariadb"
    else
        mysql_type="mysql"
    fi
fi

# Service status
mysql_running="false"
mysql_status="not installed"
mysql_pid=""
for service in mysql mariadb mysqld; do
    status=$(systemctl is-active $service 2>/dev/null || echo "not found")
    if [ "$status" = "active" ]; then
        mysql_running="true"
        mysql_status="running"
        mysql_pid=$(systemctl show $service --property=MainPID --value 2>/dev/null || echo "")
        break
    elif [ "$status" != "not found" ]; then
        mysql_status="$status"
    fi
done

# MySQL version
mysql_version=""
if [ "$mysql_installed" = "true" ]; then
    mysql_version=$(mysql --version 2>/dev/null | awk "{print \$3}" || echo "unknown")
fi

# Connection test (if socket exists)
socket_ok="false"
socket_path=""
for sock in /var/run/mysqld/mysqld.sock /var/lib/mysql/mysql.sock /tmp/mysql.sock; do
    if [ -S "$sock" ]; then
        socket_ok="true"
        socket_path="$sock"
        break
    fi
done

# Uptime and stats (if running and accessible)
uptime_seconds=""
threads_connected=""
threads_running=""
connections_total=""
max_connections=""
queries=""
slow_queries=""
if [ "$mysql_running" = "true" ] && [ "$socket_ok" = "true" ]; then
    # Try to get status via mysqladmin
    stats=$(mysqladmin status 2>/dev/null || echo "")
    if [ -n "$stats" ]; then
        uptime_seconds=$(echo "$stats" | grep -o "Uptime: [0-9]*" | awk "{print \$2}" || echo "")
        threads_connected=$(echo "$stats" | grep -o "Threads: [0-9]*" | awk "{print \$2}" || echo "")
        queries=$(echo "$stats" | grep -o "Queries: [0-9]*" | awk "{print \$2}" || echo "")
        slow_queries=$(echo "$stats" | grep -o "Slow queries: [0-9]*" | awk "{print \$3}" || echo "")
    fi
fi

# Process list count (via ps)
mysql_procs=0
if [ "$mysql_running" = "true" ]; then
    mysql_procs=$(pgrep -c "mysqld\|mariadbd" 2>/dev/null || echo 0)
fi

# Memory usage of MySQL process
mysql_mem_mb=""
if [ -n "$mysql_pid" ] && [ "$mysql_pid" != "0" ]; then
    mysql_mem_kb=$(ps -o rss= -p "$mysql_pid" 2>/dev/null || echo 0)
    mysql_mem_mb=$((mysql_mem_kb / 1024))
fi

# Data directory size
data_dir_size=""
for dir in /var/lib/mysql /data/mysql; do
    if [ -d "$dir" ]; then
        data_dir_size=$(du -sh "$dir" 2>/dev/null | awk "{print \$1}" || echo "unknown")
        break
    fi
done

# Error log check
mysql_errors=""
error_count=0
for log in /var/log/mysql/error.log /var/log/mariadb/mariadb.log /var/log/mysqld.log; do
    if [ -f "$log" ]; then
        error_count=$(tail -100 "$log" 2>/dev/null | grep -ci "error\|warning\|fatal" || echo 0)
        mysql_errors=$(tail -20 "$log" 2>/dev/null | grep -i "error" | tail -5 | while read line; do echo "\"$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-200)\""; done | paste -sd "," -)
        break
    fi
done

# Port 3306 listener
listening_3306=$(ss -tlnp 2>/dev/null | grep ":3306 " | awk "{print \$NF}" | head -1 || echo "none")

# Output JSON
cat << EOF
{
  "script": "30_mysql_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "mysql": {
    "installed": $mysql_installed,
    "type": "$mysql_type",
    "version": "$mysql_version",
    "running": $mysql_running,
    "status": "$mysql_status",
    "pid": ${mysql_pid:-null},
    "process_count": $mysql_procs
  },
  "connection": {
    "socket_available": $socket_ok,
    "socket_path": "${socket_path:-null}",
    "port_3306": "$listening_3306"
  },
  "stats": {
    "uptime_seconds": ${uptime_seconds:-null},
    "threads_connected": ${threads_connected:-null},
    "threads_running": ${threads_running:-null},
    "total_queries": ${queries:-null},
    "slow_queries": ${slow_queries:-null}
  },
  "resources": {
    "memory_mb": ${mysql_mem_mb:-null},
    "data_dir_size": "${data_dir_size:-unknown}"
  },
  "errors": {
    "recent_count": $error_count,
    "recent_entries": [${mysql_errors:-}]
  }
}
EOF
'
