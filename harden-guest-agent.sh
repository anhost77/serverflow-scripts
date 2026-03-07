#!/bin/bash
# ServerFlow - Harden QEMU Guest Agent (auto-restart on crash)
set -e

echo "Configuring QEMU Guest Agent for reliability..."

# Create systemd override for auto-restart
mkdir -p /etc/systemd/system/qemu-guest-agent.service.d/
cat > /etc/systemd/system/qemu-guest-agent.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=30
WatchdogSec=60
EOF

# Reload and restart
systemctl daemon-reload
systemctl restart qemu-guest-agent
systemctl enable qemu-guest-agent

echo "✅ QEMU Guest Agent hardened with auto-restart"
systemctl status qemu-guest-agent --no-pager | head -5
