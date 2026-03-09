#!/bin/bash
# db-backup-content.sh - Get backup file content (base64 encoded)
# Usage: db-backup-content.sh <backup_id>
# Output: base64 encoded file content

BACKUP_ID="$1"

if [ -z "$BACKUP_ID" ]; then
    echo "Usage: db-backup-content.sh <backup_id>"
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
    cat "$FILEPATH" | base64
else
    echo "Backup not found"
    exit 1
fi
