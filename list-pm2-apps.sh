#!/bin/bash
# list-pm2-apps.sh - List PM2 apps with proper HOME

# Set HOME if not set (QEMU guest agent issue)
export HOME="${HOME:-/root}"

# Check if PM2 is installed
if ! command -v pm2 &>/dev/null; then
  echo "[]"
  exit 0
fi

# Resurrect saved processes
pm2 resurrect 2>/dev/null || true

# Get JSON list
pm2 jlist 2>/dev/null || echo "[]"
