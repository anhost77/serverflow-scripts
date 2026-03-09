#!/bin/bash
# db-backup-schedule.sh - Setup or disable scheduled backups
# Usage: db-backup-schedule.sh <action> <dbtype> <dbname> [frequency] [time] [retention]
# action: enable|disable|status
# frequency: daily|weekly|monthly
# time: HH:MM
# retention: days

ACTION="$1"
DBTYPE="$2"
DBNAME="$3"
FREQUENCY="$4"
TIME="$5"
RETENTION="$6"

if [ -z "$ACTION" ] || [ -z "$DBTYPE" ] || [ -z "$DBNAME" ]; then
    echo '{"error":"Usage: db-backup-schedule.sh <action> <dbtype> <dbname> [frequency] [time] [retention]"}'
    exit 1
fi

SAFE_DBNAME=$(echo "$DBNAME" | sed 's/[^a-zA-Z0-9_]/_/g')
BACKUP_DIR="/var/backups/serverflow-db"
CRON_ID="serverflow-backup-${SAFE_DBNAME}"

case "$ACTION" in
    status)
        line=$(crontab -l 2>/dev/null | grep "# $CRON_ID" || echo "")
        if [ -n "$line" ]; then
            min=$(echo "$line" | awk '{print $1}')
            hour=$(echo "$line" | awk '{print $2}')
            dom=$(echo "$line" | awk '{print $3}')
            dow=$(echo "$line" | awk '{print $5}')
            
            freq="daily"
            [ "$dow" = "0" ] && freq="weekly"
            [ "$dom" = "1" ] && freq="monthly"
            
            ret=$(echo "$line" | grep -oP '\-mtime \+\K[0-9]+' || echo "7")
            
            echo "{\"enabled\":true,\"frequency\":\"$freq\",\"time\":\"$hour:$min\",\"retention\":$ret}"
        else
            echo '{"enabled":false,"frequency":"daily","time":"03:00","retention":7}'
        fi
        ;;
        
    enable)
        [ -z "$FREQUENCY" ] && FREQUENCY="daily"
        [ -z "$TIME" ] && TIME="03:00"
        [ -z "$RETENTION" ] && RETENTION="7"
        
        HOUR=$(echo "$TIME" | cut -d: -f1)
        MIN=$(echo "$TIME" | cut -d: -f2)
        
        case "$FREQUENCY" in
            daily)   CRON_EXPR="$MIN $HOUR * * *" ;;
            weekly)  CRON_EXPR="$MIN $HOUR * * 0" ;;
            monthly) CRON_EXPR="$MIN $HOUR 1 * *" ;;
            *)       echo '{"success":false,"error":"Invalid frequency"}'; exit 1 ;;
        esac
        
        mkdir -p "$BACKUP_DIR"
        
        if [ "$DBTYPE" = "postgresql" ]; then
            BACKUP_CMD="sudo -u postgres pg_dump $DBNAME | gzip > $BACKUP_DIR/${SAFE_DBNAME}_scheduled_\$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).sql.gz"
        else
            BACKUP_CMD="mysqldump $DBNAME | gzip > $BACKUP_DIR/${SAFE_DBNAME}_scheduled_\$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).sql.gz"
        fi
        
        CLEANUP_CMD="find $BACKUP_DIR -name '${SAFE_DBNAME}_scheduled_*.sql.gz' -mtime +$RETENTION -delete"
        
        # Remove existing cron for this DB
        crontab -l 2>/dev/null | grep -v "# $CRON_ID" > /tmp/crons.txt || true
        # Add new cron
        echo "$CRON_EXPR $BACKUP_CMD && $CLEANUP_CMD # $CRON_ID" >> /tmp/crons.txt
        crontab /tmp/crons.txt
        rm /tmp/crons.txt
        
        echo '{"success":true,"enabled":true}'
        ;;
        
    disable)
        crontab -l 2>/dev/null | grep -v "# $CRON_ID" > /tmp/crons.txt || true
        crontab /tmp/crons.txt
        rm /tmp/crons.txt
        echo '{"success":true,"enabled":false}'
        ;;
        
    *)
        echo '{"error":"Invalid action. Use: status|enable|disable"}'
        exit 1
        ;;
esac
