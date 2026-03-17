#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - WordPress Health Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

# Find WordPress installations
wp_found="false"
wp_path=""
wp_paths=""

# Common WordPress locations
for dir in /var/www/html /var/www /home/*/public_html /srv/www/*; do
    [ ! -d "$dir" ] && continue
    if [ -f "$dir/wp-config.php" ]; then
        wp_found="true"
        wp_path="$dir"
        [ -n "$wp_paths" ] && wp_paths="$wp_paths,"
        wp_paths="${wp_paths}\"$dir\""
    fi
    # Check subdirectories
    for subdir in "$dir"/*/; do
        [ ! -d "$subdir" ] && continue
        if [ -f "$subdir/wp-config.php" ]; then
            wp_found="true"
            [ -z "$wp_path" ] && wp_path="$subdir"
            [ -n "$wp_paths" ] && wp_paths="$wp_paths,"
            wp_paths="${wp_paths}\"${subdir%/}\""
        fi
    done
done

if [ "$wp_found" = "false" ]; then
    cat << 'ENDJSON'
{
  "script": "40_wordpress_health",
  "timestamp": "TIMESTAMP_PLACEHOLDER",
  "status": "ok",
  "wordpress_found": false,
  "message": "No WordPress installation found"
}
ENDJSON
    exit 0
fi

# Use first found WordPress path for detailed analysis
wp_path="${wp_path%/}"

# Get WordPress version
wp_version="unknown"
if [ -f "$wp_path/wp-includes/version.php" ]; then
    wp_version=$(grep "wp_version = " "$wp_path/wp-includes/version.php" 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.?[0-9]*" | head -1)
fi
wp_version="${wp_version:-unknown}"

# Database info from wp-config
db_name=""
db_host=""
table_prefix=""
config_readable="false"
if [ -r "$wp_path/wp-config.php" ]; then
    config_readable="true"
    db_name=$(grep "DB_NAME" "$wp_path/wp-config.php" 2>/dev/null | grep -oP "DB_NAME[^,]+,[^'\"]*['\"]\\K[^'\"]+")
    db_host=$(grep "DB_HOST" "$wp_path/wp-config.php" 2>/dev/null | grep -oP "DB_HOST[^,]+,[^'\"]*['\"]\\K[^'\"]+")
    table_prefix=$(grep "table_prefix" "$wp_path/wp-config.php" 2>/dev/null | grep -oP "table_prefix[^=]*=[^'\"]*['\"]\\K[^'\"]+")
fi

# Plugin count
plugins_count=0
if [ -d "$wp_path/wp-content/plugins" ]; then
    plugins_count=$(find "$wp_path/wp-content/plugins" -maxdepth 1 -type d 2>/dev/null | wc -l)
    plugins_count=$((plugins_count - 1))
fi

# Theme count
themes_count=0
if [ -d "$wp_path/wp-content/themes" ]; then
    themes_count=$(find "$wp_path/wp-content/themes" -maxdepth 1 -type d 2>/dev/null | wc -l)
    themes_count=$((themes_count - 1))
fi

# WP_DEBUG status
wp_debug="false"
if grep -q "WP_DEBUG.*true" "$wp_path/wp-config.php" 2>/dev/null; then
    wp_debug="true"
fi

# Uploads directory size
uploads_size="unknown"
if [ -d "$wp_path/wp-content/uploads" ]; then
    uploads_size=$(du -sh "$wp_path/wp-content/uploads" 2>/dev/null | awk '{print $1}')
fi
uploads_size="${uploads_size:-unknown}"

# Cache plugin detection
cache_plugin="none"
for plugin in wp-rocket w3-total-cache wp-super-cache litespeed-cache redis-cache wp-fastest-cache; do
    if [ -d "$wp_path/wp-content/plugins/$plugin" ]; then
        cache_plugin="$plugin"
        break
    fi
done

# Object cache detection
object_cache="false"
[ -f "$wp_path/wp-content/object-cache.php" ] && object_cache="true"

# Security plugins detection
security_plugins=""
for plugin in wordfence sucuri-scanner ithemes-security-pro all-in-one-wp-security-and-firewall; do
    if [ -d "$wp_path/wp-content/plugins/$plugin" ]; then
        [ -n "$security_plugins" ] && security_plugins="$security_plugins,"
        security_plugins="${security_plugins}\"$plugin\""
    fi
done

# htaccess
htaccess_exists="false"
[ -f "$wp_path/.htaccess" ] && htaccess_exists="true"

# wp-config permissions
config_perms=$(stat -c "%a" "$wp_path/wp-config.php" 2>/dev/null || echo "unknown")

# Issues
issues=""
[ -f "$wp_path/.maintenance" ] && issues="${issues}\"WordPress in maintenance mode\","

# Debug log errors
error_count=0
wp_errors=""
if [ -f "$wp_path/wp-content/debug.log" ]; then
    error_count=$(tail -100 "$wp_path/wp-content/debug.log" 2>/dev/null | grep -ci "error\|fatal" || echo "0")
    error_count=$((error_count + 0))
fi

# Remove trailing comma from issues
issues="${issues%,}"

# Total size
wp_total_size=$(du -sh "$wp_path" 2>/dev/null | awk '{print $1}' || echo "unknown")

# Output JSON
cat << ENDJSON
{
  "script": "40_wordpress_health",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": true,
  "installations": [${wp_paths}],
  "primary_installation": {
    "path": "${wp_path}",
    "version": "${wp_version}",
    "total_size": "${wp_total_size}"
  },
  "database": {
    "name": "${db_name}",
    "host": "${db_host}",
    "table_prefix": "${table_prefix}"
  },
  "configuration": {
    "config_readable": ${config_readable},
    "config_permissions": "${config_perms}",
    "wp_debug": ${wp_debug},
    "htaccess_exists": ${htaccess_exists}
  },
  "content": {
    "plugins_count": ${plugins_count},
    "themes_count": ${themes_count},
    "uploads_size": "${uploads_size}"
  },
  "performance": {
    "cache_plugin": "${cache_plugin}",
    "object_cache": ${object_cache}
  },
  "security": {
    "plugins": [${security_plugins}]
  },
  "issues": [${issues}],
  "errors": {
    "recent_count": ${error_count}
  }
}
ENDJSON
