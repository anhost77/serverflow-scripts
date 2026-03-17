#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Laravel Health Check
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Find Laravel installations
laravel_found="false"
search_paths=("/var/www" "/srv/www" "/home")

# Find artisan files (Laravel indicator)
artisan_files=$(find "${search_paths[@]}" -maxdepth 4 -name "artisan" -type f 2>/dev/null | head -5)

[ -n "$artisan_files" ] && laravel_found="true"

sites_data=""

for artisan in $artisan_files; do
    laravel_dir=$(dirname "$artisan")
    
    # Verify it'\''s Laravel
    if ! grep -q "Laravel" "$artisan" 2>/dev/null; then
        continue
    fi
    
    # Get Laravel version from composer.lock
    laravel_version=""
    if [ -f "$laravel_dir/composer.lock" ]; then
        laravel_version=$(grep -A 5 "\"name\": \"laravel/framework\"" "$laravel_dir/composer.lock" 2>/dev/null | grep "\"version\"" | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "unknown")
    fi
    
    # Check .env file
    env_exists="false"
    app_env=""
    app_debug=""
    if [ -f "$laravel_dir/.env" ]; then
        env_exists="true"
        app_env=$(grep "^APP_ENV=" "$laravel_dir/.env" 2>/dev/null | cut -d= -f2 | tr -d "\r" || echo "")
        app_debug=$(grep "^APP_DEBUG=" "$laravel_dir/.env" 2>/dev/null | cut -d= -f2 | tr -d "\r" || echo "")
    fi
    
    # Check storage directory permissions
    storage_writable="false"
    if [ -d "$laravel_dir/storage" ] && [ -w "$laravel_dir/storage" ]; then
        storage_writable="true"
    fi
    
    # Check bootstrap/cache permissions
    cache_writable="false"
    if [ -d "$laravel_dir/bootstrap/cache" ] && [ -w "$laravel_dir/bootstrap/cache" ]; then
        cache_writable="true"
    fi
    
    # Recent errors in laravel.log
    log_errors=0
    recent_errors=""
    log_file="$laravel_dir/storage/logs/laravel.log"
    if [ -f "$log_file" ]; then
        log_errors=$(tail -500 "$log_file" 2>/dev/null | grep -c "\[.*\] .*ERROR\|exception\|Exception" || echo 0)
        recent_errors=$(tail -100 "$log_file" 2>/dev/null | grep -i "error\|exception" | tail -5 | while read -r line; do
            echo "\"$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-150)\""
        done | paste -sd "," - | tr -d "\n")
    fi
    
    # Log file size
    log_size=""
    if [ -f "$log_file" ]; then
        log_size=$(du -sh "$log_file" 2>/dev/null | awk "{print \$1}" || echo "?")
    fi
    
    # Check cache driver
    cache_driver=""
    if [ -f "$laravel_dir/.env" ]; then
        cache_driver=$(grep "^CACHE_DRIVER=" "$laravel_dir/.env" 2>/dev/null | cut -d= -f2 | tr -d "\r" || echo "file")
    fi
    
    # Check queue driver
    queue_driver=""
    if [ -f "$laravel_dir/.env" ]; then
        queue_driver=$(grep "^QUEUE_CONNECTION=" "$laravel_dir/.env" 2>/dev/null | cut -d= -f2 | tr -d "\r" || echo "sync")
    fi
    
    # Check session driver
    session_driver=""
    if [ -f "$laravel_dir/.env" ]; then
        session_driver=$(grep "^SESSION_DRIVER=" "$laravel_dir/.env" 2>/dev/null | cut -d= -f2 | tr -d "\r" || echo "file")
    fi
    
    # Check if queue workers are running
    queue_workers=0
    queue_workers=$(pgrep -f "artisan queue:work" 2>/dev/null | wc -l || echo 0)
    
    # Check scheduler (cron)
    scheduler_configured="false"
    if grep -r "artisan schedule:run" /etc/cron.* /var/spool/cron 2>/dev/null | grep -q "$laravel_dir"; then
        scheduler_configured="true"
    fi
    
    # Check horizon (if redis queue)
    horizon_running="false"
    if [ "$queue_driver" = "redis" ]; then
        if pgrep -f "artisan horizon" &>/dev/null; then
            horizon_running="true"
        fi
    fi
    
    # Config cached
    config_cached="false"
    if [ -f "$laravel_dir/bootstrap/cache/config.php" ]; then
        config_cached="true"
    fi
    
    # Routes cached
    routes_cached="false"
    if [ -f "$laravel_dir/bootstrap/cache/routes-v7.php" ] || [ -f "$laravel_dir/bootstrap/cache/routes.php" ]; then
        routes_cached="true"
    fi
    
    sites_data="$sites_data{\"path\":\"$laravel_dir\",\"version\":\"$laravel_version\",\"env\":{\"exists\":$env_exists,\"app_env\":\"$app_env\",\"app_debug\":\"$app_debug\"},\"permissions\":{\"storage_writable\":$storage_writable,\"cache_writable\":$cache_writable},\"drivers\":{\"cache\":\"$cache_driver\",\"queue\":\"$queue_driver\",\"session\":\"$session_driver\"},\"cache_status\":{\"config_cached\":$config_cached,\"routes_cached\":$routes_cached},\"workers\":{\"queue_workers\":$queue_workers,\"horizon_running\":$horizon_running,\"scheduler_configured\":$scheduler_configured},\"logs\":{\"errors_recent\":$log_errors,\"log_size\":\"$log_size\",\"recent_errors\":[${recent_errors:-}]}},"
done

# Remove trailing comma
sites_data=$(echo "$sites_data" | sed "s/,$//" | tr -d "\n")

cat << EOF
{
  "script": "43_laravel_health",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "laravel_found": $laravel_found,
  "sites": [${sites_data:-}]
}
EOF
'
