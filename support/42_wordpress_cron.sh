#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - WordPress Cron Analysis
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
  "script": "42_wordpress_cron",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": false,
  "message": "No WordPress installation found"
}
ENDJSON
    exit 0
fi

# Check if WP-CLI is available
wp_cli_available="false"
if command -v wp &> /dev/null; then
    wp_cli_available="true"
fi

# Check DISABLE_WP_CRON in wp-config
wp_cron_disabled="false"
if grep -q "DISABLE_WP_CRON.*true" "$wp_path/wp-config.php" 2>/dev/null; then
    wp_cron_disabled="true"
fi

# Check system cron for wp-cron
system_cron_configured="false"
if grep -r "wp-cron" /etc/cron* /var/spool/cron* 2>/dev/null | grep -q "$wp_path"; then
    system_cron_configured="true"
fi

# Check wp-cron.php accessibility
cron_accessible="false"
if [ -f "$wp_path/wp-cron.php" ] && [ -r "$wp_path/wp-cron.php" ]; then
    cron_accessible="true"
fi

# Get cron jobs via WP-CLI if available
cron_events=""
cron_count=0
if [ "$wp_cli_available" = "true" ]; then
    # Try to get cron events (may fail if WP not properly configured)
    cron_output=$(cd "$wp_path" && wp cron event list --format=json 2>/dev/null || echo "[]")
    if [ "$cron_output" != "[]" ] && echo "$cron_output" | grep -q "hook"; then
        cron_events="$cron_output"
        cron_count=$(echo "$cron_output" | grep -c "hook" || echo "0")
    fi
fi

# Output JSON
cat << ENDJSON
{
  "script": "42_wordpress_cron",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": true,
  "path": "${wp_path}",
  "wp_cli_available": ${wp_cli_available},
  "configuration": {
    "disable_wp_cron": ${wp_cron_disabled},
    "system_cron_configured": ${system_cron_configured},
    "wp_cron_accessible": ${cron_accessible}
  },
  "recommendation": $([ "$wp_cron_disabled" = "true" ] && [ "$system_cron_configured" = "true" ] && echo '"Properly configured with system cron"' || echo '"Consider using system cron instead of WP-Cron"'),
  "scheduled_events_count": ${cron_count}
}
ENDJSON
