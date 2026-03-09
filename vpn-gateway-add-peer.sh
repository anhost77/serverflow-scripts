#!/bin/bash
# vpn-gateway-add-peer.sh - Add a peer to the VPN gateway
# Usage: vpn-gateway-add-peer.sh <peer_name> <peer_public_key> <allowed_ip>
# Example: vpn-gateway-add-peer.sh "iPhone" "abc123..." "10.100.42.100/32"
# Output: JSON with peer config for client

PEER_NAME="$1"
PEER_PUBKEY="$2"
ALLOWED_IP="$3"

if [ -z "$PEER_NAME" ] || [ -z "$PEER_PUBKEY" ] || [ -z "$ALLOWED_IP" ]; then
    echo '{"error":"Usage: vpn-gateway-add-peer.sh <name> <pubkey> <allowed_ip>"}'
    exit 1
fi

# Get server info
SERVER_PUBKEY=$(cat /etc/wireguard/publickey)
SERVER_PORT=$(grep "ListenPort" /etc/wireguard/wg0.conf | cut -d'=' -f2 | tr -d ' ')
SERVER_SUBNET=$(grep "Address" /etc/wireguard/wg0.conf | cut -d'=' -f2 | tr -d ' ' | cut -d'/' -f1 | sed 's/\.[0-9]*$//')

# Add peer to WireGuard config
cat >> /etc/wireguard/wg0.conf << EOF

# ${PEER_NAME}
[Peer]
PublicKey = ${PEER_PUBKEY}
AllowedIPs = ${ALLOWED_IP}
EOF

# Apply config without restart (hot reload)
wg set wg0 peer "${PEER_PUBKEY}" allowed-ips "${ALLOWED_IP}"

# Add route for this peer (required because subnet exists on both eth0 and wg0)
PEER_IP=$(echo "${ALLOWED_IP}" | cut -d'/' -f1)
ip route add "${PEER_IP}/32" dev wg0 2>/dev/null || true

# Get server's public IP (for client config)
SERVER_ENDPOINT=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

# Output client config as JSON
cat << EOF
{
  "success": true,
  "peer_name": "${PEER_NAME}",
  "client_config": {
    "interface": {
      "private_key": "CLIENT_PRIVATE_KEY_HERE",
      "address": "${ALLOWED_IP}"
    },
    "peer": {
      "public_key": "${SERVER_PUBKEY}",
      "endpoint": "${SERVER_ENDPOINT}:${SERVER_PORT}",
      "allowed_ips": "${SERVER_SUBNET}.0/24",
      "persistent_keepalive": 25
    }
  }
}
EOF
