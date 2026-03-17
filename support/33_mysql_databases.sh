#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - MySQL Databases List & Size
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

# Try to connect
can_connect="false"
databases=""
total_size_mb=0
db_count=0

if [ "$mysql_running" = "true" ]; then
    if mysql -e "SELECT 1" &>/dev/null; then
        can_connect="true"
        
        # Get database sizes
        databases=$(mysql -N -e "
            SELECT JSON_OBJECT(
                '\''name'\'', table_schema,
                '\''size_mb'\'', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2),
                '\''tables'\'', COUNT(*),
                '\''data_mb'\'', ROUND(SUM(data_length) / 1024 / 1024, 2),
                '\''index_mb'\'', ROUND(SUM(index_length) / 1024 / 1024, 2)
            )
            FROM information_schema.TABLES
            WHERE table_schema NOT IN ('\''information_schema'\'', '\''performance_schema'\'', '\''sys'\'')
            GROUP BY table_schema
            ORDER BY SUM(data_length + index_length) DESC
            LIMIT 20
        " 2>/dev/null | paste -sd "," - || echo "")
        
        # Total size
        total_size_mb=$(mysql -N -e "
            SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
            FROM information_schema.TABLES
            WHERE table_schema NOT IN ('\''information_schema'\'', '\''performance_schema'\'', '\''sys'\'')
        " 2>/dev/null || echo 0)
        
        # Database count
        db_count=$(mysql -N -e "
            SELECT COUNT(DISTINCT table_schema)
            FROM information_schema.TABLES
            WHERE table_schema NOT IN ('\''information_schema'\'', '\''performance_schema'\'', '\''sys'\'')
        " 2>/dev/null || echo 0)
    fi
fi

# Largest tables (top 10)
largest_tables=""
if [ "$can_connect" = "true" ]; then
    largest_tables=$(mysql -N -e "
        SELECT JSON_OBJECT(
            '\''database'\'', table_schema,
            '\''table'\'', table_name,
            '\''size_mb'\'', ROUND((data_length + index_length) / 1024 / 1024, 2),
            '\''rows'\'', table_rows,
            '\''engine'\'', engine
        )
        FROM information_schema.TABLES
        WHERE table_schema NOT IN ('\''information_schema'\'', '\''performance_schema'\'', '\''sys'\'')
        ORDER BY (data_length + index_length) DESC
        LIMIT 10
    " 2>/dev/null | paste -sd "," - || echo "")
fi

# Tables without primary key (potential issues)
tables_no_pk=""
no_pk_count=0
if [ "$can_connect" = "true" ]; then
    no_pk_count=$(mysql -N -e "
        SELECT COUNT(*)
        FROM information_schema.TABLES t
        LEFT JOIN information_schema.TABLE_CONSTRAINTS tc
            ON t.table_schema = tc.table_schema
            AND t.table_name = tc.table_name
            AND tc.constraint_type = '\''PRIMARY KEY'\''
        WHERE t.table_schema NOT IN ('\''information_schema'\'', '\''performance_schema'\'', '\''sys'\'', '\''mysql'\'')
        AND t.table_type = '\''BASE TABLE'\''
        AND tc.constraint_name IS NULL
    " 2>/dev/null || echo 0)
    
    if [ "$no_pk_count" -gt 0 ]; then
        tables_no_pk=$(mysql -N -e "
            SELECT JSON_OBJECT('\''database'\'', t.table_schema, '\''table'\'', t.table_name)
            FROM information_schema.TABLES t
            LEFT JOIN information_schema.TABLE_CONSTRAINTS tc
                ON t.table_schema = tc.table_schema
                AND t.table_name = tc.table_name
                AND tc.constraint_type = '\''PRIMARY KEY'\''
            WHERE t.table_schema NOT IN ('\''information_schema'\'', '\''performance_schema'\'', '\''sys'\'', '\''mysql'\'')
            AND t.table_type = '\''BASE TABLE'\''
            AND tc.constraint_name IS NULL
            LIMIT 10
        " 2>/dev/null | paste -sd "," - || echo "")
    fi
fi

# Data directory size (filesystem level)
data_dir_size=""
data_dir=$(mysql -N -e "SHOW VARIABLES LIKE '\''datadir'\''" 2>/dev/null | awk "{print \$2}" || echo "/var/lib/mysql")
if [ -d "$data_dir" ]; then
    data_dir_size=$(du -sh "$data_dir" 2>/dev/null | awk "{print \$1}" || echo "unknown")
fi

cat << EOF
{
  "script": "33_mysql_databases",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "mysql": {
    "running": $mysql_running,
    "type": "$mysql_type",
    "can_connect": $can_connect
  },
  "summary": {
    "database_count": $db_count,
    "total_size_mb": ${total_size_mb:-0},
    "data_directory": "$data_dir",
    "data_dir_size": "$data_dir_size"
  },
  "databases": [${databases:-}],
  "largest_tables": [${largest_tables:-}],
  "tables_without_pk": {
    "count": $no_pk_count,
    "tables": [${tables_no_pk:-}]
  }
}
EOF
'
