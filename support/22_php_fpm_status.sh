#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - PHP-FPM Status Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Detect PHP version(s)
php_versions=""
for v in 7.4 8.0 8.1 8.2 8.3; do
    if [ -f "/etc/php/$v/fpm/php-fpm.conf" ] || [ -f "/etc/php/$v/fpm/pool.d/www.conf" ]; then
        if [ -n "$php_versions" ]; then
            php_versions="$php_versions,"
        fi
        php_versions="$php_versions\"$v\""
    fi
done

# Main PHP version
php_version=$(php -v 2>/dev/null | head -1 | awk "{print \$2}" || echo "not installed")

# Check PHP-FPM service status
fpm_services=""
fpm_running="false"
for service in php8.3-fpm php8.2-fpm php8.1-fpm php8.0-fpm php7.4-fpm php-fpm; do
    status=$(systemctl is-active $service 2>/dev/null || echo "not found")
    if [ "$status" != "not found" ]; then
        if [ -n "$fpm_services" ]; then
            fpm_services="$fpm_services,"
        fi
        fpm_services="$fpm_services{\"service\":\"$service\",\"status\":\"$status\"}"
        if [ "$status" = "active" ]; then
            fpm_running="true"
        fi
    fi
done

# PHP-FPM pool configuration
pool_config=""
pool_files=$(find /etc/php -name "www.conf" 2>/dev/null | head -1)
if [ -n "$pool_files" ]; then
    pm=$(grep "^pm = " "$pool_files" 2>/dev/null | awk -F= "{print \$2}" | xargs || echo "dynamic")
    max_children=$(grep "^pm.max_children" "$pool_files" 2>/dev/null | awk -F= "{print \$2}" | xargs || echo "5")
    start_servers=$(grep "^pm.start_servers" "$pool_files" 2>/dev/null | awk -F= "{print \$2}" | xargs || echo "2")
    min_spare=$(grep "^pm.min_spare_servers" "$pool_files" 2>/dev/null | awk -F= "{print \$2}" | xargs || echo "1")
    max_spare=$(grep "^pm.max_spare_servers" "$pool_files" 2>/dev/null | awk -F= "{print \$2}" | xargs || echo "3")
    max_requests=$(grep "^pm.max_requests" "$pool_files" 2>/dev/null | awk -F= "{print \$2}" | xargs || echo "0")
    pool_config="{\"pm\":\"$pm\",\"max_children\":$max_children,\"start_servers\":$start_servers,\"min_spare\":$min_spare,\"max_spare\":$max_spare,\"max_requests\":$max_requests}"
fi

# Active PHP-FPM processes
fpm_procs=0
fpm_procs_idle=0
fpm_procs_active=0
if [ "$fpm_running" = "true" ]; then
    fpm_procs=$(pgrep -c "php-fpm" 2>/dev/null || echo 0)
fi

# PHP Error log analysis
php_errors=""
error_count=0
error_log=$(php -i 2>/dev/null | grep "^error_log" | awk "{print \$3}" | head -1)
if [ -z "$error_log" ]; then
    error_log="/var/log/php-fpm.log"
fi
if [ -f "$error_log" ]; then
    error_count=$(tail -100 "$error_log" 2>/dev/null | grep -ci "error\|fatal\|warning" || echo 0)
    php_errors=$(tail -20 "$error_log" 2>/dev/null | grep -i "error\|fatal" | tail -5 | while read line; do echo "\"$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-200)\""; done | paste -sd "," -)
fi

# Check for common PHP error logs
fpm_error_log="/var/log/php*-fpm.log"
for log in /var/log/php8.3-fpm.log /var/log/php8.2-fpm.log /var/log/php8.1-fpm.log /var/log/php-fpm.log; do
    if [ -f "$log" ]; then
        fpm_log_errors=$(tail -50 "$log" 2>/dev/null | grep -ci "error\|warning" || echo 0)
        error_count=$((error_count + fpm_log_errors))
    fi
done

# Memory limit
memory_limit=$(php -i 2>/dev/null | grep "^memory_limit" | awk "{print \$3}" || echo "unknown")

# Max execution time
max_execution=$(php -i 2>/dev/null | grep "^max_execution_time" | awk "{print \$3}" || echo "unknown")

# Loaded modules count
modules_count=$(php -m 2>/dev/null | wc -l || echo 0)

# Check OPcache status
opcache_enabled="false"
if php -m 2>/dev/null | grep -qi "opcache"; then
    opcache_enabled="true"
fi

# Output JSON
cat << EOF
{
  "script": "22_php_fpm_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "php": {
    "version": "$php_version",
    "installed_versions": [${php_versions:-}],
    "memory_limit": "$memory_limit",
    "max_execution_time": "$max_execution",
    "modules_count": $modules_count,
    "opcache_enabled": $opcache_enabled
  },
  "fpm": {
    "running": $fpm_running,
    "services": [${fpm_services:-}],
    "process_count": $fpm_procs,
    "pool_config": ${pool_config:-null}
  },
  "errors": {
    "recent_count": $error_count,
    "log_path": "$error_log",
    "recent_entries": [${php_errors:-}]
  }
}
EOF
'
