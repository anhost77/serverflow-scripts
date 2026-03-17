#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - WordPress Plugins List
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Find WordPress installations
wp_found="false"
wp_paths=""
plugins_data=""

# Common WordPress locations
search_paths=(
    "/var/www"
    "/srv/www"
    "/home"
    "/var/www/html"
)

# Find wp-config.php files
wp_configs=$(find "${search_paths[@]}" -maxdepth 4 -name "wp-config.php" 2>/dev/null | head -5)

if [ -n "$wp_configs" ]; then
    wp_found="true"
fi

# Process each WordPress installation
sites_data=""
for config in $wp_configs; do
    wp_dir=$(dirname "$config")
    plugins_dir="$wp_dir/wp-content/plugins"
    
    if [ ! -d "$plugins_dir" ]; then
        continue
    fi
    
    # Get site info
    site_url=""
    if [ -f "$config" ]; then
        site_url=$(grep -oP "define\s*\(\s*['\"]WP_HOME['\"]\s*,\s*['\"]\\K[^'\"]+(?=['\"])" "$config" 2>/dev/null || \
                   grep -oP "define\s*\(\s*['\"]WP_SITEURL['\"]\s*,\s*['\"]\\K[^'\"]+(?=['\"])" "$config" 2>/dev/null || \
                   echo "unknown")
    fi
    
    # Count plugins
    total_plugins=$(ls -1d "$plugins_dir"/*/ 2>/dev/null | wc -l || echo 0)
    
    # Get plugin details
    plugins_list=""
    for plugin_dir in "$plugins_dir"/*/; do
        [ -d "$plugin_dir" ] || continue
        plugin_name=$(basename "$plugin_dir")
        
        # Find main plugin file
        plugin_file=""
        if [ -f "$plugin_dir/$plugin_name.php" ]; then
            plugin_file="$plugin_dir/$plugin_name.php"
        else
            plugin_file=$(find "$plugin_dir" -maxdepth 1 -name "*.php" | head -1)
        fi
        
        # Extract plugin info from header
        version=""
        display_name="$plugin_name"
        if [ -f "$plugin_file" ]; then
            version=$(grep -i "Version:" "$plugin_file" 2>/dev/null | head -1 | sed "s/.*Version:[[:space:]]*//" | tr -d "\r" | head -c 20 || echo "")
            name_line=$(grep -i "Plugin Name:" "$plugin_file" 2>/dev/null | head -1 | sed "s/.*Plugin Name:[[:space:]]*//" | tr -d "\r" | head -c 50)
            [ -n "$name_line" ] && display_name="$name_line"
        fi
        
        # Check if active (check in active_plugins option - simplified check)
        active="unknown"
        
        # Get last modified time
        last_modified=$(stat -c %Y "$plugin_dir" 2>/dev/null || echo 0)
        last_modified_human=$(date -d "@$last_modified" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
        
        # Get directory size
        size=$(du -sh "$plugin_dir" 2>/dev/null | awk "{print \$1}" || echo "?")
        
        plugins_list="$plugins_list{\"name\":\"$plugin_name\",\"display_name\":\"$(echo "$display_name" | sed "s/\"/\\\\\"/g")\",\"version\":\"$version\",\"size\":\"$size\",\"last_modified\":\"$last_modified_human\"},"
    done
    
    # Remove trailing comma
    plugins_list=$(echo "$plugins_list" | sed "s/,$//" | tr -d "\n")
    
    # Must-use plugins
    mu_plugins_count=0
    mu_plugins_dir="$wp_dir/wp-content/mu-plugins"
    if [ -d "$mu_plugins_dir" ]; then
        mu_plugins_count=$(ls -1 "$mu_plugins_dir"/*.php 2>/dev/null | wc -l || echo 0)
    fi
    
    # Drop-ins
    dropins=""
    for dropin in "object-cache.php" "advanced-cache.php" "db.php" "maintenance.php"; do
        if [ -f "$wp_dir/wp-content/$dropin" ]; then
            dropins="$dropins\"$dropin\","
        fi
    done
    dropins=$(echo "$dropins" | sed "s/,$//" | tr -d "\n")
    
    sites_data="$sites_data{\"path\":\"$wp_dir\",\"site_url\":\"$site_url\",\"total_plugins\":$total_plugins,\"mu_plugins\":$mu_plugins_count,\"dropins\":[${dropins:-}],\"plugins\":[${plugins_list:-}]},"
done

# Remove trailing comma
sites_data=$(echo "$sites_data" | sed "s/,$//" | tr -d "\n")

# Check for WP-CLI
wpcli_available="false"
wpcli_version=""
if command -v wp &>/dev/null; then
    wpcli_available="true"
    wpcli_version=$(wp --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "")
fi

cat << EOF
{
  "script": "41_wordpress_plugins",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": $wp_found,
  "wp_cli": {
    "available": $wpcli_available,
    "version": "$wpcli_version"
  },
  "sites": [${sites_data:-}]
}
EOF
'
