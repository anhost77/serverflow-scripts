#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Firewall Rules Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Detect firewall type
firewall_type="none"
firewall_active="false"

# Check for various firewall implementations
if systemctl is-active firewalld >/dev/null 2>&1; then
    firewall_type="firewalld"
    firewall_active="true"
elif systemctl is-active ufw >/dev/null 2>&1; then
    firewall_type="ufw"
    firewall_active="true"
elif iptables -L -n >/dev/null 2>&1; then
    # Check if iptables has rules (beyond default empty chains)
    rules_count=$(iptables -L -n 2>/dev/null | grep -cv "^Chain\|^target\|^$" || echo 0)
    if [ "$rules_count" -gt 0 ]; then
        firewall_type="iptables"
        firewall_active="true"
    fi
fi

# Check for nftables
nft_active="false"
if command -v nft &>/dev/null && nft list tables 2>/dev/null | grep -q .; then
    nft_active="true"
    if [ "$firewall_type" = "none" ]; then
        firewall_type="nftables"
        firewall_active="true"
    fi
fi

# UFW status
ufw_rules=""
ufw_status="inactive"
if [ "$firewall_type" = "ufw" ]; then
    ufw_status=$(ufw status 2>/dev/null | head -1 | awk "{print \$2}" || echo "unknown")
    ufw_rules=$(ufw status numbered 2>/dev/null | grep "^\[" | while read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-100)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# Firewalld zones and rules
firewalld_info=""
if [ "$firewall_type" = "firewalld" ]; then
    default_zone=$(firewall-cmd --get-default-zone 2>/dev/null || echo "")
    active_zones=$(firewall-cmd --get-active-zones 2>/dev/null | grep -v "^\s" | paste -sd "," - || echo "")
    
    # Get services in default zone
    services=$(firewall-cmd --zone="$default_zone" --list-services 2>/dev/null || echo "")
    ports=$(firewall-cmd --zone="$default_zone" --list-ports 2>/dev/null || echo "")
    
    firewalld_info="{\"default_zone\":\"$default_zone\",\"active_zones\":\"$active_zones\",\"services\":\"$services\",\"ports\":\"$ports\"}"
fi

# iptables rules (summary)
iptables_rules=""
iptables_summary=""
if command -v iptables &>/dev/null; then
    # Count rules per chain
    input_rules=$(iptables -L INPUT -n 2>/dev/null | grep -cv "^Chain\|^target\|^$" || echo 0)
    output_rules=$(iptables -L OUTPUT -n 2>/dev/null | grep -cv "^Chain\|^target\|^$" || echo 0)
    forward_rules=$(iptables -L FORWARD -n 2>/dev/null | grep -cv "^Chain\|^target\|^$" || echo 0)
    
    # Default policies
    input_policy=$(iptables -L INPUT -n 2>/dev/null | head -1 | grep -oP "policy \K[A-Z]+" || echo "unknown")
    output_policy=$(iptables -L OUTPUT -n 2>/dev/null | head -1 | grep -oP "policy \K[A-Z]+" || echo "unknown")
    forward_policy=$(iptables -L FORWARD -n 2>/dev/null | head -1 | grep -oP "policy \K[A-Z]+" || echo "unknown")
    
    iptables_summary="{\"input\":{\"policy\":\"$input_policy\",\"rules\":$input_rules},\"output\":{\"policy\":\"$output_policy\",\"rules\":$output_rules},\"forward\":{\"policy\":\"$forward_policy\",\"rules\":$forward_rules}}"
    
    # Get first 20 INPUT rules
    iptables_rules=$(iptables -L INPUT -n --line-numbers 2>/dev/null | tail -n +3 | head -15 | while read -r line; do
        escaped=$(echo "$line" | sed "s/\"/\\\\\"/g" | cut -c1-100)
        echo "\"$escaped\""
    done | paste -sd "," - | tr -d "\n")
fi

# nftables rules
nft_rules=""
if [ "$nft_active" = "true" ]; then
    nft_tables=$(nft list tables 2>/dev/null | while read -r line; do
        echo "\"$line\""
    done | paste -sd "," - | tr -d "\n")
    
    # Get rule count
    nft_rule_count=$(nft list ruleset 2>/dev/null | grep -c "^\s*\(accept\|drop\|reject\)" || echo 0)
    nft_rules="{\"tables\":[${nft_tables:-}],\"rule_count\":$nft_rule_count}"
fi

# Check for fail2ban integration
fail2ban_chains="false"
if iptables -L -n 2>/dev/null | grep -q "f2b-\|fail2ban"; then
    fail2ban_chains="true"
fi

# NAT rules count
nat_rules=0
if command -v iptables &>/dev/null; then
    nat_rules=$(iptables -t nat -L -n 2>/dev/null | grep -cv "^Chain\|^target\|^$" || echo 0)
fi

# Check allowed incoming ports (from various sources)
allowed_ports=""
# From iptables ACCEPT rules
if command -v iptables &>/dev/null; then
    allowed_ports=$(iptables -L INPUT -n 2>/dev/null | grep "ACCEPT" | grep -oP "dpt:\K[0-9]+" | sort -u | while read -r port; do
        echo "$port"
    done | paste -sd "," - || echo "")
fi

# Security assessment
security_level="unknown"
if [ "$firewall_active" = "false" ]; then
    security_level="none"
elif [ "$input_policy" = "DROP" ] || [ "$input_policy" = "REJECT" ]; then
    security_level="strict"
elif [ "$input_policy" = "ACCEPT" ]; then
    security_level="permissive"
fi

cat << EOF
{
  "script": "72_firewall_rules",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "firewall": {
    "type": "$firewall_type",
    "active": $firewall_active,
    "nftables_present": $nft_active,
    "security_level": "$security_level"
  },
  "ufw": {
    "status": "$ufw_status",
    "rules": [${ufw_rules:-}]
  },
  "firewalld": ${firewalld_info:-null},
  "iptables": {
    "summary": ${iptables_summary:-null},
    "input_rules": [${iptables_rules:-}],
    "nat_rules_count": $nat_rules,
    "fail2ban_integrated": $fail2ban_chains
  },
  "nftables": ${nft_rules:-null},
  "allowed_incoming_ports": "$allowed_ports"
}
EOF
'
