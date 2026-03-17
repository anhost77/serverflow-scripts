#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Dovecot Status
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check Dovecot installation and status
dovecot_installed="false"
dovecot_running="false"
dovecot_version=""

if command -v dovecot &>/dev/null || [ -f /usr/sbin/dovecot ]; then
    dovecot_installed="true"
    dovecot_version=$(dovecot --version 2>/dev/null | head -1 || echo "unknown")
fi

if systemctl is-active dovecot >/dev/null 2>&1; then
    dovecot_running="true"
fi

# Get running protocols
protocols=""
if [ "$dovecot_running" = "true" ]; then
    protocols=$(doveconf -n protocols 2>/dev/null | cut -d= -f2 | xargs || echo "")
fi

# Check listening ports
imap_143=$(ss -tlnp 2>/dev/null | grep ":143 " | head -1 || echo "")
imaps_993=$(ss -tlnp 2>/dev/null | grep ":993 " | head -1 || echo "")
pop3_110=$(ss -tlnp 2>/dev/null | grep ":110 " | head -1 || echo "")
pop3s_995=$(ss -tlnp 2>/dev/null | grep ":995 " | head -1 || echo "")

# SSL configuration
ssl_enabled="false"
ssl_cert=""
if doveconf -n ssl 2>/dev/null | grep -qi "yes"; then
    ssl_enabled="true"
    ssl_cert=$(doveconf -n ssl_cert 2>/dev/null | cut -d= -f2 | xargs | head -c 100 || echo "")
fi

# Mail location
mail_location=""
mail_location=$(doveconf -n mail_location 2>/dev/null | cut -d= -f2 | xargs || echo "")

# Connected users (if doveadm available)
connected_users=0
connections=""
if command -v doveadm &>/dev/null && [ "$dovecot_running" = "true" ]; then
    connections=$(doveadm who 2>/dev/null | tail -n +2 | head -20 | while read -r line; do
        user=$(echo "$line" | awk "{print \$1}")
        proto=$(echo "$line" | awk "{print \$2}")
        ip=$(echo "$line" | awk "{print \$3}")
        echo "{\"user\":\"$user\",\"protocol\":\"$proto\",\"ip\":\"$ip\"}"
    done | paste -sd "," - | tr -d "\n")
    
    connected_users=$(doveadm who 2>/dev/null | tail -n +2 | wc -l || echo 0)
fi

# Authentication failures
auth_failures=0
recent_failures=""
mail_log=""
[ -f /var/log/mail.log ] && mail_log="/var/log/mail.log"
[ -f /var/log/maillog ] && mail_log="/var/log/maillog"

if [ -n "$mail_log" ]; then
    auth_failures=$(tail -500 "$mail_log" 2>/dev/null | grep -ci "auth failed\|authentication failure\|password mismatch" || echo 0)
    recent_failures=$(tail -200 "$mail_log" 2>/dev/null | grep -i "auth failed\|authentication failure" | tail -5 | while read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Login attempts (successful)
login_success=0
if [ -n "$mail_log" ]; then
    login_success=$(tail -500 "$mail_log" 2>/dev/null | grep -ci "imap-login\|pop3-login" | head -1 || echo 0)
fi

# Check mailbox storage
mailbox_storage=""
storage_warning="false"
mail_dirs=("/var/mail" "/var/vmail" "/home/vmail")
for dir in "${mail_dirs[@]}"; do
    if [ -d "$dir" ]; then
        size=$(du -sh "$dir" 2>/dev/null | awk "{print \$1}" || echo "?")
        count=$(find "$dir" -type f 2>/dev/null | wc -l || echo 0)
        mailbox_storage="$mailbox_storage{\"path\":\"$dir\",\"size\":\"$size\",\"files\":$count},"
        
        # Check disk usage
        usage=$(df "$dir" 2>/dev/null | tail -1 | awk "{print \$5}" | tr -d "%" || echo 0)
        if [ "$usage" -gt 90 ]; then
            storage_warning="true"
        fi
    fi
done
mailbox_storage=$(echo "$mailbox_storage" | sed "s/,$//" | tr -d "\n")

# Dovecot errors
error_count=0
recent_errors=""
if [ -n "$mail_log" ]; then
    error_count=$(tail -500 "$mail_log" 2>/dev/null | grep -i "dovecot.*error\|dovecot.*fatal\|dovecot.*panic" | wc -l || echo 0)
    recent_errors=$(tail -200 "$mail_log" 2>/dev/null | grep -i "dovecot.*error\|dovecot.*warning" | tail -5 | while read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# LMTP status (for Postfix integration)
lmtp_running="false"
if ss -tlnp 2>/dev/null | grep -q "dovecot.*lmtp\|:24 "; then
    lmtp_running="true"
fi

cat << EOF
{
  "script": "62_dovecot_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "dovecot": {
    "installed": $dovecot_installed,
    "running": $dovecot_running,
    "version": "$dovecot_version",
    "protocols": "$protocols"
  },
  "ports": {
    "imap_143": "${imap_143:-not listening}",
    "imaps_993": "${imaps_993:-not listening}",
    "pop3_110": "${pop3_110:-not listening}",
    "pop3s_995": "${pop3s_995:-not listening}"
  },
  "ssl": {
    "enabled": $ssl_enabled,
    "cert": "$ssl_cert"
  },
  "mail_location": "$mail_location",
  "lmtp_running": $lmtp_running,
  "connections": {
    "current_users": $connected_users,
    "list": [${connections:-}]
  },
  "authentication": {
    "failures_recent": $auth_failures,
    "successes_recent": $login_success,
    "recent_failures": [${recent_failures:-}]
  },
  "storage": {
    "warning": $storage_warning,
    "locations": [${mailbox_storage:-}]
  },
  "errors": {
    "count": $error_count,
    "recent": [${recent_errors:-}]
  }
}
EOF
'
