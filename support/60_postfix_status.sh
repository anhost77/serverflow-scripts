#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Postfix Status
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check Postfix installation and status
postfix_installed="false"
postfix_running="false"
postfix_version=""

if command -v postfix &>/dev/null || [ -f /usr/sbin/postfix ]; then
    postfix_installed="true"
    postfix_version=$(postconf -d mail_version 2>/dev/null | cut -d= -f2 | xargs || echo "unknown")
fi

if systemctl is-active postfix >/dev/null 2>&1; then
    postfix_running="true"
fi

# Get main.cf config
hostname=""
mydomain=""
inet_interfaces=""
relay_host=""

if [ -f /etc/postfix/main.cf ]; then
    hostname=$(postconf myhostname 2>/dev/null | cut -d= -f2 | xargs || echo "")
    mydomain=$(postconf mydomain 2>/dev/null | cut -d= -f2 | xargs || echo "")
    inet_interfaces=$(postconf inet_interfaces 2>/dev/null | cut -d= -f2 | xargs || echo "")
    relay_host=$(postconf relayhost 2>/dev/null | cut -d= -f2 | xargs || echo "")
fi

# Queue status
queue_size=0
queue_deferred=0
queue_active=0
queue_hold=0

if [ "$postfix_running" = "true" ]; then
    if command -v mailq &>/dev/null; then
        queue_output=$(mailq 2>/dev/null || echo "")
        queue_size=$(echo "$queue_output" | grep -c "^[A-F0-9]" || echo 0)
        
        # Count by queue type
        queue_deferred=$(find /var/spool/postfix/deferred -type f 2>/dev/null | wc -l || echo 0)
        queue_active=$(find /var/spool/postfix/active -type f 2>/dev/null | wc -l || echo 0)
        queue_hold=$(find /var/spool/postfix/hold -type f 2>/dev/null | wc -l || echo 0)
    fi
fi

# Recent mail log entries
recent_errors=""
mail_log=""
if [ -f /var/log/mail.log ]; then
    mail_log="/var/log/mail.log"
elif [ -f /var/log/maillog ]; then
    mail_log="/var/log/maillog"
fi

error_count=0
if [ -n "$mail_log" ] && [ -f "$mail_log" ]; then
    error_count=$(tail -500 "$mail_log" 2>/dev/null | grep -ci "error\|warning\|fatal\|reject" || echo 0)
    recent_errors=$(tail -100 "$mail_log" 2>/dev/null | grep -i "error\|warning\|fatal\|reject" | tail -10 | while read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Sent/received stats (last hour approximation)
sent_count=0
received_count=0
bounced_count=0
if [ -n "$mail_log" ] && [ -f "$mail_log" ]; then
    sent_count=$(tail -1000 "$mail_log" 2>/dev/null | grep -c "status=sent" || echo 0)
    bounced_count=$(tail -1000 "$mail_log" 2>/dev/null | grep -c "status=bounced\|status=deferred" || echo 0)
fi

# Check SMTP ports
smtp_25=$(ss -tlnp 2>/dev/null | grep ":25 " | head -1 || echo "")
smtp_587=$(ss -tlnp 2>/dev/null | grep ":587 " | head -1 || echo "")
smtp_465=$(ss -tlnp 2>/dev/null | grep ":465 " | head -1 || echo "")

# TLS configuration
tls_enabled="false"
if postconf smtpd_tls_cert_file 2>/dev/null | grep -qv "^$"; then
    tls_enabled="true"
fi

# SASL/Authentication
sasl_enabled="false"
if postconf smtpd_sasl_auth_enable 2>/dev/null | grep -qi "yes"; then
    sasl_enabled="true"
fi

# Check SPF/DKIM/DMARC setup
spf_configured="false"
dkim_configured="false"
if [ -f /etc/postfix/main.cf ]; then
    grep -qi "spf" /etc/postfix/main.cf 2>/dev/null && spf_configured="true"
fi
if systemctl is-active opendkim >/dev/null 2>&1 || [ -f /etc/opendkim.conf ]; then
    dkim_configured="true"
fi

# Blacklist check warning (basic local check)
blacklist_warning="false"
# This would need external DNS lookups which might timeout

cat << EOF
{
  "script": "60_postfix_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "postfix": {
    "installed": $postfix_installed,
    "running": $postfix_running,
    "version": "$postfix_version"
  },
  "config": {
    "hostname": "$hostname",
    "mydomain": "$mydomain",
    "inet_interfaces": "$inet_interfaces",
    "relay_host": "$relay_host"
  },
  "security": {
    "tls_enabled": $tls_enabled,
    "sasl_enabled": $sasl_enabled,
    "spf_configured": $spf_configured,
    "dkim_configured": $dkim_configured
  },
  "ports": {
    "smtp_25": "${smtp_25:-not listening}",
    "submission_587": "${smtp_587:-not listening}",
    "smtps_465": "${smtp_465:-not listening}"
  },
  "queue": {
    "total": $queue_size,
    "active": $queue_active,
    "deferred": $queue_deferred,
    "hold": $queue_hold
  },
  "stats": {
    "sent_recent": $sent_count,
    "bounced_recent": $bounced_count,
    "errors_in_log": $error_count
  },
  "recent_errors": [${recent_errors:-}]
}
EOF
'
