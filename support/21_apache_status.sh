#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Apache Status Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check if Apache is installed
apache_installed="false"
apache_path=$(which apache2 2>/dev/null || which httpd 2>/dev/null || echo "")
if [ -n "$apache_path" ]; then
    apache_installed="true"
fi

# Get Apache status
apache_running="false"
apache_pid=""
apache_status=""
if systemctl is-active apache2 >/dev/null 2>&1; then
    apache_running="true"
    apache_pid=$(systemctl show apache2 --property=MainPID --value 2>/dev/null || echo "")
    apache_status="running"
elif systemctl is-active httpd >/dev/null 2>&1; then
    apache_running="true"
    apache_pid=$(systemctl show httpd --property=MainPID --value 2>/dev/null || echo "")
    apache_status="running"
else
    apache_status=$(systemctl is-active apache2 2>/dev/null || systemctl is-active httpd 2>/dev/null || echo "not installed")
fi

# Apache version
apache_version=""
if [ "$apache_installed" = "true" ]; then
    apache_version=$(apache2 -v 2>&1 | head -1 | grep -oP "Apache/[0-9.]+" || httpd -v 2>&1 | head -1 | grep -oP "Apache/[0-9.]+" || echo "unknown")
fi

# Config test
config_valid="false"
config_error=""
if [ "$apache_installed" = "true" ]; then
    config_test=$(apache2ctl configtest 2>&1 || apachectl configtest 2>&1 || echo "error")
    if echo "$config_test" | grep -qi "syntax ok"; then
        config_valid="true"
    else
        config_error=$(echo "$config_test" | head -3 | tr "\n" " " | sed "s/\"/\\\\\"/g")
    fi
fi

# Worker info from server-status (if mod_status enabled)
active_connections=""
requests_per_sec=""
if [ "$apache_running" = "true" ]; then
    status_data=$(curl -s http://127.0.0.1/server-status?auto 2>/dev/null || curl -s http://localhost/server-status?auto 2>/dev/null || echo "")
    if [ -n "$status_data" ]; then
        active_connections=$(echo "$status_data" | grep "BusyWorkers" | awk "{print \$2}" || echo "")
        requests_per_sec=$(echo "$status_data" | grep "ReqPerSec" | awk "{print \$2}" || echo "")
    fi
fi

# MPM info
mpm=""
if [ "$apache_installed" = "true" ]; then
    mpm=$(apache2ctl -M 2>/dev/null | grep mpm || apachectl -M 2>/dev/null | grep mpm || echo "")
    mpm=$(echo "$mpm" | grep -oE "mpm_[a-z]+" | head -1 || echo "unknown")
fi

# Enabled modules count
modules_count=0
if [ "$apache_installed" = "true" ]; then
    modules_count=$(apache2ctl -M 2>/dev/null | wc -l || apachectl -M 2>/dev/null | wc -l || echo 0)
fi

# Enabled sites count
sites_enabled=0
if [ -d /etc/apache2/sites-enabled ]; then
    sites_enabled=$(ls -1 /etc/apache2/sites-enabled 2>/dev/null | wc -l)
elif [ -d /etc/httpd/conf.d ]; then
    sites_enabled=$(ls -1 /etc/httpd/conf.d/*.conf 2>/dev/null | wc -l)
fi

# Recent error log entries
error_log_path="/var/log/apache2/error.log"
[ ! -f "$error_log_path" ] && error_log_path="/var/log/httpd/error_log"
error_count=0
error_log_entries=""
if [ -f "$error_log_path" ]; then
    error_count=$(tail -100 "$error_log_path" 2>/dev/null | grep -ci "error\|crit\|alert\|emerg" || echo 0)
    error_log_entries=$(tail -20 "$error_log_path" 2>/dev/null | grep -i "error\|crit\|alert\|emerg" | tail -5 | while read -r line; do
        echo "\"$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-200)\""
    done | paste -sd "," -)
fi

# Port listeners
listening_80=$(ss -tlnp 2>/dev/null | grep ":80 " | grep -i "apache\|httpd" | head -1 || echo "")
listening_443=$(ss -tlnp 2>/dev/null | grep ":443 " | grep -i "apache\|httpd" | head -1 || echo "")

cat << EOF
{
  "script": "21_apache_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "apache": {
    "installed": $apache_installed,
    "running": $apache_running,
    "status": "$apache_status",
    "version": "$apache_version",
    "pid": ${apache_pid:-null},
    "mpm": "$mpm",
    "modules_count": $modules_count
  },
  "config": {
    "valid": $config_valid,
    "error": "${config_error:-null}"
  },
  "connections": {
    "active_workers": ${active_connections:-null},
    "requests_per_sec": ${requests_per_sec:-null}
  },
  "sites_enabled": $sites_enabled,
  "ports": {
    "port_80": "${listening_80:-none}",
    "port_443": "${listening_443:-none}"
  },
  "errors": {
    "recent_count": $error_count,
    "recent_entries": [${error_log_entries:-}]
  }
}
EOF
'
