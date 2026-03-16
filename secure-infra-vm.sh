#!/bin/bash
# secure-infra-vm.sh
# Sécurisation des VMs infra ServerFlow
#
# Usage: secure-infra-vm.sh <password> [home_ip] [username]
# Example: secure-infra-vm.sh "MySecurePass123" "YOUR_HOME_IP" "admin"

set -e

PASSWORD="$1"
HOME_IP="${2:-}"
USERNAME="${3:-}"

if [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <password> [home_ip] [username]"
    exit 1
fi

echo "=== ServerFlow Infrastructure VM Security Hardening ==="

# 1. Change passwords
echo "[1/6] Setting passwords..."
echo "root:${PASSWORD}" | chpasswd
if [ -n "$USERNAME" ] && id "$USERNAME" &>/dev/null; then
    echo "${USERNAME}:${PASSWORD}" | chpasswd
    echo "  ✓ Password set for root and ${USERNAME}"
else
    echo "  ✓ Password set for root"
fi

# 2. Install security packages
echo "[2/6] Installing security packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq fail2ban ufw > /dev/null 2>&1
echo "  ✓ fail2ban and ufw installed"

# 3. Configure fail2ban
echo "[3/6] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 10.0.0.0/8

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "  ✓ fail2ban configured (3 attempts, 24h ban)"

# 4. Configure UFW firewall
echo "[4/6] Configuring UFW firewall..."
ufw --force reset > /dev/null 2>&1

# Allow SSH from infra networks and home IP
ufw allow from 10.0.0.0/8 to any port 22 comment "SSH from infra"
ufw allow from ${HOME_IP} to any port 22 comment "SSH from home"

# Allow all traffic from infra (for services)
ufw allow from 10.0.0.0/8 comment "Infra network"

# Allow established connections
ufw default deny incoming
ufw default allow outgoing

# Enable UFW
echo "y" | ufw enable > /dev/null 2>&1
echo "  ✓ UFW configured (SSH: 10.0.0.0/8 + ${HOME_IP})"

# 5. Harden SSH config
echo "[5/6] Hardening SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Apply SSH hardening
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/^#*LoginGraceTime.*/LoginGraceTime 30/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config

# Restrict SSH to specific addresses (via Match block)
if [ -n "$USERNAME" ] && ! grep -q "# ServerFlow SSH Restrictions" /etc/ssh/sshd_config; then
    cat >> /etc/ssh/sshd_config << EOF

# ServerFlow SSH Restrictions
AllowUsers ${USERNAME} root
EOF
fi

systemctl restart sshd
echo "  ✓ SSH hardened (root key-only, 3 max attempts)"

# 6. Install unattended-upgrades for auto security updates
echo "[6/6] Configuring automatic security updates..."
apt-get install -y -qq unattended-upgrades > /dev/null 2>&1
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
echo "  ✓ Automatic security updates enabled"

echo ""
echo "=== Security Hardening Complete ==="
echo "  • Passwords: set for root${USERNAME:+ and $USERNAME}"
echo "  • fail2ban: enabled (3 attempts = 24h ban)"
echo "  • UFW: SSH from 10.0.0.0/8${HOME_IP:+ + $HOME_IP}"
echo "  • SSH: root key-only, max 3 attempts"
echo "  • Auto-updates: security patches enabled"
echo ""
echo "⚠️  Test SSH access before closing current session!"
