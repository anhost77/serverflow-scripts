#!/bin/bash
# list-pm2-apps.sh - List PM2 apps

export HOME="${HOME:-/root}"

# Check if PM2 is installed
if ! command -v pm2 &>/dev/null; then
  echo "[]"
  exit 0
fi

# Try /etc/.pm2 first (legacy from QEMU without HOME), then /root/.pm2
RESULT=""

# Check /etc/.pm2
if [ -d "/etc/.pm2" ]; then
  export PM2_HOME="/etc/.pm2"
  pm2 resurrect 2>/dev/null || true
  RESULT=$(pm2 jlist 2>/dev/null)
  if [ -n "$RESULT" ] && [ "$RESULT" != "[]" ]; then
    echo "$RESULT"
    exit 0
  fi
fi

# Fallback to /root/.pm2
export PM2_HOME="/root/.pm2"
pm2 resurrect 2>/dev/null || true
pm2 jlist 2>/dev/null || echo "[]"
