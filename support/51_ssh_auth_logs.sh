#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - SSH Authentication Logs
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Find auth log file
auth_log=""
if [ -f /var/log/auth.log ]; then
    auth_log="/var/log/auth.log"
elif [ -f /var/log/secure ]; then
    auth_log="/var/log/secure"
fi

log_found="false"
[ -n "$auth_log" ] && [ -f "$auth_log" ] && log_found="true"

# Use journald if log file not accessible
use_journald="false"
if [ "$log_found" = "false" ] && command -v journalctl &>/dev/null; then
    use_journald="true"
fi

# Successful logins
successful_logins=0
successful_list=""

if [ "$log_found" = "true" ]; then
    successful_logins=$(grep -c "Accepted " "$auth_log" 2>/dev/null || echo 0)
    successful_list=$(grep "Accepted " "$auth_log" 2>/dev/null | tail -10 | while read -r line; do
        # Extract user, IP, method
        user=$(echo "$line" | grep -oP "for \K[^ ]+" || echo "unknown")
        ip=$(echo "$line" | grep -oP "from \K[0-9.]+" || echo "unknown")
        method=$(echo "$line" | grep -oP "Accepted \K[^ ]+" || echo "unknown")
        timestamp=$(echo "$line" | awk "{print \$1, \$2, \$3}")
        
        echo "{\"timestamp\":\"$timestamp\",\"user\":\"$user\",\"ip\":\"$ip\",\"method\":\"$method\"}"
    done | paste -sd "," - | tr -d "\n")
elif [ "$use_journald" = "true" ]; then
    successful_logins=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -c "Accepted " || echo 0)
    successful_list=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep "Accepted " | tail -10 | while read -r line; do
        user=$(echo "$line" | grep -oP "for \K[^ ]+" || echo "unknown")
        ip=$(echo "$line" | grep -oP "from \K[0-9.]+" || echo "unknown")
        method=$(echo "$line" | grep -oP "Accepted \K[^ ]+" || echo "unknown")
        timestamp=$(echo "$line" | awk "{print \$1, \$2, \$3}")
        echo "{\"timestamp\":\"$timestamp\",\"user\":\"$user\",\"ip\":\"$ip\",\"method\":\"$method\"}"
    done | paste -sd "," - | tr -d "\n")
fi

# Failed logins
failed_logins=0
failed_list=""

if [ "$log_found" = "true" ]; then
    failed_logins=$(grep -cE "Failed password|Invalid user|authentication failure" "$auth_log" 2>/dev/null || echo 0)
    failed_list=$(grep -E "Failed password|Invalid user" "$auth_log" 2>/dev/null | tail -10 | while read -r line; do
        user=$(echo "$line" | grep -oP "(for |user )\K[^ ]+" || echo "unknown")
        ip=$(echo "$line" | grep -oP "from \K[0-9.]+" || echo "unknown")
        timestamp=$(echo "$line" | awk "{print \$1, \$2, \$3}")
        reason=$(echo "$line" | grep -oP "(Failed password|Invalid user)" || echo "failed")
        echo "{\"timestamp\":\"$timestamp\",\"user\":\"$user\",\"ip\":\"$ip\",\"reason\":\"$reason\"}"
    done | paste -sd "," - | tr -d "\n")
elif [ "$use_journald" = "true" ]; then
    failed_logins=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -cE "Failed password|Invalid user" || echo 0)
    failed_list=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -E "Failed password|Invalid user" | tail -10 | while read -r line; do
        user=$(echo "$line" | grep -oP "(for |user )\K[^ ]+" || echo "unknown")
        ip=$(echo "$line" | grep -oP "from \K[0-9.]+" || echo "unknown")
        timestamp=$(echo "$line" | awk "{print \$1, \$2, \$3}")
        reason=$(echo "$line" | grep -oP "(Failed password|Invalid user)" || echo "failed")
        echo "{\"timestamp\":\"$timestamp\",\"user\":\"$user\",\"ip\":\"$ip\",\"reason\":\"$reason\"}"
    done | paste -sd "," - | tr -d "\n")
fi

# Top attacking IPs
top_attackers=""
if [ "$log_found" = "true" ]; then
    top_attackers=$(grep -E "Failed password|Invalid user" "$auth_log" 2>/dev/null | grep -oP "from \K[0-9.]+" | sort | uniq -c | sort -rn | head -10 | awk "{printf \"{\\\"ip\\\":\\\"%s\\\",\\\"attempts\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
elif [ "$use_journald" = "true" ]; then
    top_attackers=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -E "Failed password|Invalid user" | grep -oP "from \K[0-9.]+" | sort | uniq -c | sort -rn | head -10 | awk "{printf \"{\\\"ip\\\":\\\"%s\\\",\\\"attempts\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Targeted usernames
targeted_users=""
if [ "$log_found" = "true" ]; then
    targeted_users=$(grep -E "Failed password|Invalid user" "$auth_log" 2>/dev/null | grep -oP "(for |user )\K[^ ]+" | sort | uniq -c | sort -rn | head -10 | awk "{printf \"{\\\"user\\\":\\\"%s\\\",\\\"attempts\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Root login attempts
root_attempts=0
if [ "$log_found" = "true" ]; then
    root_attempts=$(grep -c "for root" "$auth_log" 2>/dev/null || echo 0)
fi

# SSH config security
permit_root="unknown"
password_auth="unknown"
if [ -f /etc/ssh/sshd_config ]; then
    permit_root=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk "{print \$2}" || echo "default")
    password_auth=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk "{print \$2}" || echo "default")
fi

# Current SSH sessions
active_sessions=""
active_sessions=$(who 2>/dev/null | grep -v "^$" | while read -r line; do
    user=$(echo "$line" | awk "{print \$1}")
    terminal=$(echo "$line" | awk "{print \$2}")
    from=$(echo "$line" | grep -oP "\([0-9.]+\)" | tr -d "()" || echo "local")
    login_time=$(echo "$line" | awk "{print \$3, \$4}")
    echo "{\"user\":\"$user\",\"terminal\":\"$terminal\",\"from\":\"$from\",\"login_time\":\"$login_time\"}"
done | paste -sd "," - | tr -d "\n")

cat << EOF
{
  "script": "51_ssh_auth_logs",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "log_source": "${auth_log:-journald}",
  "authentication": {
    "successful_24h": $successful_logins,
    "failed_24h": $failed_logins,
    "root_attempts": $root_attempts
  },
  "successful_logins": [${successful_list:-}],
  "failed_logins": [${failed_list:-}],
  "top_attackers": [${top_attackers:-}],
  "targeted_users": [${targeted_users:-}],
  "ssh_config": {
    "permit_root_login": "$permit_root",
    "password_authentication": "$password_auth"
  },
  "active_sessions": [${active_sessions:-}]
}
EOF
'
