#!/bin/bash
# list-pm2-apps.sh - List PM2 apps

# Force PM2 to use /root/.pm2 (standard location)
export HOME="${HOME:-/root}"
export PM2_HOME="${PM2_HOME:-$HOME/.pm2}"

# Check if PM2 is installed
if ! command -v pm2 &>/dev/null; then
  echo "[]"
  exit 0
fi

# If PM2_HOME doesn't exist but /etc/.pm2 does (legacy), use that
if [ ! -d "$PM2_HOME" ] && [ -d "/etc/.pm2" ]; then
  export PM2_HOME="/etc/.pm2"
fi

# Resurrect saved processes
pm2 resurrect 2>/dev/null || true

# Get JSON list
pm2 jlist 2>/dev/null || echo "[]"
