#!/bin/bash
# ServerFlow - Install PostgreSQL
set -e

if command -v psql &> /dev/null; then
  echo "PostgreSQL already installed: $(psql --version)"
  systemctl is-active postgresql && echo "PostgreSQL is running" && exit 0
  systemctl start postgresql
  exit 0
fi

echo "Installing PostgreSQL..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y postgresql postgresql-contrib

systemctl enable postgresql
systemctl start postgresql

# Wait for PostgreSQL to be ready
for i in {1..30}; do
  sudo -u postgres psql -c "SELECT 1" &>/dev/null && break
  sleep 1
done

echo "✅ $(psql --version) installed and running"
