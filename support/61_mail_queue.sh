#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Mail Queue Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Detect MTA
mta="unknown"
mta_running="false"

if systemctl is-active postfix >/dev/null 2>&1; then
    mta="postfix"
    mta_running="true"
elif systemctl is-active exim4 >/dev/null 2>&1 || systemctl is-active exim >/dev/null 2>&1; then
    mta="exim"
    mta_running="true"
elif systemctl is-active sendmail >/dev/null 2>&1; then
    mta="sendmail"
    mta_running="true"
fi

# Queue stats
queue_total=0
queue_deferred=0
queue_active=0
queue_corrupt=0
oldest_message=""
queue_size_bytes=0

# Get queue details based on MTA
queue_items=""

if [ "$mta" = "postfix" ]; then
    # Postfix queue
    if command -v postqueue &>/dev/null; then
        queue_output=$(postqueue -j 2>/dev/null || echo "")
        
        if [ -n "$queue_output" ]; then
            queue_total=$(echo "$queue_output" | wc -l)
            
            # Parse queue items (first 20)
            queue_items=$(echo "$queue_output" | head -20 | while read -r line; do
                echo "$line"
            done | paste -sd "," - | tr -d "\n")
        fi
    fi
    
    # Queue directories
    queue_deferred=$(find /var/spool/postfix/deferred -type f 2>/dev/null | wc -l || echo 0)
    queue_active=$(find /var/spool/postfix/active -type f 2>/dev/null | wc -l || echo 0)
    queue_corrupt=$(find /var/spool/postfix/corrupt -type f 2>/dev/null | wc -l || echo 0)
    
    # Queue size
    queue_size_bytes=$(du -sb /var/spool/postfix/deferred /var/spool/postfix/active 2>/dev/null | awk "{sum+=\$1} END {print sum}" || echo 0)
    
    # Oldest message
    oldest_file=$(find /var/spool/postfix/deferred -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | head -1 | awk "{print \$2}")
    if [ -n "$oldest_file" ]; then
        oldest_ts=$(stat -c %Y "$oldest_file" 2>/dev/null || echo 0)
        oldest_message=$(date -d "@$oldest_ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
    fi
    
elif [ "$mta" = "exim" ]; then
    # Exim queue
    if command -v exim &>/dev/null; then
        queue_total=$(exim -bpc 2>/dev/null || echo 0)
        
        # Get queue items
        queue_items=$(exim -bp 2>/dev/null | head -40 | grep -E "^[0-9]" | while read -r line; do
            id=$(echo "$line" | awk "{print \$3}")
            size=$(echo "$line" | awk "{print \$1}")
            time=$(echo "$line" | awk "{print \$2}")
            echo "{\"id\":\"$id\",\"size\":\"$size\",\"time\":\"$time\"}"
        done | paste -sd "," - | tr -d "\n")
    fi
fi

# Convert bytes to human readable
queue_size_human="0B"
if [ "$queue_size_bytes" -gt 0 ]; then
    queue_size_human=$(numfmt --to=iec-i --suffix=B "$queue_size_bytes" 2>/dev/null || echo "${queue_size_bytes}B")
fi

# Deferred reasons (Postfix)
deferred_reasons=""
if [ "$mta" = "postfix" ] && [ "$queue_deferred" -gt 0 ]; then
    mail_log=""
    [ -f /var/log/mail.log ] && mail_log="/var/log/mail.log"
    [ -f /var/log/maillog ] && mail_log="/var/log/maillog"
    
    if [ -n "$mail_log" ]; then
        deferred_reasons=$(grep "status=deferred" "$mail_log" 2>/dev/null | tail -50 | grep -oP "\(.*\)" | sort | uniq -c | sort -rn | head -5 | while read -r count reason; do
            reason_escaped=$(echo "$reason" | sed "s/\"/\\\\\"/g" | cut -c1-100)
            echo "{\"count\":$count,\"reason\":\"$reason_escaped\"}"
        done | paste -sd "," - | tr -d "\n")
    fi
fi

# Top recipients in queue
top_recipients=""
if [ "$mta" = "postfix" ] && command -v postqueue &>/dev/null; then
    top_recipients=$(postqueue -j 2>/dev/null | grep -oP "\"recipient\":\"[^\"]+\"" | cut -d: -f2 | tr -d "\"" | sort | uniq -c | sort -rn | head -10 | awk "{printf \"{\\\"recipient\\\":\\\"%s\\\",\\\"count\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Top senders in queue
top_senders=""
if [ "$mta" = "postfix" ] && command -v postqueue &>/dev/null; then
    top_senders=$(postqueue -j 2>/dev/null | grep -oP "\"sender\":\"[^\"]+\"" | cut -d: -f2 | tr -d "\"" | sort | uniq -c | sort -rn | head -10 | awk "{printf \"{\\\"sender\\\":\\\"%s\\\",\\\"count\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Warning level
warning_level="ok"
if [ "$queue_deferred" -gt 100 ]; then
    warning_level="warning"
fi
if [ "$queue_deferred" -gt 1000 ]; then
    warning_level="critical"
fi

cat << EOF
{
  "script": "61_mail_queue",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "mta": {
    "type": "$mta",
    "running": $mta_running
  },
  "queue": {
    "total": $queue_total,
    "active": $queue_active,
    "deferred": $queue_deferred,
    "corrupt": $queue_corrupt,
    "size": "$queue_size_human",
    "size_bytes": $queue_size_bytes,
    "oldest_message": "$oldest_message",
    "warning_level": "$warning_level"
  },
  "deferred_reasons": [${deferred_reasons:-}],
  "top_recipients": [${top_recipients:-}],
  "top_senders": [${top_senders:-}],
  "queue_items": [${queue_items:-}]
}
EOF
'
