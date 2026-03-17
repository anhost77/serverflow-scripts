#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Virtual Hosts Configuration
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Detect web server
web_server="none"
nginx_running="false"
apache_running="false"

if systemctl is-active nginx >/dev/null 2>&1; then
    web_server="nginx"
    nginx_running="true"
elif systemctl is-active apache2 >/dev/null 2>&1 || systemctl is-active httpd >/dev/null 2>&1; then
    web_server="apache"
    apache_running="true"
fi

# Nginx vhosts
nginx_vhosts=""
nginx_vhost_count=0
if [ -d /etc/nginx/sites-enabled ]; then
    nginx_vhost_count=$(ls -1 /etc/nginx/sites-enabled 2>/dev/null | wc -l || echo 0)
    nginx_vhosts=$(for f in /etc/nginx/sites-enabled/*; do
        [ -f "$f" ] || continue
        filename=$(basename "$f")
        # Extract server_name
        server_names=$(grep -h "server_name" "$f" 2>/dev/null | head -3 | sed "s/server_name//" | tr -d ";" | xargs | head -c 100)
        # Extract listen ports
        listen=$(grep -h "listen" "$f" 2>/dev/null | head -2 | awk "{print \$2}" | tr -d ";" | paste -sd "," -)
        # Check if SSL
        ssl="false"
        grep -q "ssl_certificate" "$f" 2>/dev/null && ssl="true"
        # Check root
        root=$(grep -h "root" "$f" 2>/dev/null | head -1 | awk "{print \$2}" | tr -d ";" || echo "")
        
        echo "{\"file\":\"$filename\",\"server_name\":\"$server_names\",\"listen\":\"$listen\",\"ssl\":$ssl,\"root\":\"$root\"}"
    done | paste -sd "," - | tr -d "\n")
fi

# Nginx conf.d
nginx_confd=""
if [ -d /etc/nginx/conf.d ]; then
    nginx_confd=$(ls -1 /etc/nginx/conf.d/*.conf 2>/dev/null | while read -r f; do
        filename=$(basename "$f")
        server_names=$(grep -h "server_name" "$f" 2>/dev/null | head -1 | sed "s/server_name//" | tr -d ";" | xargs | head -c 100)
        [ -z "$server_names" ] && continue
        echo "\"$filename ($server_names)\""
    done | paste -sd "," - | tr -d "\n")
fi

# Apache vhosts
apache_vhosts=""
apache_vhost_count=0
if [ -d /etc/apache2/sites-enabled ]; then
    apache_vhost_count=$(ls -1 /etc/apache2/sites-enabled 2>/dev/null | wc -l || echo 0)
    apache_vhosts=$(for f in /etc/apache2/sites-enabled/*; do
        [ -f "$f" ] || continue
        filename=$(basename "$f")
        # Extract ServerName
        server_name=$(grep -hi "ServerName" "$f" 2>/dev/null | head -1 | awk "{print \$2}" || echo "")
        # Extract ServerAlias
        aliases=$(grep -hi "ServerAlias" "$f" 2>/dev/null | head -1 | sed "s/ServerAlias//" | xargs | head -c 100)
        # Check port
        port=$(grep -h "<VirtualHost" "$f" 2>/dev/null | head -1 | grep -oP ":\K[0-9]+" || echo "80")
        # Check if SSL
        ssl="false"
        grep -qi "SSLEngine" "$f" 2>/dev/null && ssl="true"
        # Document root
        root=$(grep -hi "DocumentRoot" "$f" 2>/dev/null | head -1 | awk "{print \$2}" | tr -d "\"" || echo "")
        
        echo "{\"file\":\"$filename\",\"server_name\":\"$server_name\",\"aliases\":\"$aliases\",\"port\":\"$port\",\"ssl\":$ssl,\"document_root\":\"$root\"}"
    done | paste -sd "," - | tr -d "\n")
elif [ -d /etc/httpd/conf.d ]; then
    apache_vhost_count=$(ls -1 /etc/httpd/conf.d/*.conf 2>/dev/null | wc -l || echo 0)
    apache_vhosts=$(for f in /etc/httpd/conf.d/*.conf; do
        [ -f "$f" ] || continue
        filename=$(basename "$f")
        server_name=$(grep -hi "ServerName" "$f" 2>/dev/null | head -1 | awk "{print \$2}" || echo "")
        [ -z "$server_name" ] && continue
        ssl="false"
        grep -qi "SSLEngine" "$f" 2>/dev/null && ssl="true"
        echo "{\"file\":\"$filename\",\"server_name\":\"$server_name\",\"ssl\":$ssl}"
    done | paste -sd "," - | tr -d "\n")
fi

# DNS/hosts entries for local domains
local_hosts=$(grep -v "^#" /etc/hosts 2>/dev/null | grep -v "^$" | grep -v "localhost" | head -10 | while read -r line; do
    ip=$(echo "$line" | awk "{print \$1}")
    names=$(echo "$line" | awk "{for(i=2;i<=NF;i++) printf \"%s \", \$i}" | xargs)
    [ -n "$names" ] && echo "{\"ip\":\"$ip\",\"names\":\"$names\"}"
done | paste -sd "," - | tr -d "\n")

# Default document roots check
default_roots=""
roots_to_check=("/var/www/html" "/var/www" "/usr/share/nginx/html" "/srv/www")
for root in "${roots_to_check[@]}"; do
    if [ -d "$root" ]; then
        size=$(du -sh "$root" 2>/dev/null | awk "{print \$1}" || echo "?")
        files=$(find "$root" -maxdepth 2 -type f 2>/dev/null | wc -l || echo 0)
        default_roots="$default_roots{\"path\":\"$root\",\"size\":\"$size\",\"files_count\":$files},"
    fi
done
default_roots=$(echo "$default_roots" | sed "s/,$//" | tr -d "\n")

cat << EOF
{
  "script": "25_vhost_config",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "web_server": "$web_server",
  "nginx": {
    "running": $nginx_running,
    "vhost_count": $nginx_vhost_count,
    "vhosts": [${nginx_vhosts:-}],
    "conf_d": [${nginx_confd:-}]
  },
  "apache": {
    "running": $apache_running,
    "vhost_count": $apache_vhost_count,
    "vhosts": [${apache_vhosts:-}]
  },
  "local_hosts": [${local_hosts:-}],
  "document_roots": [${default_roots:-}]
}
EOF
'
