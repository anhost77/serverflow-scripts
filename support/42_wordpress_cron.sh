#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - WordPress Cron Status
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Find WordPress installations
wp_configs=$(find /var/www /srv/www /home -maxdepth 4 -name "wp-config.php" 2>/dev/null | head -5)

wp_found="false"
[ -n "$wp_configs" ] && wp_found="true"

# Check for WP-CLI
wpcli_available="false"
if command -v wp &>/dev/null; then
    wpcli_available="true"
fi

sites_data=""

for config in $wp_configs; do
    wp_dir=$(dirname "$config")
    
    # Get site URL
    site_url=$(grep -oP "define\s*\(\s*['\"]WP_SITEURL['\"]\s*,\s*['\"]\\K[^'\"]+(?=['\"])" "$config" 2>/dev/null || echo "unknown")
    
    # Check WP_CRON disabled
    cron_disabled="false"
    if grep -q "DISABLE_WP_CRON.*true" "$config" 2>/dev/null; then
        cron_disabled="true"
    fi
    
    # Check for external cron in system crontab
    external_cron="false"
    external_cron_entry=""
    if grep -r "wp-cron.php\|wp cron run" /etc/cron.* /var/spool/cron 2>/dev/null | grep -q "$wp_dir"; then
        external_cron="true"
        external_cron_entry=$(grep -r "wp-cron.php\|wp cron run" /etc/cron.* /var/spool/cron 2>/dev/null | grep "$wp_dir" | head -1 | sed "s/\"/\\\\\"/g" || echo "")
    fi
    
    # If WP-CLI available, get detailed cron info
    cron_events=""
    stuck_crons=""
    total_events=0
    overdue_events=0
    
    if [ "$wpcli_available" = "true" ]; then
        # Try to get cron event list
        if cd "$wp_dir" 2>/dev/null; then
            # Get cron events
            cron_output=$(wp cron event list --format=json --allow-root 2>/dev/null || echo "[]")
            
            if [ "$cron_output" != "[]" ] && [ -n "$cron_output" ]; then
                total_events=$(echo "$cron_output" | grep -o "\"hook\"" | wc -l || echo 0)
                
                # Get top 10 events
                cron_events=$(echo "$cron_output" | head -c 2000 | tr -d "\n")
                
                # Check for overdue events (more than 1 hour late)
                now=$(date +%s)
                overdue_events=$(echo "$cron_output" | grep -oP "\"next_run_gmt\":\"\K[^\"]+(?=\")" | while read -r ts; do
                    event_ts=$(date -d "$ts" +%s 2>/dev/null || echo 0)
                    if [ $((now - event_ts)) -gt 3600 ] && [ "$event_ts" -gt 0 ]; then
                        echo "1"
                    fi
                done | wc -l)
            fi
            
            # Check for stuck crons (running for too long)
            running=$(wp cron event list --status=running --format=json --allow-root 2>/dev/null || echo "[]")
            if [ "$running" != "[]" ]; then
                stuck_crons=$(echo "$running" | head -c 500 | tr -d "\n")
            fi
            
            cd - >/dev/null
        fi
    fi
    
    # Check last cron execution from wp-cron transient (approximate)
    # This would require DB access, skip for now
    
    # Estimate cron health
    cron_health="unknown"
    if [ "$wpcli_available" = "true" ]; then
        if [ "$overdue_events" -gt 10 ]; then
            cron_health="critical"
        elif [ "$overdue_events" -gt 0 ]; then
            cron_health="warning"
        elif [ "$total_events" -gt 0 ]; then
            cron_health="healthy"
        fi
    fi
    
    sites_data="$sites_data{\"path\":\"$wp_dir\",\"site_url\":\"$site_url\",\"wp_cron_disabled\":$cron_disabled,\"external_cron\":$external_cron,\"external_cron_entry\":\"$external_cron_entry\",\"total_events\":$total_events,\"overdue_events\":$overdue_events,\"health\":\"$cron_health\",\"events\":${cron_events:-[]},\"stuck\":${stuck_crons:-[]}},"
done

# Remove trailing comma
sites_data=$(echo "$sites_data" | sed "s/,$//" | tr -d "\n")

# System-level cron entries for WordPress
system_wp_crons=""
system_wp_crons=$(grep -rh "wp-cron\|wp cron" /etc/cron.* 2>/dev/null | head -5 | while read -r line; do
    escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | head -c 150)
    echo "\"$escaped\""
done | paste -sd "," - | tr -d "\n")

cat << EOF
{
  "script": "42_wordpress_cron",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "wordpress_found": $wp_found,
  "wp_cli_available": $wpcli_available,
  "system_cron_entries": [${system_wp_crons:-}],
  "sites": [${sites_data:-}]
}
EOF
'
