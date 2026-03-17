#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Fail2ban Status
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check fail2ban installation
f2b_installed="false"
f2b_running="false"
f2b_version=""

if command -v fail2ban-client &>/dev/null; then
    f2b_installed="true"
    f2b_version=$(fail2ban-client --version 2>/dev/null | head -1 | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
fi

if systemctl is-active fail2ban >/dev/null 2>&1; then
    f2b_running="true"
fi

# Get fail2ban status
jails=""
total_banned=0
total_currently_banned=0

if [ "$f2b_running" = "true" ]; then
    # Get jail list
    jail_list=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | sed "s/.*Jail list://" | tr -d "\t" | tr "," " " | xargs)
    
    if [ -n "$jail_list" ]; then
        jails=$(for jail in $jail_list; do
            # Get jail status
            jail_status=$(fail2ban-client status "$jail" 2>/dev/null || echo "")
            
            if [ -n "$jail_status" ]; then
                currently_banned=$(echo "$jail_status" | grep "Currently banned:" | awk "{print \$NF}" || echo 0)
                total_banned_jail=$(echo "$jail_status" | grep "Total banned:" | awk "{print \$NF}" || echo 0)
                currently_failed=$(echo "$jail_status" | grep "Currently failed:" | awk "{print \$NF}" || echo 0)
                
                # Get banned IPs (up to 10)
                banned_ips=$(echo "$jail_status" | grep "Banned IP list:" | sed "s/.*Banned IP list://" | tr " " "\n" | head -10 | while read -r ip; do
                    [ -n "$ip" ] && echo "\"$ip\""
                done | paste -sd "," - | tr -d "\n")
                
                total_banned=$((total_banned + total_banned_jail))
                total_currently_banned=$((total_currently_banned + currently_banned))
                
                echo "{\"jail\":\"$jail\",\"currently_banned\":$currently_banned,\"total_banned\":$total_banned_jail,\"currently_failed\":$currently_failed,\"banned_ips\":[${banned_ips:-}]}"
            fi
        done | paste -sd "," - | tr -d "\n")
    fi
fi

# Recent bans from log
recent_bans=""
if [ -f /var/log/fail2ban.log ]; then
    recent_bans=$(grep "Ban " /var/log/fail2ban.log 2>/dev/null | tail -10 | while read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Recent unbans
recent_unbans=""
if [ -f /var/log/fail2ban.log ]; then
    recent_unbans=$(grep "Unban " /var/log/fail2ban.log 2>/dev/null | tail -5 | while read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Fail2ban errors
f2b_errors=0
if [ -f /var/log/fail2ban.log ]; then
    f2b_errors=$(grep -c "ERROR\|WARNING" /var/log/fail2ban.log 2>/dev/null | tail -1 || echo 0)
fi

# Check main config
config_exists="false"
if [ -f /etc/fail2ban/jail.local ] || [ -f /etc/fail2ban/jail.conf ]; then
    config_exists="true"
fi

# Ban count last 24h (approximate)
bans_24h=0
if [ -f /var/log/fail2ban.log ]; then
    yesterday=$(date -d "24 hours ago" "+%Y-%m-%d")
    today=$(date "+%Y-%m-%d")
    bans_24h=$(grep -E "^($yesterday|$today).*Ban " /var/log/fail2ban.log 2>/dev/null | wc -l || echo 0)
fi

cat << EOF
{
  "script": "50_fail2ban_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "fail2ban": {
    "installed": $f2b_installed,
    "running": $f2b_running,
    "version": "$f2b_version",
    "config_exists": $config_exists
  },
  "summary": {
    "total_currently_banned": $total_currently_banned,
    "total_banned_all_time": $total_banned,
    "bans_last_24h": $bans_24h,
    "errors_in_log": $f2b_errors
  },
  "jails": [${jails:-}],
  "recent_bans": [${recent_bans:-}],
  "recent_unbans": [${recent_unbans:-}]
}
EOF
'
