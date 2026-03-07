#!/bin/bash
# ServerFlow - Install Python 3
set -e

if command -v python3 &> /dev/null; then
  echo "Python already installed: $(python3 --version)"
  exit 0
fi

echo "Installing Python 3..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-pip python3-venv python3-dev build-essential
pip3 install --break-system-packages uvicorn gunicorn 2>/dev/null || pip3 install uvicorn gunicorn

echo "✅ $(python3 --version) installed"
