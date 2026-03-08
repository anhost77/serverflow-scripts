#!/bin/bash
# reinstall-cron.sh - Reinstall auto-update cron for an app
# Usage: reinstall-cron.sh <app_name> <branch>

export HOME="${HOME:-/root}"

APP_NAME="$1"
BRANCH="${2:-main}"

if [ -z "$APP_NAME" ]; then
  echo "ERROR: Usage: reinstall-cron.sh <app_name> [branch]"
  exit 1
fi

# Ensure cron is installed
command -v crontab >/dev/null 2>&1 || (apt-get install -y cron >/dev/null 2>&1 && systemctl enable cron && systemctl start cron)

CRON_JOB="*/5 * * * * cd /srv/nodejs/${APP_NAME} && git fetch origin ${BRANCH} --quiet 2>/dev/null && git diff --quiet HEAD origin/${BRANCH} || (git pull origin ${BRANCH} && npm install --production --silent && pm2 restart ${APP_NAME} --update-env) >/dev/null 2>&1"

(crontab -l 2>/dev/null | grep -v "/srv/nodejs/${APP_NAME}"; echo "$CRON_JOB") | crontab -

echo "SUCCESS: Auto-update cron reinstalled for ${APP_NAME}"
