#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Nginx Status Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check if nginx is installed
nginx_installed="false"
nginx_path=$(which nginx 2>/dev/null || echo "")
if [ -n "$nginx_path" ]; then
    nginx_installed="true"
fi

# Get nginx status
nginx_running="false"
nginx_pid=""
nginx_status=""
if systemctl is-active nginx >/dev/null 2>&1; then
    nginx_running="true"
    nginx_pid=$(systemctl show nginx --property=MainPID --value 2>/dev/null || echo "")
    nginx_status="running"
elif systemctl is-active openresty >/dev/null 2>&1; then
    nginx_running="true"
    nginx_pid=$(systemctl show openresty --property=MainPID --value 2>/dev/null || echo "")
    nginx_status="running (openresty)"
else
    nginx_status=$(systemctl is-active nginx 2>/dev/null || echo "not installed")
fi

# Nginx version
nginx_version=""
if [ "$nginx_installed" = "true" ]; then
    nginx_version=$(nginx -v 2>&1 | cut -d/ -f2 || echo "unknown")
fi

# Config test
config_valid="false"
config_error=""
if [ "$nginx_installed" = "true" ]; then
    config_test=$(nginx -t 2>&1)
    if echo "$config_test" | grep -q "syntax is ok"; then
        config_valid="true"
    else
        config_error=$(echo "$config_test" | head -3 | tr "\n" " " | sed "s/\"/\\\\\"/g")
    fi
fi

# Worker processes
worker_count=0
if [ "$nginx_running" = "true" ]; then
    worker_count=$(pgrep -c "nginx: worker" 2>/dev/null || echo 0)
fi

# Active connections (from stub_status if available)
active_connections=""
accepts=""
handled=""
requests=""
if [ "$nginx_running" = "true" ]; then
    # Try to get from stub_status
    stub_data=$(curl -s http://127.0.0.1/nginx_status 2>/dev/null || curl -s http://127.0.0.1:80/stub_status 2>/dev/null || echo "")
    if [ -n "$stub_data" ]; then
        active_connections=$(echo "$stub_data" | grep "Active" | awk "{print \$3}" || echo "")
        accepts=$(echo "$stub_data" | awk "NR==3 {print \$1}" || echo "")
        handled=$(echo "$stub_data" | awk "NR==3 {print \$2}" || echo "")
        requests=$(echo "$stub_data" | awk "NR==3 {print \$3}" || echo "")
    fi
fi

# Enabled sites count
sites_enabled=0
if [ -d /etc/nginx/sites-enabled ]; then
    sites_enabled=$(ls -1 /etc/nginx/sites-enabled 2>/dev/null | wc -l)
fi

# Recent error log entries
error_log_entries=""
error_count=0
if [ -f /var/log/nginx/error.log ]; then
    error_count=$(tail -100 /var/log/nginx/error.log 2>/dev/null | grep -c "error\|crit\|alert\|emerg" || echo 0)
    error_log_entries=$(tail -10 /var/log/nginx/error.log 2>/dev/null | grep "error\|crit\|alert\|emerg" | tail -5 | while read line; do echo "\"$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-200)\""; done | paste -sd "," -)
fi

# Port 80/443 listeners
listening_80=$(ss -tlnp 2>/dev/null | grep ":80 " | head -1 | awk "{print \$NF}" || echo "none")
listening_443=$(ss -tlnp 2>/dev/null | grep ":443 " | head -1 | awk "{print \$NF}" || echo "none")

# Output JSON
cat << EOF
{
  "script": "20_nginx_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "nginx": {
    "installed": $nginx_installed,
    "running": $nginx_running,
    "status": "$nginx_status",
    "version": "$nginx_version",
    "pid": "${nginx_pid:-null}",
    "worker_processes": $worker_count
  },
  "config": {
    "valid": $config_valid,
    "error": "${config_error:-null}"
  },
  "connections": {
    "active": ${active_connections:-null},
    "accepts": ${accepts:-null},
    "handled": ${handled:-null},
    "requests": ${requests:-null}
  },
  "sites_enabled": $sites_enabled,
  "ports": {
    "port_80": "$listening_80",
    "port_443": "$listening_443"
  },
  "errors": {
    "recent_count": $error_count,
    "recent_entries": [${error_log_entries:-}]
  }
}
EOF
'
