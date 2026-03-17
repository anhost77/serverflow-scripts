#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Network Interfaces Configuration
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Get all network interfaces
interfaces=""
interface_count=0

for iface in /sys/class/net/*; do
    [ -d "$iface" ] || continue
    name=$(basename "$iface")
    
    # Skip loopback
    [ "$name" = "lo" ] && continue
    
    # Get interface state
    state=$(cat "$iface/operstate" 2>/dev/null || echo "unknown")
    
    # Get MAC address
    mac=$(cat "$iface/address" 2>/dev/null || echo "")
    
    # Get MTU
    mtu=$(cat "$iface/mtu" 2>/dev/null || echo "")
    
    # Get speed (if applicable)
    speed=$(cat "$iface/speed" 2>/dev/null || echo "")
    
    # Get IP addresses
    ipv4=$(ip -4 addr show "$name" 2>/dev/null | grep "inet " | awk "{print \$2}" | paste -sd "," - || echo "")
    ipv6=$(ip -6 addr show "$name" 2>/dev/null | grep "inet6 " | grep -v "fe80:" | awk "{print \$2}" | paste -sd "," - || echo "")
    
    # Get gateway (if this is the default route interface)
    gateway=""
    default_route=$(ip route 2>/dev/null | grep "default.*$name" | awk "{print \$3}" || echo "")
    gateway="$default_route"
    
    # Get driver
    driver=$(basename "$(readlink "$iface/device/driver" 2>/dev/null)" 2>/dev/null || echo "")
    
    # Get RX/TX stats
    rx_bytes=$(cat "$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx_bytes=$(cat "$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
    rx_packets=$(cat "$iface/statistics/rx_packets" 2>/dev/null || echo 0)
    tx_packets=$(cat "$iface/statistics/tx_packets" 2>/dev/null || echo 0)
    rx_errors=$(cat "$iface/statistics/rx_errors" 2>/dev/null || echo 0)
    tx_errors=$(cat "$iface/statistics/tx_errors" 2>/dev/null || echo 0)
    rx_dropped=$(cat "$iface/statistics/rx_dropped" 2>/dev/null || echo 0)
    tx_dropped=$(cat "$iface/statistics/tx_dropped" 2>/dev/null || echo 0)
    
    # Convert bytes to human readable
    rx_human=$(numfmt --to=iec-i --suffix=B "$rx_bytes" 2>/dev/null || echo "${rx_bytes}B")
    tx_human=$(numfmt --to=iec-i --suffix=B "$tx_bytes" 2>/dev/null || echo "${tx_bytes}B")
    
    # Check if virtual
    virtual="false"
    if [ -d "$iface/device" ]; then
        if readlink -f "$iface/device" 2>/dev/null | grep -q "virtual"; then
            virtual="true"
        fi
    else
        # No device directory usually means virtual
        virtual="true"
    fi
    
    interfaces="$interfaces{\"name\":\"$name\",\"state\":\"$state\",\"mac\":\"$mac\",\"mtu\":$mtu,\"speed\":\"${speed:-unknown}\",\"driver\":\"$driver\",\"virtual\":$virtual,\"ipv4\":\"$ipv4\",\"ipv6\":\"$ipv6\",\"gateway\":\"$gateway\",\"stats\":{\"rx_bytes\":$rx_bytes,\"tx_bytes\":$tx_bytes,\"rx_human\":\"$rx_human\",\"tx_human\":\"$tx_human\",\"rx_packets\":$rx_packets,\"tx_packets\":$tx_packets,\"rx_errors\":$rx_errors,\"tx_errors\":$tx_errors,\"rx_dropped\":$rx_dropped,\"tx_dropped\":$tx_dropped}},"
    
    interface_count=$((interface_count + 1))
done
interfaces=$(echo "$interfaces" | sed "s/,$//" | tr -d "\n")

# Default route
default_route=""
default_route_info=$(ip route 2>/dev/null | grep "^default" | head -1)
if [ -n "$default_route_info" ]; then
    gw=$(echo "$default_route_info" | awk "{print \$3}")
    dev=$(echo "$default_route_info" | awk "{print \$5}")
    default_route="{\"gateway\":\"$gw\",\"device\":\"$dev\"}"
fi

# DNS servers
dns_servers=""
dns_servers=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk "{print \$2}" | while read -r ns; do
    echo "\"$ns\""
done | paste -sd "," - | tr -d "\n")

# Hostname info
hostname=$(hostname 2>/dev/null || echo "unknown")
fqdn=$(hostname -f 2>/dev/null || echo "unknown")

# Check for bonding/bridging
bonds=""
if [ -d /proc/net/bonding ]; then
    bonds=$(ls /proc/net/bonding 2>/dev/null | while read -r bond; do
        mode=$(grep "Bonding Mode:" "/proc/net/bonding/$bond" 2>/dev/null | cut -d: -f2 | xargs || echo "")
        slaves=$(grep "Slave Interface:" "/proc/net/bonding/$bond" 2>/dev/null | cut -d: -f2 | xargs | tr " " "," || echo "")
        echo "{\"name\":\"$bond\",\"mode\":\"$mode\",\"slaves\":\"$slaves\"}"
    done | paste -sd "," - | tr -d "\n")
fi

bridges=""
if command -v brctl &>/dev/null; then
    bridges=$(brctl show 2>/dev/null | tail -n +2 | while read -r line; do
        br=$(echo "$line" | awk "{print \$1}")
        [ -z "$br" ] && continue
        interfaces_br=$(echo "$line" | awk "{print \$4}")
        echo "{\"name\":\"$br\",\"interfaces\":\"$interfaces_br\"}"
    done | paste -sd "," - | tr -d "\n")
fi

# Check connectivity
ping_test=""
test_hosts=("8.8.8.8" "1.1.1.1")
for host in "${test_hosts[@]}"; do
    result=$(ping -c 1 -W 2 "$host" 2>/dev/null && echo "ok" || echo "failed")
    ping_test="$ping_test{\"host\":\"$host\",\"status\":\"$result\"},"
done
ping_test=$(echo "$ping_test" | sed "s/,$//" | tr -d "\n")

# Network manager status
network_manager="none"
if systemctl is-active NetworkManager >/dev/null 2>&1; then
    network_manager="NetworkManager"
elif systemctl is-active systemd-networkd >/dev/null 2>&1; then
    network_manager="systemd-networkd"
elif systemctl is-active networking >/dev/null 2>&1; then
    network_manager="ifupdown"
fi

cat << EOF
{
  "script": "71_network_interfaces",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "hostname": "$hostname",
  "fqdn": "$fqdn",
  "network_manager": "$network_manager",
  "interface_count": $interface_count,
  "interfaces": [${interfaces:-}],
  "default_route": ${default_route:-null},
  "dns_servers": [${dns_servers:-}],
  "bonds": [${bonds:-}],
  "bridges": [${bridges:-}],
  "connectivity_tests": [${ping_test:-}]
}
EOF
'
