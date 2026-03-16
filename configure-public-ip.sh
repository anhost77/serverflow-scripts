#!/bin/bash
# configure-public-ip.sh
# Configure a VM for public IP access via VNet infra
#
# Usage: configure-public-ip.sh <interface> <private_ip> <gateway> <table_id> <table_name>
# Example: configure-public-ip.sh ens20 10.100.200.22 10.100.200.254 200 public

set -e

INTERFACE="$1"
PRIVATE_IP="$2"
GATEWAY="$3"
TABLE_ID="$4"
TABLE_NAME="$5"

if [ -z "$INTERFACE" ] || [ -z "$PRIVATE_IP" ] || [ -z "$GATEWAY" ]; then
    echo "Usage: $0 <interface> <private_ip> <gateway> [table_id] [table_name]"
    exit 1
fi

TABLE_ID="${TABLE_ID:-200}"
TABLE_NAME="${TABLE_NAME:-public}"

echo "[1/4] Configuring IP $PRIVATE_IP on $INTERFACE..."
ip addr add "$PRIVATE_IP/24" dev "$INTERFACE" 2>/dev/null || true
ip link set "$INTERFACE" up

echo "[2/4] Setting up routing table..."
grep -q "$TABLE_ID $TABLE_NAME" /etc/iproute2/rt_tables 2>/dev/null || echo "$TABLE_ID $TABLE_NAME" >> /etc/iproute2/rt_tables

echo "[3/4] Configuring policy routing..."
ip route add default via "$GATEWAY" dev "$INTERFACE" table "$TABLE_ID" 2>/dev/null || true
ip rule add from "$PRIVATE_IP" lookup "$TABLE_ID" prio 32764 2>/dev/null || true

echo "[4/4] Persisting configuration..."
mkdir -p /etc/network/interfaces.d

cat > "/etc/network/interfaces.d/$INTERFACE" << EOF
# Public IP routing interface - managed by ServerFlow
auto $INTERFACE
iface $INTERFACE inet static
    address $PRIVATE_IP
    netmask 255.255.255.0
    # Policy routing for public IP
    post-up ip route add default via $GATEWAY dev $INTERFACE table $TABLE_ID 2>/dev/null || true
    post-up ip rule add from $PRIVATE_IP lookup $TABLE_ID prio 32764 2>/dev/null || true
    pre-down ip rule del from $PRIVATE_IP lookup $TABLE_ID prio 32764 2>/dev/null || true
    pre-down ip route del default via $GATEWAY dev $INTERFACE table $TABLE_ID 2>/dev/null || true
EOF

# Ensure routing table is defined at boot
if ! grep -q "$TABLE_ID $TABLE_NAME" /etc/iproute2/rt_tables 2>/dev/null; then
    echo "$TABLE_ID $TABLE_NAME" >> /etc/iproute2/rt_tables
fi

echo "Done! Interface $INTERFACE configured with IP $PRIVATE_IP, routing via $GATEWAY (table $TABLE_ID)"
