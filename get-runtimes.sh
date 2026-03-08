#!/bin/bash
# get-runtimes.sh - Detect installed runtimes
# Output: JSON object with runtime status

# Fix HOME for QEMU guest agent
export HOME="${HOME:-/root}"

json='{'

# Node.js
if command -v node &>/dev/null; then
  ver=$(node -v 2>/dev/null | tr -d 'v')
  json+='"node":{"installed":true,"version":"'"$ver"'"},'
else
  json+='"node":{"installed":false,"version":""},'
fi

# PM2
if command -v pm2 &>/dev/null; then
  ver=$(pm2 -v 2>/dev/null)
  json+='"pm2":{"installed":true,"version":"'"$ver"'"},'
else
  json+='"pm2":{"installed":false,"version":""},'
fi

# PHP
if command -v php &>/dev/null; then
  ver=$(php -v 2>/dev/null | head -1 | awk '{print $2}')
  json+='"php":{"installed":true,"version":"'"$ver"'"},'
else
  json+='"php":{"installed":false,"version":""},'
fi

# Python
if command -v python3 &>/dev/null; then
  ver=$(python3 -V 2>/dev/null | awk '{print $2}')
  json+='"python":{"installed":true,"version":"'"$ver"'"},'
else
  json+='"python":{"installed":false,"version":""},'
fi

# Docker
if command -v docker &>/dev/null; then
  ver=$(docker -v 2>/dev/null | awk '{print $3}' | tr -d ',')
  json+='"docker":{"installed":true,"version":"'"$ver"'"},'
else
  json+='"docker":{"installed":false,"version":""},'
fi

# Nginx
if command -v nginx &>/dev/null; then
  ver=$(nginx -v 2>&1 | awk -F/ '{print $2}')
  json+='"nginx":{"installed":true,"version":"'"$ver"'"},'
else
  json+='"nginx":{"installed":false,"version":""},'
fi

# Git
if command -v git &>/dev/null; then
  ver=$(git --version 2>/dev/null | awk '{print $3}')
  json+='"git":{"installed":true,"version":"'"$ver"'"}'
else
  json+='"git":{"installed":false,"version":""}'
fi

json+='}'
echo "$json"
