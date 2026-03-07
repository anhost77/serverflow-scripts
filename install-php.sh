#!/bin/bash
# ServerFlow - Install PHP with FPM
set -e

if command -v php &> /dev/null; then
  echo "PHP already installed: $(php -v | head -1)"
  FPM=$(systemctl list-units --type=service | grep -oP 'php[0-9.]+-fpm' | head -1 || echo "php-fpm")
  systemctl is-active $FPM && echo "PHP-FPM is running" && exit 0
  systemctl start $FPM 2>/dev/null || true
  exit 0
fi

echo "Installing PHP with FPM..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y php-fpm php-cli php-common php-mysql php-pgsql php-curl php-gd php-mbstring php-xml php-zip php-bcmath

FPM=$(systemctl list-units --type=service | grep -oP 'php[0-9.]+-fpm' | head -1 || echo "php-fpm")
systemctl enable $FPM
systemctl start $FPM

echo "✅ $(php -v | head -1) installed with FPM"
