#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - SSL Certificates Check
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Find SSL certificates
certs_found=""
certs_array=""

# Check common locations
cert_paths=(
    "/etc/letsencrypt/live"
    "/etc/ssl/certs"
    "/etc/nginx/ssl"
    "/etc/apache2/ssl"
    "/etc/pki/tls/certs"
)

# Check Let'\''s Encrypt certificates first (most common)
le_certs=""
if [ -d /etc/letsencrypt/live ]; then
    le_certs=$(for domain_dir in /etc/letsencrypt/live/*/; do
        [ -d "$domain_dir" ] || continue
        domain=$(basename "$domain_dir")
        cert_file="$domain_dir/cert.pem"
        [ -f "$cert_file" ] || continue
        
        # Get certificate info
        info=$(openssl x509 -in "$cert_file" -noout -dates -subject 2>/dev/null || echo "")
        if [ -n "$info" ]; then
            subject=$(echo "$info" | grep "subject=" | sed "s/subject=//" | sed "s/\"/\\\\\"/g")
            not_before=$(echo "$info" | grep "notBefore=" | sed "s/notBefore=//" | xargs)
            not_after=$(echo "$info" | grep "notAfter=" | sed "s/notAfter=//" | xargs)
            
            # Calculate days until expiry
            expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            
            # Status
            status="valid"
            [ "$days_left" -lt 30 ] && status="expiring_soon"
            [ "$days_left" -lt 7 ] && status="critical"
            [ "$days_left" -lt 0 ] && status="expired"
            
            echo "{\"domain\":\"$domain\",\"type\":\"letsencrypt\",\"not_after\":\"$not_after\",\"days_left\":$days_left,\"status\":\"$status\"}"
        fi
    done | paste -sd "," - | tr -d "\n")
fi

# Check Nginx SSL configurations
nginx_ssl=""
if [ -d /etc/nginx ]; then
    nginx_ssl=$(grep -rh "ssl_certificate[^_]" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | grep -v "ssl_certificate_key" | awk "{print \$2}" | tr -d ";" | sort -u | head -10 | while read -r cert_path; do
        [ -f "$cert_path" ] || continue
        info=$(openssl x509 -in "$cert_path" -noout -dates -subject 2>/dev/null || echo "")
        if [ -n "$info" ]; then
            cn=$(echo "$info" | grep "subject=" | grep -oP "CN\s*=\s*\K[^,/]+" | head -1 || basename "$cert_path")
            not_after=$(echo "$info" | grep "notAfter=" | sed "s/notAfter=//" | xargs)
            expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            status="valid"
            [ "$days_left" -lt 30 ] && status="expiring_soon"
            [ "$days_left" -lt 7 ] && status="critical"
            [ "$days_left" -lt 0 ] && status="expired"
            echo "{\"domain\":\"$cn\",\"path\":\"$cert_path\",\"not_after\":\"$not_after\",\"days_left\":$days_left,\"status\":\"$status\"}"
        fi
    done | paste -sd "," - | tr -d "\n")
fi

# Check system CA certificates count
ca_count=0
if [ -d /etc/ssl/certs ]; then
    ca_count=$(ls -1 /etc/ssl/certs/*.pem 2>/dev/null | wc -l || echo 0)
fi

# Summary
total_certs=0
expiring_soon=0
expired=0
critical=0

all_certs="[${le_certs:-}${le_certs:+,}${nginx_ssl:-}]"
# Remove trailing/leading commas and fix empty arrays
all_certs=$(echo "$all_certs" | sed "s/,]/]/g" | sed "s/\[,/[/g" | sed "s/,,/,/g")

# Count warnings (approximate from output)
expiring_soon=$(echo "$all_certs" | grep -o "expiring_soon" | wc -l || echo 0)
expired=$(echo "$all_certs" | grep -o "\"expired\"" | wc -l || echo 0)
critical=$(echo "$all_certs" | grep -o "\"critical\"" | wc -l || echo 0)

# Check certbot status
certbot_installed="false"
certbot_version=""
if command -v certbot &>/dev/null; then
    certbot_installed="true"
    certbot_version=$(certbot --version 2>&1 | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
fi

# Auto-renewal timer
renewal_timer="inactive"
if systemctl is-active certbot.timer &>/dev/null || systemctl is-active certbot-renew.timer &>/dev/null; then
    renewal_timer="active"
fi

cat << EOF
{
  "script": "23_ssl_certificates",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "certbot": {
    "installed": $certbot_installed,
    "version": "$certbot_version",
    "renewal_timer": "$renewal_timer"
  },
  "summary": {
    "expiring_soon": $expiring_soon,
    "critical": $critical,
    "expired": $expired,
    "ca_certificates": $ca_count
  },
  "certificates": $all_certs
}
EOF
'
