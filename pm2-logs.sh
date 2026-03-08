#!/bin/bash
# pm2-logs.sh - Get PM2 app logs
# Usage: pm2-logs.sh <app_name> [lines]
set -e

export HOME="${HOME:-/root}"
export PM2_HOME="${PM2_HOME:-/root/.pm2}"

APP_NAME="$1"
LINES="${2:-100}"

if [ -z "$APP_NAME" ]; then
  echo "ERROR: Usage: pm2-logs.sh <app_name> [lines]"
  exit 1
fi

if ! command -v pm2 &> /dev/null; then
  echo "ERROR: PM2 is not installed"
  exit 1
fi

pm2 logs "$APP_NAME" --nostream --lines "$LINES" 2>/dev/null || echo "No logs found for $APP_NAME"
