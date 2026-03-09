#!/bin/bash
# vpn-gateway-status.sh - Get VPN gateway status
# Output: JSON with status, public key, peers

PUBLIC_KEY=$(cat /etc/wireguard/publickey 2>/dev/null || echo "")
LISTEN_PORT=$(grep "ListenPort" /etc/wireguard/wg0.conf 2>/dev/null | cut -d'=' -f2 | tr -d ' ')

# Check if WireGuard is running
if wg show wg0 &>/dev/null; then
    STATUS="running"
else
    STATUS="stopped"
fi

# Get peer count
PEER_COUNT=$(wg show wg0 peers 2>/dev/null | wc -l || echo 0)

# Get peers with last handshake
PEERS="["
first=1
while read -r line; do
    [ -z "$line" ] && continue
    pubkey=$(echo "$line" | awk '{print $1}')
    endpoint=$(wg show wg0 endpoints 2>/dev/null | grep "$pubkey" | awk '{print $2}')
    handshake=$(wg show wg0 latest-handshakes 2>/dev/null | grep "$pubkey" | awk '{print $2}')
    
    [ $first -eq 0 ] && PEERS+=","
    first=0
    PEERS+="{\"public_key\":\"$pubkey\",\"endpoint\":\"$endpoint\",\"last_handshake\":$handshake}"
done < <(wg show wg0 peers 2>/dev/null)
PEERS+="]"

cat << EOF
{
  "status": "${STATUS}",
  "public_key": "${PUBLIC_KEY}",
  "listen_port": ${LISTEN_PORT:-51820},
  "peer_count": ${PEER_COUNT},
  "peers": ${PEERS}
}
EOF
