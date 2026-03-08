#!/bin/bash
# list-pm2-apps.sh - List PM2 apps with proper initialization

# Check if PM2 is installed
if ! command -v pm2 &>/dev/null; then
  echo "[]"
  exit 0
fi

# Ensure PM2 daemon is started (resurrect saved processes)
pm2 resurrect 2>/dev/null || true

# Get JSON list
OUTPUT=$(pm2 jlist 2>/dev/null)

# If empty or error, return empty array
if [ -z "$OUTPUT" ] || [ "$OUTPUT" = "[]" ]; then
  # Try reloading PM2 dump
  if [ -f ~/.pm2/dump.pm2 ]; then
    pm2 resurrect 2>/dev/null
    OUTPUT=$(pm2 jlist 2>/dev/null)
  fi
fi

# Return output or empty array
echo "${OUTPUT:-[]}"
