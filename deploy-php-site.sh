#!/bin/bash
# ============================================
# ServerFlow - Deploy PHP Site from Git
# Usage: deploy-php-site.sh <site_name> <git_repo> <branch> [php_version]
# Example: deploy-php-site.sh mysite https://github.com/user/repo.git main 8.2
# ============================================
set -e

SITE_NAME="$1"
GIT_REPO="$2"
BRANCH="${3:-main}"
PHP_VERSION="${4:-8.2}"

# ============================================
# Validation
# ============================================
if [ -z "$SITE_NAME" ] || [ -z "$GIT_REPO" ]; then
  echo "❌ Usage: deploy-php-site.sh <site_name> <git_repo> <branch> [php_version]"
  echo "Example: deploy-php-site.sh mysite https://github.com/user/repo.git main 8.2"
  exit 1
fi

# Sanitize site name (alphanumeric + dash only)
SITE_NAME=$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

SITE_DIR="/var/www/${SITE_NAME}"
NGINX_AVAILABLE="/etc/nginx/sites-available/${SITE_NAME}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
TEMPLATE="/etc/nginx/templates/php-site.conf"

echo "🚀 Deploying PHP site: $SITE_NAME"
echo "   Repository: $GIT_REPO"
echo "   Branch: $BRANCH"
echo "   PHP version: $PHP_VERSION"
echo ""

# ============================================
# 1. Clone or update repository
# ============================================
if [ -d "$SITE_DIR/.git" ]; then
  echo "📦 Updating existing site..."
  cd "$SITE_DIR"
  
  # Stash local changes
  git stash --quiet 2>/dev/null || true
  
  # Backup wp-config.php if exists and not tracked by git
  WP_CONFIG_BACKUP=""
  if [ -f "$SITE_DIR/wp-config.php" ] && ! git ls-files --error-unmatch wp-config.php 2>/dev/null; then
    echo "📦 Backing up untracked wp-config.php..."
    WP_CONFIG_BACKUP=$(cat "$SITE_DIR/wp-config.php")
  fi
  
  # Fetch and reset to branch
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git reset --hard "origin/$BRANCH"
  
  # Restore wp-config.php if it was backed up
  if [ -n "$WP_CONFIG_BACKUP" ]; then
    echo "$WP_CONFIG_BACKUP" > "$SITE_DIR/wp-config.php"
    echo "📦 Restored wp-config.php"
  fi
  
  echo "✅ Updated to latest commit: $(git rev-parse --short HEAD)"
else
  echo "📦 Cloning repository..."
  
  # Remove directory if exists but not a git repo
  if [ -d "$SITE_DIR" ]; then
    rm -rf "$SITE_DIR"
  fi
  
  git clone --branch "$BRANCH" --single-branch "$GIT_REPO" "$SITE_DIR"
  cd "$SITE_DIR"
  
  echo "✅ Cloned commit: $(git rev-parse --short HEAD)"
fi

# ============================================
# 2. Set permissions
# ============================================
echo "🔐 Setting permissions..."
chown -R www-data:www-data "$SITE_DIR"
find "$SITE_DIR" -type d -exec chmod 755 {} \;
find "$SITE_DIR" -type f -exec chmod 644 {} \;

# WordPress specific permissions
if [ -f "$SITE_DIR/wp-config.php" ] || [ -f "$SITE_DIR/wp-config-sample.php" ]; then
  echo "📝 WordPress detected, applying specific permissions..."
  
  # wp-content needs write access
  if [ -d "$SITE_DIR/wp-content" ]; then
    chmod -R 775 "$SITE_DIR/wp-content"
  fi
  
  # Protect wp-config
  if [ -f "$SITE_DIR/wp-config.php" ]; then
    chmod 640 "$SITE_DIR/wp-config.php"
  fi
fi

# ============================================
# 3. Generate Nginx config
# ============================================
echo "⚙️ Generating Nginx configuration..."

if [ -f "$TEMPLATE" ]; then
  # Use template
  sed -e "s/{{SITE_NAME}}/${SITE_NAME}/g" \
      -e "s/{{SERVER_NAME}}/_/g" \
      -e "s/{{PHP_VERSION}}/${PHP_VERSION}/g" \
      "$TEMPLATE" > "$NGINX_AVAILABLE"
else
  # Fallback: generate inline
  cat > "$NGINX_AVAILABLE" << EOF
server {
    listen 80;
    server_name _;
    root /var/www/${SITE_NAME}/;
    index index.php index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # WordPress pretty permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP processing
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
EOF
fi

# ============================================
# 4. Enable site
# ============================================
if [ ! -L "$NGINX_ENABLED" ]; then
  ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"
  echo "✅ Site enabled"
fi

# ============================================
# 5. Test and reload Nginx
# ============================================
echo "🔍 Testing Nginx configuration..."
if nginx -t; then
  systemctl reload nginx
  echo "✅ Nginx reloaded"
else
  echo "❌ Nginx configuration error!"
  exit 1
fi

# ============================================
# 6. Setup auto-update cron
# ============================================
CRON_FILE="/etc/cron.d/serverflow-${SITE_NAME}"
CRON_SCRIPT="/opt/serverflow/update-${SITE_NAME}.sh"

mkdir -p /opt/serverflow

cat > "$CRON_SCRIPT" << EOF
#!/bin/bash
# Auto-update script for ${SITE_NAME}
cd "${SITE_DIR}"

# Fetch latest
git fetch origin ${BRANCH} --quiet

# Check if update needed
LOCAL=\$(git rev-parse HEAD)
REMOTE=\$(git rev-parse origin/${BRANCH})

if [ "\$LOCAL" != "\$REMOTE" ]; then
  echo "\$(date '+%Y-%m-%d %H:%M:%S') - Updating ${SITE_NAME}..."
  git reset --hard origin/${BRANCH}
  chown -R www-data:www-data "${SITE_DIR}"
  
  # Clear OPcache if PHP-FPM running
  systemctl is-active php${PHP_VERSION}-fpm && systemctl reload php${PHP_VERSION}-fpm
  
  echo "\$(date '+%Y-%m-%d %H:%M:%S') - Updated to \$(git rev-parse --short HEAD)"
fi
EOF

chmod +x "$CRON_SCRIPT"

# Cron every 5 minutes
echo "*/5 * * * * root $CRON_SCRIPT >> /var/log/serverflow-${SITE_NAME}.log 2>&1" > "$CRON_FILE"
chmod 644 "$CRON_FILE"

echo "✅ Auto-update cron configured (every 5 minutes)"

# ============================================
# 7. Summary
# ============================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Site deployed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Site name:      $SITE_NAME"
echo "Root directory: $SITE_DIR"
echo "Nginx config:   $NGINX_AVAILABLE"
echo "PHP-FPM socket: /run/php/php${PHP_VERSION}-fpm.sock"
echo "Auto-update:    $CRON_SCRIPT (every 5 min)"
echo "Update log:     /var/log/serverflow-${SITE_NAME}.log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Show current commit
echo ""
echo "Current deployment:"
cd "$SITE_DIR"
git log -1 --format="  Commit: %h%n  Author: %an%n  Date: %ad%n  Message: %s" --date=short
