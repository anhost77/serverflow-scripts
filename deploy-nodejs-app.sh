#!/bin/bash
# deploy-nodejs-app.sh - Deploy Node.js app with PM2
# Usage: deploy-nodejs-app.sh <name> <repo_url> <branch> <port> [env_vars_base64]

set -e

# Fix HOME/PM2_HOME for QEMU guest agent
export HOME="${HOME:-/root}"
export PM2_HOME="${PM2_HOME:-$HOME/.pm2}"

NAME="$1"
REPO_URL="$2"
BRANCH="${3:-main}"
PORT="${4:-3000}"
ENV_BASE64="$5"

if [ -z "$NAME" ] || [ -z "$REPO_URL" ]; then
  echo "Usage: $0 <name> <repo_url> [branch] [port] [env_base64]"
  exit 1
fi

# Sanitize app name
SAFE_NAME=$(echo "$NAME" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')
APP_DIR="/srv/nodejs/${SAFE_NAME}"

echo "=== Deploying ${SAFE_NAME} ==="
echo "Repository: ${REPO_URL}"
echo "Branch: ${BRANCH}"
echo "Port: ${PORT}"

# Check Node.js
if ! command -v node &> /dev/null; then
  echo "ERROR: Node.js is not installed"
  exit 1
fi

if ! command -v pm2 &> /dev/null; then
  echo "ERROR: PM2 is not installed"
  exit 1
fi

# Create base directory
mkdir -p /srv/nodejs

# Clone or update repository
if [ -d "$APP_DIR" ]; then
  echo "Updating existing repository..."
  cd "$APP_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git reset --hard "origin/$BRANCH"
else
  echo "Cloning repository..."
  git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
fi

# Install dependencies
echo "Installing dependencies..."
if [ -f "package-lock.json" ]; then
  npm ci --production --no-audit --no-fund
elif [ -f "yarn.lock" ]; then
  command -v yarn &>/dev/null || npm install -g yarn
  yarn install --production --frozen-lockfile
else
  npm install --production --no-audit --no-fund
fi

# Build if needed
if [ ! -d "dist" ] && grep -q '"build"' package.json 2>/dev/null; then
  echo "Building application..."
  npm run build || true
fi

# Determine entry point
ENTRY=""
for f in dist/index.js dist/main.js index.js server.js app.js; do
  if [ -f "$f" ]; then
    ENTRY="$f"
    break
  fi
done

if [ -z "$ENTRY" ] && [ -f "package.json" ]; then
  ENTRY=$(node -p "require('./package.json').main || 'index.js'" 2>/dev/null || echo "index.js")
fi

if [ ! -f "$ENTRY" ]; then
  echo "ERROR: Could not find entry point. Tried: dist/index.js, index.js, server.js, app.js"
  exit 1
fi

echo "Entry point: $ENTRY"

# Stop existing process
pm2 delete "$SAFE_NAME" 2>/dev/null || true

# Decode and apply env vars
export PORT="$PORT"
if [ -n "$ENV_BASE64" ]; then
  eval "$(echo "$ENV_BASE64" | base64 -d)"
fi

# Start with PM2
echo "Starting with PM2..."
pm2 start "$ENTRY" --name "$SAFE_NAME" --update-env

# Configure PM2 to start on boot (if not already done)
if [ ! -f /etc/systemd/system/pm2-root.service ]; then
  echo "Configuring PM2 startup..."
  pm2 startup systemd -u root --hp /root 2>/dev/null || true
fi

# Save PM2 state
pm2 save --force

# Ensure cron is installed
command -v crontab >/dev/null 2>&1 || (apt-get install -y cron >/dev/null 2>&1 && systemctl enable cron && systemctl start cron)

# Install auto-update cron (idempotent)
echo "Setting up auto-update cron..."
CRON_JOB="*/5 * * * * cd /srv/nodejs/${SAFE_NAME} && git fetch origin ${BRANCH} --quiet 2>/dev/null && git diff --quiet HEAD origin/${BRANCH} || (git pull origin ${BRANCH} && npm install --production --silent && pm2 restart ${SAFE_NAME} --update-env) >/dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "/srv/nodejs/${SAFE_NAME}"; echo "$CRON_JOB") | crontab -
echo "Auto-update cron installed (every 5 min)"

echo ""
echo "=== Deployment Complete ==="
pm2 show "$SAFE_NAME" --no-color 2>/dev/null | head -20

exit 0
