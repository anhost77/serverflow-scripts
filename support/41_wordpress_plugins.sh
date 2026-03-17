#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - WordPress Plugins Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

# Find WordPress path
wp_path=""
for dir in /var/www/html /var/www /home/*/public_html /srv/www/*; do
    [ ! -d "$dir" ] && continue
    if [ -f "$dir/wp-config.php" ]; then
        wp_path="$dir"
        break
    fi
    for subdir in "$dir"/*/; do
        [ -f "$subdir/wp-config.php" ] && wp_path="${subdir%/}" && break
    done
    [ -n "$wp_path" ] && break
done

if [ -z "$wp_path" ]; then
    cat << 'ENDJSON'
{
  "script": "41_wordpress_plugins",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": false,
  "message": "No WordPress installation found"
}
ENDJSON
    exit 0
fi

plugins_dir="$wp_path/wp-content/plugins"
plugins_list=""
plugins_count=0
active_count=0
inactive_count=0
update_available=0

if [ -d "$plugins_dir" ]; then
    for plugin_dir in "$plugins_dir"/*/; do
        [ ! -d "$plugin_dir" ] && continue
        plugin_name=$(basename "$plugin_dir")
        [ "$plugin_name" = "*" ] && continue
        
        plugins_count=$((plugins_count + 1))
        
        # Get plugin version from main PHP file
        plugin_version="unknown"
        main_file="$plugin_dir/$plugin_name.php"
        if [ -f "$main_file" ]; then
            plugin_version=$(grep -i "Version:" "$main_file" 2>/dev/null | head -1 | grep -oP "[0-9]+\.[0-9]+\.?[0-9]*" | head -1)
        fi
        plugin_version="${plugin_version:-unknown}"
        
        # Get plugin name from header
        plugin_display_name="$plugin_name"
        if [ -f "$main_file" ]; then
            header_name=$(grep -i "Plugin Name:" "$main_file" 2>/dev/null | head -1 | sed 's/.*Plugin Name:\s*//' | tr -d '\r')
            [ -n "$header_name" ] && plugin_display_name="$header_name"
        fi
        
        # Add to list
        [ -n "$plugins_list" ] && plugins_list="$plugins_list,"
        plugins_list="${plugins_list}{\"slug\":\"$plugin_name\",\"name\":\"$plugin_display_name\",\"version\":\"$plugin_version\"}"
    done
fi

# Output JSON
cat << ENDJSON
{
  "script": "41_wordpress_plugins",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": true,
  "path": "${wp_path}",
  "plugins_directory": "${plugins_dir}",
  "total_count": ${plugins_count},
  "plugins": [${plugins_list}]
}
ENDJSON
