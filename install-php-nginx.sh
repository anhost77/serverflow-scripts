#!/bin/bash
# ============================================
# ServerFlow - Install PHP + Nginx Stack
# Optimized for WordPress production
# Usage: install-php-nginx.sh [php_version]
# Example: install-php-nginx.sh 8.2
# ============================================
set -e

PHP_VERSION="${1:-8.2}"
VALID_VERSIONS="8.1 8.2 8.3"

# Validate PHP version
if ! echo "$VALID_VERSIONS" | grep -qw "$PHP_VERSION"; then
  echo "❌ Invalid PHP version: $PHP_VERSION"
  echo "Valid versions: $VALID_VERSIONS"
  exit 1
fi

echo "🚀 Installing PHP $PHP_VERSION + Nginx stack..."

# ============================================
# 1. System preparation
# ============================================
export DEBIAN_FRONTEND=noninteractive

# Add PHP repository for multiple versions (Debian/Ubuntu)
if [ -f /etc/debian_version ]; then
  if ! command -v add-apt-repository &> /dev/null; then
    apt-get update
    apt-get install -y software-properties-common
  fi
  
  # Add sury.org PHP repository if not Debian 12+ with native PHP 8.2
  if ! apt-cache show php${PHP_VERSION}-fpm &> /dev/null 2>&1; then
    echo "Adding PHP repository..."
    curl -sSL https://packages.sury.org/php/README.txt | bash -s || true
    apt-get update
  fi
fi

apt-get update

# ============================================
# 2. Install Nginx
# ============================================
echo "📦 Installing Nginx..."
if ! command -v nginx &> /dev/null; then
  apt-get install -y nginx
  systemctl enable nginx
fi

# ============================================
# 3. Install PHP-FPM + Extensions
# ============================================
echo "📦 Installing PHP $PHP_VERSION with extensions..."

PHP_PACKAGES=(
  "php${PHP_VERSION}-fpm"
  "php${PHP_VERSION}-cli"
  "php${PHP_VERSION}-common"
  "php${PHP_VERSION}-mysql"
  "php${PHP_VERSION}-pgsql"
  "php${PHP_VERSION}-curl"
  "php${PHP_VERSION}-gd"
  "php${PHP_VERSION}-mbstring"
  "php${PHP_VERSION}-xml"
  "php${PHP_VERSION}-zip"
  "php${PHP_VERSION}-bcmath"
  "php${PHP_VERSION}-intl"
  "php${PHP_VERSION}-imagick"
  "php${PHP_VERSION}-redis"
  "php${PHP_VERSION}-opcache"
)

apt-get install -y "${PHP_PACKAGES[@]}" || {
  echo "⚠️ Some packages failed, trying core packages..."
  apt-get install -y \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-zip
}

# ============================================
# 4. Configure PHP-FPM Pool
# ============================================
echo "⚙️ Configuring PHP-FPM pool..."

FPM_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
FPM_SERVICE="php${PHP_VERSION}-fpm"

if [ -f "$FPM_POOL" ]; then
  # Backup original
  cp "$FPM_POOL" "${FPM_POOL}.backup" 2>/dev/null || true
  
  # Apply optimized settings
  sed -i 's/^pm = .*/pm = dynamic/' "$FPM_POOL"
  sed -i 's/^pm\.max_children = .*/pm.max_children = 10/' "$FPM_POOL"
  sed -i 's/^pm\.start_servers = .*/pm.start_servers = 2/' "$FPM_POOL"
  sed -i 's/^pm\.min_spare_servers = .*/pm.min_spare_servers = 1/' "$FPM_POOL"
  sed -i 's/^pm\.max_spare_servers = .*/pm.max_spare_servers = 3/' "$FPM_POOL"
  
  # Add pm.max_requests if not present
  if ! grep -q "^pm\.max_requests" "$FPM_POOL"; then
    echo "pm.max_requests = 500" >> "$FPM_POOL"
  else
    sed -i 's/^pm\.max_requests = .*/pm.max_requests = 500/' "$FPM_POOL"
  fi
fi

# ============================================
# 5. Configure php.ini (WordPress optimized)
# ============================================
echo "⚙️ Optimizing php.ini for WordPress..."

PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"

