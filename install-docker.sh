#!/bin/bash
# ServerFlow - Install Docker
set -e

if command -v docker &> /dev/null; then
  echo "Docker already installed: $(docker --version)"
  systemctl is-active docker && echo "Docker is running" && exit 0
  systemctl start docker
  exit 0
fi

echo "Installing Docker..."
curl -fsSL https://get.docker.com | sh

systemctl enable docker
systemctl start docker

echo "✅ $(docker --version) installed and running"
