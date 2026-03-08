#!/bin/bash
# pm2-action.sh - PM2 app action (start/stop/restart/delete)
# Usage: pm2-action.sh <app_name> <action>
set -e

export HOME="${HOME:-/root}"
export PM2_HOME="${PM2_HOME:-/root/.pm2}"

APP_NAME="$1"
ACTION="$2"

if [ -z "$APP_NAME" ] || [ -z "$ACTION" ]; then
  echo "ERROR: Usage: pm2-action.sh <app_name> <action>"
  exit 1
fi

if ! command -v pm2 &> /dev/null; then
  echo "ERROR: PM2 is not installed"
  exit 1
fi

case "$ACTION" in
  start)
    pm2 start "$APP_NAME" --update-env 2>&1
    ;;
  stop)
    pm2 stop "$APP_NAME" 2>&1
    ;;
  restart)
    pm2 restart "$APP_NAME" --update-env 2>&1
    ;;
  delete)
    pm2 delete "$APP_NAME" 2>&1
    ;;
  *)
    echo "ERROR: Invalid action '$ACTION'. Use: start, stop, restart, delete"
    exit 1
    ;;
esac

# Save PM2 state
pm2 save --force 2>/dev/null || true

echo "SUCCESS: $ACTION completed for $APP_NAME"