if [ -f "$PHP_INI" ]; then
  # Backup original
  cp "$PHP_INI" "${PHP_INI}.backup" 2>/dev/null || true
  
  # Memory & Upload limits
  sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
  sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
  sed -i 's/^post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
  sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
  sed -i 's/^max_input_vars = .*/max_input_vars = 3000/' "$PHP_INI"
  
  # Add max_input_vars if not present (usually commented)
  if ! grep -q "^max_input_vars" "$PHP_INI"; then
    sed -i '/\[PHP\]/a max_input_vars = 3000' "$PHP_INI"
  fi
  
  # Timezone
  sed -i 's|^;date.timezone =.*|date.timezone = Europe/Paris|' "$PHP_INI"
  sed -i 's|^date.timezone =.*|date.timezone = Europe/Paris|' "$PHP_INI"
  
  # OPcache settings
  sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "$PHP_INI"
  sed -i 's/^opcache.enable=.*/opcache.enable=1/' "$PHP_INI"
  sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$PHP_INI"
  sed -i 's/^opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$PHP_INI"
  sed -i 's/^;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/' "$PHP_INI"
  sed -i 's/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=4000/' "$PHP_INI"
  sed -i 's/^;opcache.revalidate_freq=.*/opcache.revalidate_freq=2/' "$PHP_INI"
fi

# ============================================
# 6. Configure Nginx (base config)
# ============================================
echo "⚙️ Configuring Nginx..."

# Create optimized nginx.conf if default
NGINX_CONF="/etc/nginx/nginx.conf"

# Enable gzip if not already
if ! grep -q "gzip_types" "$NGINX_CONF"; then
  sed -i '/http {/a \
    # Gzip compression\
    gzip on;\
    gzip_vary on;\
    gzip_proxied any;\
    gzip_comp_level 6;\
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;' "$NGINX_CONF"
fi

# Set client_max_body_size
if ! grep -q "client_max_body_size" "$NGINX_CONF"; then
  sed -i '/http {/a \    client_max_body_size 64M;' "$NGINX_CONF"
fi

# ============================================
# 7. Create PHP site template
# ============================================
echo "📝 Creating site template..."

mkdir -p /etc/nginx/templates

cat > /etc/nginx/templates/php-site.conf << 'TEMPLATE'
server {
    listen 80;
    server_name {{SERVER_NAME}};
    root /var/www/{{SITE_NAME}}/;
    index index.php index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logs
    access_log /var/log/nginx/{{SITE_NAME}}.access.log;
    error_log /var/log/nginx/{{SITE_NAME}}.error.log;

    # WordPress pretty permalinks
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # PHP processing
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php{{PHP_VERSION}}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    # Deny access to sensitive files
    location ~ /\.ht {
        deny all;
    }

    location ~ /\.git {
        deny all;
    }

    location ~ /wp-config\.php {
        deny all;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # WordPress uploads - no PHP execution
    location ~* /uploads/.*\.php$ {
        deny all;
    }

    # Increase timeout for WordPress admin
    location ~ ^/wp-admin/ {
        try_files $uri $uri/ /index.php?$args;
        fastcgi_read_timeout 300;
    }
}
TEMPLATE

# ============================================
# 8. Disable default site
# ============================================
if [ -L /etc/nginx/sites-enabled/default ]; then
  rm -f /etc/nginx/sites-enabled/default
  echo "📝 Disabled default Nginx site"
fi

# ============================================
# 9. Create www directory
# ============================================
mkdir -p /var/www
chown -R www-data:www-data /var/www

# ============================================
# 10. Restart services
# ============================================
echo "🔄 Restarting services..."

systemctl enable "$FPM_SERVICE"
systemctl restart "$FPM_SERVICE"
nginx -t && systemctl reload nginx

# ============================================
# 11. Verification
# ============================================
echo ""
echo "✅ Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHP version:    $(php -v | head -1)"
echo "PHP-FPM:        $FPM_SERVICE ($(systemctl is-active $FPM_SERVICE))"
echo "Nginx:          $(nginx -v 2>&1)"
echo "Nginx status:   $(systemctl is-active nginx)"
echo "FPM socket:     /run/php/php${PHP_VERSION}-fpm.sock"
echo "Site template:  /etc/nginx/templates/php-site.conf"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To deploy a site, use: deploy-php-site.sh <name> <git_repo> <branch> [php_version]"
