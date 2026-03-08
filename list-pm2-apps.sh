#!/bin/bash
# list-pm2-apps.sh - List PM2 apps

export HOME="${HOME:-/root}"
export PM2_HOME="${PM2_HOME:-/root/.pm2}"

# Check if PM2 is installed
if ! command -v pm2 &>/dev/null; then
  echo "[]"
  exit 0
fi

# Ensure PM2 daemon is running (connects to existing or starts new)
pm2 ping >/dev/null 2>&1 || pm2 resurrect 2>/dev/null || true

# Get JSON list
pm2 jlist 2>/dev/null || echo "[]"
