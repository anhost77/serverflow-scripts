#!/bin/bash
# ServerFlow - Install Node.js 20 + PM2
set -e

if command -v node &> /dev/null; then
  echo "Node.js already installed: $(node -v)"
  if command -v pm2 &> /dev/null; then
    echo "PM2 already installed: $(pm2 -v)"
    # Ensure PM2 is running
    pm2 ping >/dev/null 2>&1 || pm2 resurrect >/dev/null 2>&1 || true
    systemctl is-active pm2-root >/dev/null 2>&1 || systemctl start pm2-root 2>/dev/null || true
    exit 0
  fi
fi

echo "Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "Installing PM2..."
npm install -g pm2

# Setup PM2 as systemd service and start it
pm2 startup systemd -u root --hp /root
pm2 save

# Ensure service is enabled and started
systemctl enable pm2-root 2>/dev/null || true
systemctl start pm2-root 2>/dev/null || pm2 resurrect 2>/dev/null || true

echo "✅ Node.js $(node -v) + PM2 $(pm2 -v) installed and running"
