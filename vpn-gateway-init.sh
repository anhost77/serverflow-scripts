#!/bin/bash
# vpn-gateway-init.sh - Initialize VPN Gateway container
# Called at first boot with: vpn-gateway-init.sh <listen_port> <subnet_prefix>
# Example: vpn-gateway-init.sh 51820 10.100.42

LISTEN_PORT="${1:-51820}"
SUBNET_PREFIX="${2:-10.100.1}"

# Ensure WireGuard is installed
apk update
apk add wireguard-tools curl jq

# Create WireGuard directory
mkdir -p /etc/wireguard

# Generate server keys if not exist
if [ ! -f /etc/wireguard/privatekey ]; then
    wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
    chmod 600 /etc/wireguard/privatekey
fi

PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
PUBLIC_KEY=$(cat /etc/wireguard/publickey)

# Create WireGuard config
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = ${SUBNET_PREFIX}.2/24
ListenPort = ${LISTEN_PORT}
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT

# Peers will be added dynamically via API
EOF

chmod 600 /etc/wireguard/wg0.conf

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

# Create symlink for OpenRC service
ln -sf /etc/init.d/wg-quick /etc/init.d/wg-quick.wg0

# Enable and start WireGuard
rc-update add wg-quick.wg0 default
rc-service wg-quick.wg0 start 2>/dev/null || wg-quick up wg0

# Output status
echo "VPN Gateway initialized"
echo "Public Key: ${PUBLIC_KEY}"
echo "Listen Port: ${LISTEN_PORT}"
echo "Subnet: ${SUBNET_PREFIX}.0/24"
