#!/bin/bash
# ServerFlow - Install MariaDB
set -e

if command -v mysql &> /dev/null; then
  echo "MySQL/MariaDB already installed: $(mysql --version)"
  systemctl is-active mariadb && echo "MariaDB is running" && exit 0
  systemctl start mariadb 2>/dev/null || systemctl start mysql
  exit 0
fi

echo "Installing MariaDB..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y mariadb-server mariadb-client

systemctl enable mariadb
systemctl start mariadb

# Basic security
mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true

echo "✅ $(mysql --version) installed and running"
