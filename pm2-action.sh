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
    echo "Deleting app $APP_NAME completely..."
    
    # Stop and delete from PM2
    pm2 stop "$APP_NAME" 2>/dev/null || true
    pm2 delete "$APP_NAME" 2>&1 || true
    
    # Delete app directory
    APP_DIR="/srv/nodejs/$APP_NAME"
    if [ -d "$APP_DIR" ]; then
      echo "Removing app directory: $APP_DIR"
      rm -rf "$APP_DIR"
    fi
    
    # Delete PM2 logs for this app
    PM2_LOG_DIR="$PM2_HOME/logs"
    if [ -d "$PM2_LOG_DIR" ]; then
      echo "Removing PM2 logs..."
      rm -f "$PM2_LOG_DIR/${APP_NAME}-out.log" 2>/dev/null || true
      rm -f "$PM2_LOG_DIR/${APP_NAME}-error.log" 2>/dev/null || true
      rm -f "$PM2_LOG_DIR/${APP_NAME}-"*.log 2>/dev/null || true
    fi
    
    echo "App $APP_NAME completely removed"
    ;;
  *)
    echo "ERROR: Invalid action '$ACTION'. Use: start, stop, restart, delete"
    exit 1
    ;;
esac

# Save PM2 state
pm2 save --force 2>/dev/null || true

echo "SUCCESS: $ACTION completed for $APP_NAME"
