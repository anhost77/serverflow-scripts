#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - File Permissions Check
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check sensitive files permissions
sensitive_files=""

# Critical system files to check
files_to_check=(
    "/etc/passwd:644"
    "/etc/shadow:640"
    "/etc/group:644"
    "/etc/gshadow:640"
    "/etc/ssh/sshd_config:600"
    "/etc/sudoers:440"
    "/root/.ssh/authorized_keys:600"
    "/etc/crontab:644"
)

for item in "${files_to_check[@]}"; do
    file="${item%%:*}"
    expected="${item##*:}"
    
    if [ -f "$file" ]; then
        actual=$(stat -c %a "$file" 2>/dev/null || echo "error")
        owner=$(stat -c %U "$file" 2>/dev/null || echo "error")
        group=$(stat -c %G "$file" 2>/dev/null || echo "error")
        
        status="ok"
        if [ "$actual" != "$expected" ]; then
            # Check if more permissive
            if [ "$actual" -gt "$expected" ] 2>/dev/null; then
                status="warning"
            fi
        fi
        
        sensitive_files="$sensitive_files{\"file\":\"$file\",\"expected\":\"$expected\",\"actual\":\"$actual\",\"owner\":\"$owner\",\"group\":\"$group\",\"status\":\"$status\"},"
    fi
done
sensitive_files=$(echo "$sensitive_files" | sed "s/,$//" | tr -d "\n")

# World-writable directories (excluding expected ones)
world_writable=""
world_writable_count=0
world_writable=$(find /etc /var /home -type d -perm -0002 ! -path "/var/tmp" ! -path "/tmp" 2>/dev/null | head -10 | while read -r dir; do
    owner=$(stat -c %U "$dir" 2>/dev/null || echo "error")
    echo "{\"path\":\"$dir\",\"owner\":\"$owner\"}"
done | paste -sd "," - | tr -d "\n")
world_writable_count=$(find /etc /var /home -type d -perm -0002 ! -path "/var/tmp" ! -path "/tmp" 2>/dev/null | wc -l || echo 0)

# SUID/SGID files (unusual ones)
suid_files=""
suid_count=0
# Common allowed SUID files
allowed_suid="/usr/bin/sudo|/usr/bin/passwd|/usr/bin/chsh|/usr/bin/chfn|/usr/bin/newgrp|/usr/bin/gpasswd|/bin/su|/usr/bin/su|/usr/sbin/unix_chkpwd|/usr/bin/mount|/usr/bin/umount|/usr/bin/pkexec|/usr/bin/crontab"

suid_files=$(find /usr /bin /sbin -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | grep -vE "$allowed_suid" | head -10 | while read -r file; do
    perms=$(stat -c %a "$file" 2>/dev/null || echo "error")
    owner=$(stat -c %U:%G "$file" 2>/dev/null || echo "error")
    echo "{\"file\":\"$file\",\"permissions\":\"$perms\",\"owner\":\"$owner\"}"
done | paste -sd "," - | tr -d "\n")
suid_count=$(find /usr /bin /sbin -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | grep -vE "$allowed_suid" | wc -l || echo 0)

# SSH keys with bad permissions
ssh_issues=""
ssh_dirs=$(find /home /root -maxdepth 2 -type d -name ".ssh" 2>/dev/null)
for ssh_dir in $ssh_dirs; do
    dir_perms=$(stat -c %a "$ssh_dir" 2>/dev/null || echo "999")
    if [ "$dir_perms" != "700" ] && [ "$dir_perms" != "999" ]; then
        ssh_issues="$ssh_issues{\"path\":\"$ssh_dir\",\"issue\":\"directory permissions $dir_perms (should be 700)\"},"
    fi
    
    # Check authorized_keys
    if [ -f "$ssh_dir/authorized_keys" ]; then
        ak_perms=$(stat -c %a "$ssh_dir/authorized_keys" 2>/dev/null || echo "999")
        if [ "$ak_perms" != "600" ] && [ "$ak_perms" != "644" ] && [ "$ak_perms" != "999" ]; then
            ssh_issues="$ssh_issues{\"path\":\"$ssh_dir/authorized_keys\",\"issue\":\"permissions $ak_perms (should be 600 or 644)\"},"
        fi
    fi
    
    # Check private keys
    for key in "$ssh_dir"/id_*; do
        if [ -f "$key" ] && ! echo "$key" | grep -q "\.pub$"; then
            key_perms=$(stat -c %a "$key" 2>/dev/null || echo "999")
            if [ "$key_perms" != "600" ] && [ "$key_perms" != "999" ]; then
                ssh_issues="$ssh_issues{\"path\":\"$key\",\"issue\":\"private key permissions $key_perms (should be 600)\"},"
            fi
        fi
    done
done
ssh_issues=$(echo "$ssh_issues" | sed "s/,$//" | tr -d "\n")

# Web root permissions
web_root_issues=""
web_roots=("/var/www" "/srv/www" "/var/www/html")
for root in "${web_roots[@]}"; do
    if [ -d "$root" ]; then
        owner=$(stat -c %U:%G "$root" 2>/dev/null || echo "error")
        perms=$(stat -c %a "$root" 2>/dev/null || echo "error")
        
        # Check for files writable by others
        others_writable=$(find "$root" -type f -perm -0002 2>/dev/null | wc -l || echo 0)
        
        if [ "$others_writable" -gt 0 ]; then
            web_root_issues="$web_root_issues{\"path\":\"$root\",\"owner\":\"$owner\",\"permissions\":\"$perms\",\"world_writable_files\":$others_writable},"
        fi
    fi
done
web_root_issues=$(echo "$web_root_issues" | sed "s/,$//" | tr -d "\n")

# /tmp and /var/tmp sticky bit check
tmp_sticky="ok"
if [ -d /tmp ]; then
    tmp_perms=$(stat -c %a /tmp 2>/dev/null || echo "")
    if ! echo "$tmp_perms" | grep -q "^1"; then
        tmp_sticky="missing"
    fi
fi

cat << EOF
{
  "script": "53_file_permissions",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "sensitive_files": [${sensitive_files:-}],
  "world_writable": {
    "count": $world_writable_count,
    "directories": [${world_writable:-}]
  },
  "suid_sgid": {
    "unusual_count": $suid_count,
    "files": [${suid_files:-}]
  },
  "ssh_permission_issues": [${ssh_issues:-}],
  "web_root_issues": [${web_root_issues:-}],
  "tmp_sticky_bit": "$tmp_sticky"
}
EOF
'
