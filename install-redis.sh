#!/bin/bash
# ServerFlow - Install Redis
set -e

if command -v redis-cli &> /dev/null; then
  echo "Redis already installed: $(redis-server --version)"
  systemctl is-active redis-server && echo "Redis is running" && exit 0
  systemctl start redis-server
  exit 0
fi

echo "Installing Redis..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y redis-server

systemctl enable redis-server
systemctl start redis-server

echo "✅ $(redis-server --version) installed and running"
