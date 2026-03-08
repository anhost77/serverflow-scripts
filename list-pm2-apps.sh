#!/bin/bash
# list-pm2-apps.sh - List PM2 apps

export HOME="${HOME:-/root}"

# Check if PM2 is installed
if ! command -v pm2 &>/dev/null; then
  echo "[]"
  exit 0
fi

# Check both locations for PM2 apps
# Priority: /etc/.pm2 (legacy from QEMU without HOME) > /root/.pm2

if [ -f "/etc/.pm2/dump.pm2" ]; then
  export PM2_HOME="/etc/.pm2"
elif [ -f "/root/.pm2/dump.pm2" ]; then
  export PM2_HOME="/root/.pm2"
else
  # No dump file, try default
  export PM2_HOME="/root/.pm2"
fi

# Resurrect and list
pm2 resurrect 2>/dev/null || true
pm2 jlist 2>/dev/null || echo "[]"
