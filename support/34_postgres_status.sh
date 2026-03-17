#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - PostgreSQL Status
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check if PostgreSQL is installed and running
pg_installed="false"
pg_running="false"
pg_version=""

if command -v psql &>/dev/null; then
    pg_installed="true"
fi

if systemctl is-active postgresql >/dev/null 2>&1; then
    pg_running="true"
elif systemctl is-active postgresql@* >/dev/null 2>&1; then
    pg_running="true"
fi

# Get version
if [ "$pg_installed" = "true" ]; then
    pg_version=$(psql --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+" | head -1 || echo "unknown")
fi

# Try to connect as postgres user
can_connect="false"
connection_stats=""
active_connections=0
max_connections=0
db_list=""

if [ "$pg_running" = "true" ]; then
    # Try connection
    if sudo -u postgres psql -c "SELECT 1" &>/dev/null 2>&1; then
        can_connect="true"
        
        # Max connections
        max_connections=$(sudo -u postgres psql -t -c "SHOW max_connections" 2>/dev/null | xargs || echo 0)
        
        # Active connections
        active_connections=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_stat_activity" 2>/dev/null | xargs || echo 0)
        
        # Connection by state
        connection_stats=$(sudo -u postgres psql -t -c "
            SELECT json_agg(json_build_object('\''state'\'', COALESCE(state, '\''null'\''), '\''count'\'', count))
            FROM (SELECT state, COUNT(*) as count FROM pg_stat_activity GROUP BY state) s
        " 2>/dev/null | tr -d "\n" || echo "[]")
        
        # Database list with sizes
        db_list=$(sudo -u postgres psql -t -c "
            SELECT json_agg(json_build_object(
                '\''name'\'', datname,
                '\''size_mb'\'', ROUND(pg_database_size(datname) / 1024.0 / 1024.0, 2),
                '\''owner'\'', pg_get_userbyid(datdba)
            ))
            FROM pg_database
            WHERE datistemplate = false
        " 2>/dev/null | tr -d "\n" || echo "[]")
    fi
fi

# Connection utilization
conn_utilization=0
if [ "$max_connections" -gt 0 ] && [ "$active_connections" -gt 0 ]; then
    conn_utilization=$(awk "BEGIN {printf \"%.1f\", ($active_connections / $max_connections) * 100}")
fi

# Active queries
active_queries=""
if [ "$can_connect" = "true" ]; then
    active_queries=$(sudo -u postgres psql -t -c "
        SELECT json_agg(json_build_object(
            '\''pid'\'', pid,
            '\''user'\'', usename,
            '\''database'\'', datname,
            '\''state'\'', state,
            '\''duration_sec'\'', EXTRACT(EPOCH FROM (now() - query_start))::int,
            '\''query'\'', LEFT(query, 100)
        ))
        FROM pg_stat_activity
        WHERE state = '\''active'\'' AND query NOT LIKE '\''%pg_stat_activity%'\''
        ORDER BY query_start ASC
        LIMIT 10
    " 2>/dev/null | tr -d "\n" || echo "[]")
fi

# Locks
locks_count=0
if [ "$can_connect" = "true" ]; then
    locks_count=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_locks WHERE NOT granted" 2>/dev/null | xargs || echo 0)
fi

# Replication status
replication_status=""
if [ "$can_connect" = "true" ]; then
    replication_status=$(sudo -u postgres psql -t -c "
        SELECT json_agg(json_build_object(
            '\''client_addr'\'', client_addr,
            '\''state'\'', state,
            '\''sent_lag'\'', pg_wal_lsn_diff(sent_lsn, write_lsn),
            '\''replay_lag'\'', pg_wal_lsn_diff(sent_lsn, replay_lsn)
        ))
        FROM pg_stat_replication
    " 2>/dev/null | tr -d "\n" || echo "null")
fi

# Oldest transaction
oldest_xact_age=0
if [ "$can_connect" = "true" ]; then
    oldest_xact_age=$(sudo -u postgres psql -t -c "
        SELECT EXTRACT(EPOCH FROM (now() - xact_start))::int
        FROM pg_stat_activity
        WHERE xact_start IS NOT NULL
        ORDER BY xact_start ASC
        LIMIT 1
    " 2>/dev/null | xargs || echo 0)
fi

# Vacuum stats
needs_vacuum=0
if [ "$can_connect" = "true" ]; then
    needs_vacuum=$(sudo -u postgres psql -t -c "
        SELECT COUNT(*)
        FROM pg_stat_user_tables
        WHERE n_dead_tup > n_live_tup * 0.2 AND n_live_tup > 1000
    " 2>/dev/null | xargs || echo 0)
fi

cat << EOF
{
  "script": "34_postgres_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "postgresql": {
    "installed": $pg_installed,
    "running": $pg_running,
    "version": "$pg_version",
    "can_connect": $can_connect
  },
  "connections": {
    "max": $max_connections,
    "active": $active_connections,
    "utilization_percent": $conn_utilization,
    "by_state": ${connection_stats:-[]}
  },
  "databases": ${db_list:-[]},
  "active_queries": ${active_queries:-[]},
  "locks": {
    "waiting": $locks_count
  },
  "health": {
    "oldest_transaction_sec": $oldest_xact_age,
    "tables_need_vacuum": $needs_vacuum
  },
  "replication": ${replication_status:-null}
}
EOF
'
