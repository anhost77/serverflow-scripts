#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - System Logs Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check log sources
has_journald="false"
has_syslog="false"

if command -v journalctl &>/dev/null && journalctl -n 1 &>/dev/null; then
    has_journald="true"
fi
if [ -f /var/log/syslog ] || [ -f /var/log/messages ]; then
    has_syslog="true"
fi

# Get recent errors from journald (last 1 hour)
journald_errors=""
journald_error_count=0
if [ "$has_journald" = "true" ]; then
    journald_error_count=$(journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | wc -l || echo 0)
    journald_errors=$(journalctl -p err --since "1 hour ago" --no-pager -n 20 2>/dev/null | tail -15 | while IFS= read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-200)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Get recent critical/alert/emergency
critical_count=0
critical_entries=""
if [ "$has_journald" = "true" ]; then
    critical_count=$(journalctl -p crit --since "24 hours ago" --no-pager 2>/dev/null | wc -l || echo 0)
    critical_entries=$(journalctl -p crit --since "24 hours ago" --no-pager -n 10 2>/dev/null | tail -10 | while IFS= read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-200)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Syslog errors (fallback)
syslog_errors=""
if [ "$has_syslog" = "true" ]; then
    log_file="/var/log/syslog"
    [ ! -f "$log_file" ] && log_file="/var/log/messages"
    if [ -f "$log_file" ]; then
        syslog_errors=$(grep -i "error\|fail\|crit" "$log_file" 2>/dev/null | tail -10 | while IFS= read -r line; do
            escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-200)
            echo "\"$escaped\""
        done | paste -sd "," - | tr -d "\n")
    fi
fi

# OOM killer events (last 24h)
oom_count=0
oom_events=""
if [ "$has_journald" = "true" ]; then
    oom_count=$(journalctl --since "24 hours ago" --no-pager 2>/dev/null | grep -c "Out of memory\|oom-killer\|Killed process" || echo 0)
    if [ "$oom_count" -gt 0 ]; then
        oom_events=$(journalctl --since "24 hours ago" --no-pager 2>/dev/null | grep "Out of memory\|oom-killer\|Killed process" | tail -5 | while IFS= read -r line; do
            escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)
            echo "\"$escaped\""
        done | paste -sd "," - | tr -d "\n")
    fi
fi

# Disk errors
disk_errors=0
if [ "$has_journald" = "true" ]; then
    disk_errors=$(journalctl --since "24 hours ago" --no-pager 2>/dev/null | grep -ci "I/O error\|disk error\|read error\|write error\|bad sector" || echo 0)
fi

# Service failures (last 24h)
failed_services=""
if [ "$has_journald" = "true" ]; then
    failed_services=$(journalctl --since "24 hours ago" --no-pager 2>/dev/null | grep -i "failed\|failure" | grep -i "service\|unit" | tail -10 | while IFS= read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Kernel panics/oops
kernel_issues=0
if [ "$has_journald" = "true" ]; then
    kernel_issues=$(journalctl -k --since "7 days ago" --no-pager 2>/dev/null | grep -ci "panic\|oops\|bug\|kernel bug" || echo 0)
fi

cat << EOF
{
  "script": "08_system_logs",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "log_sources": {
    "journald": $has_journald,
    "syslog": $has_syslog
  },
  "errors_last_hour": {
    "count": $journald_error_count,
    "entries": [${journald_errors:-}]
  },
  "critical_last_24h": {
    "count": $critical_count,
    "entries": [${critical_entries:-}]
  },
  "oom_events": {
    "count": $oom_count,
    "entries": [${oom_events:-}]
  },
  "disk_errors_24h": $disk_errors,
  "kernel_issues_7d": $kernel_issues,
  "failed_services": [${failed_services:-}],
  "syslog_errors": [${syslog_errors:-}]
}
EOF
'
