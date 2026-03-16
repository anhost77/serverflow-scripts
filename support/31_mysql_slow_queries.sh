#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - MySQL Slow Query Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check if MySQL is running
mysql_running="false"
for service in mysql mariadb mysqld; do
    if systemctl is-active $service >/dev/null 2>&1; then
        mysql_running="true"
        break
    fi
done

if [ "$mysql_running" = "false" ]; then
    cat << EOF
{
  "script": "31_mysql_slow_queries",
  "timestamp": "$(date -Iseconds)",
  "status": "error",
  "error": "MySQL/MariaDB is not running"
}
EOF
    exit 0
fi

# Find slow query log
slow_log=""
slow_log_enabled="false"
for log in /var/log/mysql/mysql-slow.log /var/log/mysql/slow.log /var/lib/mysql/*-slow.log /var/log/mariadb/slow.log; do
    if [ -f "$log" ]; then
        slow_log="$log"
        slow_log_enabled="true"
        break
    fi
done

# Get slow log size
slow_log_size=""
if [ -n "$slow_log" ]; then
    slow_log_size=$(du -h "$slow_log" 2>/dev/null | awk "{print \$1}" || echo "0")
fi

# Parse recent slow queries
slow_queries=""
slow_count=0
if [ -n "$slow_log" ] && [ -f "$slow_log" ]; then
    # Count total slow queries in last 1000 lines
    slow_count=$(tail -1000 "$slow_log" 2>/dev/null | grep -c "^# Time:" || echo 0)
    
    # Extract last 5 slow queries with basic info
    # Parse the slow log format
    slow_queries=$(tail -500 "$slow_log" 2>/dev/null | awk "
        /^# Time:/ { 
            time=\$3\" \"\$4
        }
        /^# Query_time:/ { 
            query_time=\$3
            gsub(/Query_time: /,\"\",query_time)
        }
        /^# User@Host:/ {
            user=\$3
        }
        /^SELECT|^UPDATE|^INSERT|^DELETE/ && length(\$0) > 5 {
            query=substr(\$0, 1, 150)
            gsub(/\"/,\"\\\\\\\\\\\"\",query)
            print \"{\\\"time\\\":\\\"\"time\"\\\",\\\"duration\\\":\\\"\"query_time\"\\\",\\\"user\\\":\\\"\"user\"\\\",\\\"query\\\":\\\"\"query\"\\\"}\"
            time=\"\"
            query_time=\"\"
            user=\"\"
        }
    " | tail -5 | paste -sd "," -)
fi

# Get processlist if accessible
active_queries=""
active_count=0
processlist=$(mysql -N -e "SHOW PROCESSLIST" 2>/dev/null || echo "")
if [ -n "$processlist" ]; then
    active_count=$(echo "$processlist" | grep -cv "Sleep\|Command" || echo 0)
    active_queries=$(echo "$processlist" | grep -v "Sleep" | head -5 | while read line; do
        id=$(echo "$line" | awk "{print \$1}")
        user=$(echo "$line" | awk "{print \$2}")
        host=$(echo "$line" | awk "{print \$3}")
        db=$(echo "$line" | awk "{print \$4}")
        command=$(echo "$line" | awk "{print \$5}")
        time=$(echo "$line" | awk "{print \$6}")
        state=$(echo "$line" | awk "{print \$7}")
        query=$(echo "$line" | cut -f8- | cut -c1-100 | sed "s/\"/\\\\\"/g")
        echo "{\"id\":$id,\"user\":\"$user\",\"db\":\"${db:-null}\",\"command\":\"$command\",\"time\":${time:-0},\"query\":\"$query\"}"
    done | paste -sd "," -)
fi

# Long running queries (> 5 seconds)
long_queries=""
if [ -n "$processlist" ]; then
    long_queries=$(echo "$processlist" | awk "\$6 > 5 && \$5 != \"Sleep\"" | head -5 | while read line; do
        id=$(echo "$line" | awk "{print \$1}")
        time=$(echo "$line" | awk "{print \$6}")
        query=$(echo "$line" | cut -f8- | cut -c1-100 | sed "s/\"/\\\\\"/g")
        echo "{\"id\":$id,\"duration_seconds\":$time,\"query\":\"$query\"}"
    done | paste -sd "," -)
fi

# Output JSON
cat << EOF
{
  "script": "31_mysql_slow_queries",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "slow_query_log": {
    "enabled": $slow_log_enabled,
    "path": "${slow_log:-null}",
    "size": "${slow_log_size:-0}",
    "recent_count": $slow_count
  },
  "recent_slow_queries": [${slow_queries:-}],
  "current_activity": {
    "active_queries_count": $active_count,
    "active_queries": [${active_queries:-}],
    "long_running_queries": [${long_queries:-}]
  }
}
EOF
'
