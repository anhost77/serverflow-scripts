#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - WordPress Health Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Find WordPress installations
wp_found="false"
wp_path=""
wp_paths=""

# Common WordPress locations
for dir in /var/www/html /var/www /home/*/public_html /srv/www/*; do
    if [ -f "$dir/wp-config.php" ]; then
        wp_found="true"
        wp_path="$dir"
        if [ -n "$wp_paths" ]; then
            wp_paths="$wp_paths,"
        fi
        wp_paths="$wp_paths\"$dir\""
    fi
    # Check subdirectories
    for subdir in $dir/*/; do
        if [ -f "$subdir/wp-config.php" ]; then
            wp_found="true"
            if [ -z "$wp_path" ]; then
                wp_path="$subdir"
            fi
            if [ -n "$wp_paths" ]; then
                wp_paths="$wp_paths,"
            fi
            wp_paths="$wp_paths\"${subdir%/}\""
        fi
    done
done

if [ "$wp_found" = "false" ]; then
    cat << EOF
{
  "script": "40_wordpress_health",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": false,
  "message": "No WordPress installation found"
}
EOF
    exit 0
fi

# Use first found WordPress path for detailed analysis
wp_path="${wp_path%/}"

# WordPress version
wp_version=""
if [ -f "$wp_path/wp-includes/version.php" ]; then
    wp_version=$(grep "\$wp_version = " "$wp_path/wp-includes/version.php" 2>/dev/null | cut -d"'" -f2 || echo "unknown")
fi

# Check if wp-config.php is readable
config_readable="false"
if [ -r "$wp_path/wp-config.php" ]; then
    config_readable="true"
fi

# Database info from wp-config (name only, no credentials)
db_name=""
db_host=""
table_prefix=""
if [ "$config_readable" = "true" ]; then
    db_name=$(grep "DB_NAME" "$wp_path/wp-config.php" 2>/dev/null | cut -d"'" -f4 || echo "")
    db_host=$(grep "DB_HOST" "$wp_path/wp-config.php" 2>/dev/null | cut -d"'" -f4 || echo "localhost")
    table_prefix=$(grep "\$table_prefix" "$wp_path/wp-config.php" 2>/dev/null | cut -d"'" -f2 || echo "wp_")
fi

# Debug mode
wp_debug="false"
if grep -q "define.*WP_DEBUG.*true" "$wp_path/wp-config.php" 2>/dev/null; then
    wp_debug="true"
fi

# Count plugins
plugins_count=0
active_plugins=""
if [ -d "$wp_path/wp-content/plugins" ]; then
    plugins_count=$(find "$wp_path/wp-content/plugins" -maxdepth 1 -type d | wc -l)
    plugins_count=$((plugins_count - 1))
fi

# Count themes
themes_count=0
if [ -d "$wp_path/wp-content/themes" ]; then
    themes_count=$(find "$wp_path/wp-content/themes" -maxdepth 1 -type d | wc -l)
    themes_count=$((themes_count - 1))
fi

# Uploads directory size
uploads_size=""
if [ -d "$wp_path/wp-content/uploads" ]; then
    uploads_size=$(du -sh "$wp_path/wp-content/uploads" 2>/dev/null | awk "{print \$1}" || echo "unknown")
fi

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
if [ -f "$wp_path/wp-content/object-cache.php" ]; then
    object_cache="true"
fi

# Security plugins detection
security_plugins=""
for plugin in wordfence sucuri-scanner ithemes-security-pro all-in-one-wp-security-and-firewall; do
    if [ -d "$wp_path/wp-content/plugins/$plugin" ]; then
        if [ -n "$security_plugins" ]; then
            security_plugins="$security_plugins,"
        fi
        security_plugins="$security_plugins\"$plugin\""
    fi
done

# File permissions check
htaccess_exists="false"
htaccess_writable="false"
if [ -f "$wp_path/.htaccess" ]; then
    htaccess_exists="true"
    if [ -w "$wp_path/.htaccess" ]; then
        htaccess_writable="true"
    fi
fi

# wp-config permissions
config_perms=$(stat -c "%a" "$wp_path/wp-config.php" 2>/dev/null || echo "unknown")

# Check for common issues
issues=""

# Check .maintenance file (WordPress in maintenance mode)
if [ -f "$wp_path/.maintenance" ]; then
    issues="$issues\"WordPress in maintenance mode\","
fi

# Check for fatal error in debug.log
if [ -f "$wp_path/wp-content/debug.log" ]; then
    fatal_errors=$(tail -50 "$wp_path/wp-content/debug.log" 2>/dev/null | grep -c "Fatal error" || echo 0)
    if [ "$fatal_errors" -gt 0 ]; then
        issues="$issues\"$fatal_errors fatal errors in debug.log\","
    fi
fi

# Remove trailing comma from issues
issues="${issues%,}"

# Recent errors from debug.log
wp_errors=""
error_count=0
if [ -f "$wp_path/wp-content/debug.log" ]; then
    error_count=$(tail -100 "$wp_path/wp-content/debug.log" 2>/dev/null | grep -ci "error\|warning\|fatal" || echo 0)
    wp_errors=$(tail -20 "$wp_path/wp-content/debug.log" 2>/dev/null | grep -i "error\|fatal" | tail -5 | while read line; do echo "\"$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-200)\""; done | paste -sd "," -)
fi

# Total WordPress installation size
wp_total_size=$(du -sh "$wp_path" 2>/dev/null | awk "{print \$1}" || echo "unknown")

# Output JSON
cat << EOF
{
  "script": "40_wordpress_health",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": true,
  "installations": [$wp_paths],
  "primary_installation": {
    "path": "$wp_path",
    "version": "$wp_version",
    "total_size": "$wp_total_size"
  },
  "database": {
    "name": "$db_name",
    "host": "$db_host",
    "table_prefix": "$table_prefix"
  },
  "configuration": {
    "config_readable": $config_readable,
    "config_permissions": "$config_perms",
    "wp_debug": $wp_debug,
    "htaccess_exists": $htaccess_exists
  },
  "content": {
    "plugins_count": $plugins_count,
    "themes_count": $themes_count,
    "uploads_size": "${uploads_size:-unknown}"
  },
  "performance": {
    "cache_plugin": "$cache_plugin",
    "object_cache": $object_cache
  },
  "security": {
    "plugins": [${security_plugins:-}]
  },
  "issues": [${issues:-}],
  "errors": {
    "recent_count": $error_count,
    "recent_entries": [${wp_errors:-}]
  }
}
EOF
'
