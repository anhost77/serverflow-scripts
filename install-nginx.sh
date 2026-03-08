#!/bin/bash
# ServerFlow - Install Nginx
set -e

if command -v nginx &> /dev/null; then
  echo "Nginx already installed: $(nginx -v 2>&1)"
  systemctl is-active nginx && echo "Nginx is running" && exit 0
  systemctl start nginx 2>/dev/null || true
  exit 0
fi

echo "Installing Nginx..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx

# Disable default site
rm -f /etc/nginx/sites-enabled/default

# Enable and start
systemctl enable nginx
systemctl start nginx

echo "✅ Nginx installed: $(nginx -v 2>&1)"
