#!/bin/bash
# db-backup-restore.sh - Restore database from backup
# Usage: db-backup-restore.sh <dbtype> <dbname> <backup_id>
# Output: OK or error

DBTYPE="$1"
DBNAME="$2"
BACKUP_ID="$3"

if [ -z "$DBTYPE" ] || [ -z "$DBNAME" ] || [ -z "$BACKUP_ID" ]; then
    echo "Usage: db-backup-restore.sh <dbtype> <dbname> <backup_id>"
    exit 1
fi

# Validate filename format (security)
if ! echo "$BACKUP_ID" | grep -qE '^[a-zA-Z0-9_-]+\.sql\.gz$'; then
    echo "Invalid backup filename"
    exit 1
fi

SAFE_DBNAME=$(echo "$DBNAME" | sed 's/[^a-zA-Z0-9_]/_/g')
BACKUP_DIR="/var/backups/serverflow-db"
FILEPATH="$BACKUP_DIR/$BACKUP_ID"

if [ ! -f "$FILEPATH" ]; then
    echo "Backup not found"
    exit 1
fi

if [ "$DBTYPE" = "postgresql" ]; then
    # Drop and recreate for clean restore
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS $SAFE_DBNAME;" 2>/dev/null
    sudo -u postgres psql -c "CREATE DATABASE $SAFE_DBNAME;" 2>/dev/null
    gunzip -c "$FILEPATH" | sudo -u postgres psql "$SAFE_DBNAME" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "Restore failed"
        exit 1
    fi
elif [ "$DBTYPE" = "mysql" ]; then
    gunzip -c "$FILEPATH" | mysql "$SAFE_DBNAME" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "Restore failed"
        exit 1
    fi
else
    echo "Unsupported database type"
    exit 1
fi
