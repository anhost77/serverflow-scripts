#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - MySQL Connections Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check if MySQL/MariaDB is running
mysql_running="false"
mysql_type=""

if systemctl is-active mysql >/dev/null 2>&1; then
    mysql_running="true"
    mysql_type="mysql"
elif systemctl is-active mariadb >/dev/null 2>&1; then
    mysql_running="true"
    mysql_type="mariadb"
elif systemctl is-active mysqld >/dev/null 2>&1; then
    mysql_running="true"
    mysql_type="mysqld"
fi

# Try to connect and get stats
can_connect="false"
max_connections=0
current_connections=0
threads_running=0
threads_connected=0
aborted_clients=0
aborted_connects=0

if [ "$mysql_running" = "true" ]; then
    # Try socket auth first (no password needed for root on most configs)
    if mysql -e "SELECT 1" &>/dev/null; then
        can_connect="true"
        
        # Get max connections
        max_connections=$(mysql -N -e "SHOW VARIABLES LIKE '\''max_connections'\''" 2>/dev/null | awk "{print \$2}" || echo 0)
        
        # Get current connection stats
        current_connections=$(mysql -N -e "SHOW STATUS LIKE '\''Threads_connected'\''" 2>/dev/null | awk "{print \$2}" || echo 0)
        threads_running=$(mysql -N -e "SHOW STATUS LIKE '\''Threads_running'\''" 2>/dev/null | awk "{print \$2}" || echo 0)
        threads_connected=$(mysql -N -e "SHOW STATUS LIKE '\''Threads_connected'\''" 2>/dev/null | awk "{print \$2}" || echo 0)
        
        # Aborted stats
        aborted_clients=$(mysql -N -e "SHOW STATUS LIKE '\''Aborted_clients'\''" 2>/dev/null | awk "{print \$2}" || echo 0)
        aborted_connects=$(mysql -N -e "SHOW STATUS LIKE '\''Aborted_connects'\''" 2>/dev/null | awk "{print \$2}" || echo 0)
    fi
fi

# Connection utilization
conn_utilization=0
if [ "$max_connections" -gt 0 ] && [ "$current_connections" -gt 0 ]; then
    conn_utilization=$(awk "BEGIN {printf \"%.1f\", ($current_connections / $max_connections) * 100}")
fi

# Warning level
conn_warning="ok"
if [ "${conn_utilization%.*}" -gt 70 ]; then
    conn_warning="warning"
fi
if [ "${conn_utilization%.*}" -gt 90 ]; then
    conn_warning="critical"
fi

# Process list (top 10 longest running)
processlist=""
if [ "$can_connect" = "true" ]; then
    processlist=$(mysql -N -e "SELECT JSON_OBJECT('\''id'\'', ID, '\''user'\'', USER, '\''host'\'', HOST, '\''db'\'', IFNULL(DB, '\''null'\''), '\''command'\'', COMMAND, '\''time'\'', TIME, '\''state'\'', IFNULL(STATE, '\''null'\''), '\''info'\'', IFNULL(LEFT(INFO, 100), '\''null'\'')) FROM information_schema.PROCESSLIST WHERE COMMAND != '\''Sleep'\'' ORDER BY TIME DESC LIMIT 10" 2>/dev/null | paste -sd "," - || echo "")
fi

# Sleeping connections
sleeping_connections=0
if [ "$can_connect" = "true" ]; then
    sleeping_connections=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE COMMAND = '\''Sleep'\''" 2>/dev/null || echo 0)
fi

# Connections by user
connections_by_user=""
if [ "$can_connect" = "true" ]; then
    connections_by_user=$(mysql -N -e "SELECT JSON_OBJECT('\''user'\'', USER, '\''count'\'', COUNT(*)) FROM information_schema.PROCESSLIST GROUP BY USER ORDER BY COUNT(*) DESC LIMIT 10" 2>/dev/null | paste -sd "," - || echo "")
fi

# Connections by host
connections_by_host=""
if [ "$can_connect" = "true" ]; then
    connections_by_host=$(mysql -N -e "SELECT JSON_OBJECT('\''host'\'', SUBSTRING_INDEX(HOST, '\'':'\'', 1), '\''count'\'', COUNT(*)) FROM information_schema.PROCESSLIST GROUP BY SUBSTRING_INDEX(HOST, '\'':'\'', 1) ORDER BY COUNT(*) DESC LIMIT 10" 2>/dev/null | paste -sd "," - || echo "")
fi

# Wait timeout config
wait_timeout=0
interactive_timeout=0
if [ "$can_connect" = "true" ]; then
    wait_timeout=$(mysql -N -e "SHOW VARIABLES LIKE '\''wait_timeout'\''" 2>/dev/null | awk "{print \$2}" || echo 0)
    interactive_timeout=$(mysql -N -e "SHOW VARIABLES LIKE '\''interactive_timeout'\''" 2>/dev/null | awk "{print \$2}" || echo 0)
fi

cat << EOF
{
  "script": "32_mysql_connections",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "mysql": {
    "running": $mysql_running,
    "type": "$mysql_type",
    "can_connect": $can_connect
  },
  "connections": {
    "max": $max_connections,
    "current": $current_connections,
    "sleeping": $sleeping_connections,
    "threads_running": $threads_running,
    "utilization_percent": $conn_utilization,
    "warning_level": "$conn_warning"
  },
  "aborted": {
    "clients": $aborted_clients,
    "connects": $aborted_connects
  },
  "timeouts": {
    "wait_timeout": $wait_timeout,
    "interactive_timeout": $interactive_timeout
  },
  "active_queries": [${processlist:-}],
  "by_user": [${connections_by_user:-}],
  "by_host": [${connections_by_host:-}]
}
EOF
'
