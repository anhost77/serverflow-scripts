#!/bin/bash
# db-backup-list.sh - List database backups
# Usage: db-backup-list.sh <dbname>
# Output: JSON array of backups

DBNAME="$1"

if [ -z "$DBNAME" ]; then
    echo '{"error":"Usage: db-backup-list.sh <dbname>"}'
    exit 1
fi

SAFE_DBNAME=$(echo "$DBNAME" | sed 's/[^a-zA-Z0-9_]/_/g')
BACKUP_DIR="/var/backups/serverflow-db"

mkdir -p "$BACKUP_DIR"

echo '['
first=1
for f in $(ls -t "$BACKUP_DIR/${SAFE_DBNAME}_"*.sql.gz 2>/dev/null); do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    size=$(stat -c%s "$f")
    mtime=$(stat -c%Y "$f")
    created=$(date -d "@$mtime" -Iseconds 2>/dev/null || date -r "$mtime" +%Y-%m-%dT%H:%M:%S 2>/dev/null)
    
    # Determine type from filename
    type="manual"
    echo "$name" | grep -q "_scheduled_" && type="scheduled"
    
    [ $first -eq 0 ] && echo ','
    first=0
    echo "{\"id\":\"$name\",\"filename\":\"$name\",\"size\":\"$size\",\"createdAt\":\"$created\",\"type\":\"$type\"}"
done
echo ']'
