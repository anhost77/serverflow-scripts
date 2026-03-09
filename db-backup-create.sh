#!/bin/bash
# db-backup-create.sh - Create database backup
# Usage: db-backup-create.sh <dbtype> <dbname>
# Output: JSON with success, filename, size

DBTYPE="$1"
DBNAME="$2"

if [ -z "$DBTYPE" ] || [ -z "$DBNAME" ]; then
    echo '{"success":false,"error":"Usage: db-backup-create.sh <dbtype> <dbname>"}'
    exit 1
fi

# Sanitize database name
SAFE_DBNAME=$(echo "$DBNAME" | sed 's/[^a-zA-Z0-9_]/_/g')
BACKUP_DIR="/var/backups/serverflow-db"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="${SAFE_DBNAME}_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

if [ "$DBTYPE" = "postgresql" ]; then
    sudo -u postgres pg_dump "$DBNAME" 2>/dev/null | gzip > "$BACKUP_DIR/$FILENAME"
elif [ "$DBTYPE" = "mysql" ]; then
    mysqldump "$DBNAME" 2>/dev/null | gzip > "$BACKUP_DIR/$FILENAME"
else
    echo '{"success":false,"error":"Unsupported database type"}'
    exit 1
fi

if [ -f "$BACKUP_DIR/$FILENAME" ] && [ -s "$BACKUP_DIR/$FILENAME" ]; then
    SIZE=$(stat -c%s "$BACKUP_DIR/$FILENAME")
    echo "{\"success\":true,\"filename\":\"$FILENAME\",\"size\":\"$SIZE\"}"
else
    rm -f "$BACKUP_DIR/$FILENAME" 2>/dev/null
    echo '{"success":false,"error":"Backup failed - empty or missing file"}'
    exit 1
fi
