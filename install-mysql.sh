#!/bin/bash
# ServerFlow - Install MariaDB (secured)
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

# Security hardening (equivalent to mysql_secure_installation)
mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true

echo "✅ $(mysql --version) installed and secured"
