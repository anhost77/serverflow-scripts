#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Web Access Logs Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Find access log
access_log=""
if [ -f /var/log/nginx/access.log ]; then
    access_log="/var/log/nginx/access.log"
elif [ -f /var/log/apache2/access.log ]; then
    access_log="/var/log/apache2/access.log"
elif [ -f /var/log/httpd/access_log ]; then
    access_log="/var/log/httpd/access_log"
fi

log_found="false"
[ -n "$access_log" ] && [ -f "$access_log" ] && log_found="true"

# Get last 24h entries (approximate - check timestamps)
total_requests=0
if [ "$log_found" = "true" ]; then
    # Use recent lines (last ~10000 as proxy for 24h)
    total_requests=$(tail -10000 "$access_log" 2>/dev/null | wc -l || echo 0)
fi

# Top 10 IPs by request count
top_ips=""
if [ "$log_found" = "true" ]; then
    top_ips=$(tail -10000 "$access_log" 2>/dev/null | awk "{print \$1}" | sort | uniq -c | sort -rn | head -10 | awk "{printf \"{\\\"ip\\\":\\\"%s\\\",\\\"requests\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Top URLs by request count
top_urls=""
if [ "$log_found" = "true" ]; then
    top_urls=$(tail -10000 "$access_log" 2>/dev/null | awk "{print \$7}" | sort | uniq -c | sort -rn | head -10 | awk "{url=\$2; gsub(/\"/, \"\\\\\\\"\", url); printf \"{\\\"url\\\":\\\"%s\\\",\\\"requests\\\":%s},\", url, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# HTTP status codes distribution
status_codes=""
if [ "$log_found" = "true" ]; then
    status_codes=$(tail -10000 "$access_log" 2>/dev/null | awk "{print \$9}" | grep -E "^[0-9]{3}$" | sort | uniq -c | sort -rn | awk "{printf \"{\\\"code\\\":%s,\\\"count\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Error counts (4xx and 5xx)
errors_4xx=0
errors_5xx=0
if [ "$log_found" = "true" ]; then
    errors_4xx=$(tail -10000 "$access_log" 2>/dev/null | awk "\$9 ~ /^4[0-9]{2}$/" | wc -l || echo 0)
    errors_5xx=$(tail -10000 "$access_log" 2>/dev/null | awk "\$9 ~ /^5[0-9]{2}$/" | wc -l || echo 0)
fi

# Top 404 URLs
top_404=""
if [ "$log_found" = "true" ]; then
    top_404=$(tail -10000 "$access_log" 2>/dev/null | awk "\$9 == 404 {print \$7}" | sort | uniq -c | sort -rn | head -5 | awk "{url=\$2; gsub(/\"/, \"\\\\\\\"\", url); printf \"{\\\"url\\\":\\\"%s\\\",\\\"count\\\":%s},\", url, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Top 5xx URLs
top_5xx=""
if [ "$log_found" = "true" ]; then
    top_5xx=$(tail -10000 "$access_log" 2>/dev/null | awk "\$9 ~ /^5[0-9]{2}$/ {print \$7}" | sort | uniq -c | sort -rn | head -5 | awk "{url=\$2; gsub(/\"/, \"\\\\\\\"\", url); printf \"{\\\"url\\\":\\\"%s\\\",\\\"count\\\":%s},\", url, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# User agents summary (bots vs browsers)
bots_count=0
browsers_count=0
if [ "$log_found" = "true" ]; then
    bots_count=$(tail -5000 "$access_log" 2>/dev/null | grep -ci "bot\|crawler\|spider\|curl\|wget" || echo 0)
    browsers_count=$(tail -5000 "$access_log" 2>/dev/null | grep -ci "mozilla\|chrome\|safari\|firefox" || echo 0)
fi

# Request methods
request_methods=""
if [ "$log_found" = "true" ]; then
    request_methods=$(tail -10000 "$access_log" 2>/dev/null | awk "{gsub(/\"/, \"\", \$6); print \$6}" | sort | uniq -c | sort -rn | head -5 | awk "{printf \"{\\\"method\\\":\\\"%s\\\",\\\"count\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Requests per hour (last entries)
hourly_pattern=""
if [ "$log_found" = "true" ]; then
    hourly_pattern=$(tail -10000 "$access_log" 2>/dev/null | awk -F"[\\[/:]" "{print \$5}" | sort | uniq -c | tail -12 | awk "{printf \"{\\\"hour\\\":\\\"%s\\\",\\\"requests\\\":%s},\", \$2, \$1}" | sed "s/,$//" | tr -d "\n")
fi

# Potential attack indicators
suspicious_requests=0
if [ "$log_found" = "true" ]; then
    suspicious_requests=$(tail -10000 "$access_log" 2>/dev/null | grep -ciE "\.\.\/|<script|union.*select|eval\(|base64" || echo 0)
fi

cat << EOF
{
  "script": "24_web_access_logs",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "log_file": "${access_log:-not found}",
  "log_found": $log_found,
  "summary": {
    "total_requests_analyzed": $total_requests,
    "errors_4xx": $errors_4xx,
    "errors_5xx": $errors_5xx,
    "bots_detected": $bots_count,
    "browsers_detected": $browsers_count,
    "suspicious_requests": $suspicious_requests
  },
  "top_ips": [${top_ips:-}],
  "top_urls": [${top_urls:-}],
  "status_codes": [${status_codes:-}],
  "top_404": [${top_404:-}],
  "top_5xx": [${top_5xx:-}],
  "request_methods": [${request_methods:-}],
  "hourly_distribution": [${hourly_pattern:-}]
}
EOF
'
