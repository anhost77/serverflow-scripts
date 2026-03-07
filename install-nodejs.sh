#!/bin/bash
# ServerFlow - Install Node.js 20 + PM2
set -e

if command -v node &> /dev/null; then
  echo "Node.js already installed: $(node -v)"
  if command -v pm2 &> /dev/null; then
    echo "PM2 already installed: $(pm2 -v)"
    exit 0
  fi
fi

echo "Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "Installing PM2..."
npm install -g pm2
pm2 startup systemd -u root --hp /root
pm2 save

echo "✅ Node.js $(node -v) + PM2 $(pm2 -v) installed"
