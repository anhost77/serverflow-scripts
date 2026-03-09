#!/bin/bash
# db-backup-delete.sh - Delete a database backup
# Usage: db-backup-delete.sh <backup_id>
# Output: OK or error

BACKUP_ID="$1"

if [ -z "$BACKUP_ID" ]; then
    echo "Usage: db-backup-delete.sh <backup_id>"
    exit 1
fi

# Validate filename format (security)
if ! echo "$BACKUP_ID" | grep -qE '^[a-zA-Z0-9_-]+\.sql\.gz$'; then
    echo "Invalid backup filename"
    exit 1
fi

BACKUP_DIR="/var/backups/serverflow-db"
FILEPATH="$BACKUP_DIR/$BACKUP_ID"

if [ -f "$FILEPATH" ]; then
    rm -f "$FILEPATH"
    echo "OK"
else
    echo "Backup not found"
    exit 1
fi
