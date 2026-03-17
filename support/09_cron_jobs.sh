#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Cron Jobs List
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# System crontabs
system_crons=""
if [ -f /etc/crontab ]; then
    system_crons=$(grep -v "^#" /etc/crontab 2>/dev/null | grep -v "^$" | grep -v "^SHELL\|^PATH\|^MAILTO" | while IFS= read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | tr -d "\t" | xargs)
        [ -n "$escaped" ] && echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Cron.d directory
crond_jobs=""
if [ -d /etc/cron.d ]; then
    crond_jobs=$(for f in /etc/cron.d/*; do
        [ -f "$f" ] || continue
        fname=$(basename "$f")
        grep -v "^#" "$f" 2>/dev/null | grep -v "^$" | grep -v "^SHELL\|^PATH\|^MAILTO" | while IFS= read -r line; do
            escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | tr -d "\t" | xargs)
            [ -n "$escaped" ] && echo "{\"file\":\"$fname\",\"job\":\"$escaped\"}"
        done
    done | paste -sd "," - | tr -d "\n")
fi

# User crontabs
user_crons=""
if [ -d /var/spool/cron/crontabs ]; then
    user_crons=$(for f in /var/spool/cron/crontabs/*; do
        [ -f "$f" ] || continue
        user=$(basename "$f")
        count=$(grep -cv "^#\|^$" "$f" 2>/dev/null || echo 0)
        jobs=$(grep -v "^#" "$f" 2>/dev/null | grep -v "^$" | head -5 | while IFS= read -r line; do
            escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-100)
            echo "\"$escaped\""
        done | paste -sd "," -)
        echo "{\"user\":\"$user\",\"count\":$count,\"jobs\":[$jobs]}"
    done | paste -sd "," - | tr -d "\n")
elif [ -d /var/spool/cron ]; then
    # RedHat style
    user_crons=$(for f in /var/spool/cron/*; do
        [ -f "$f" ] || continue
        user=$(basename "$f")
        count=$(grep -cv "^#\|^$" "$f" 2>/dev/null || echo 0)
        jobs=$(grep -v "^#" "$f" 2>/dev/null | grep -v "^$" | head -5 | while IFS= read -r line; do
            escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-100)
            echo "\"$escaped\""
        done | paste -sd "," -)
        echo "{\"user\":\"$user\",\"count\":$count,\"jobs\":[$jobs]}"
    done | paste -sd "," - | tr -d "\n")
fi

# Periodic directories
hourly_count=$(ls -1 /etc/cron.hourly 2>/dev/null | wc -l || echo 0)
daily_count=$(ls -1 /etc/cron.daily 2>/dev/null | wc -l || echo 0)
weekly_count=$(ls -1 /etc/cron.weekly 2>/dev/null | wc -l || echo 0)
monthly_count=$(ls -1 /etc/cron.monthly 2>/dev/null | wc -l || echo 0)

# List periodic scripts
daily_scripts=$(ls -1 /etc/cron.daily 2>/dev/null | head -10 | while read -r f; do echo "\"$f\""; done | paste -sd "," - | tr -d "\n")
hourly_scripts=$(ls -1 /etc/cron.hourly 2>/dev/null | head -10 | while read -r f; do echo "\"$f\""; done | paste -sd "," - | tr -d "\n")

# Systemd timers (if available)
timers=""
if command -v systemctl &>/dev/null; then
    timers=$(systemctl list-timers --no-pager 2>/dev/null | tail -n +2 | head -15 | while IFS= read -r line; do
        [ -z "$line" ] && continue
        echo "$line" | grep -q "^$\|timers listed" && continue
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | xargs)
        [ -n "$escaped" ] && echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Recent cron executions from logs
recent_runs=""
if command -v journalctl &>/dev/null; then
    recent_runs=$(journalctl -u cron --since "1 hour ago" --no-pager 2>/dev/null | grep -i "cmd\|command" | tail -10 | while IFS= read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

cat << EOF
{
  "script": "09_cron_jobs",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "system_crontab": [${system_crons:-}],
  "cron_d_jobs": [${crond_jobs:-}],
  "user_crontabs": [${user_crons:-}],
  "periodic": {
    "hourly": {"count": $hourly_count, "scripts": [${hourly_scripts:-}]},
    "daily": {"count": $daily_count, "scripts": [${daily_scripts:-}]},
    "weekly": {"count": $weekly_count},
    "monthly": {"count": $monthly_count}
  },
  "systemd_timers": [${timers:-}],
  "recent_executions": [${recent_runs:-}]
}
EOF
'
