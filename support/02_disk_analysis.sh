#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Disk Analysis
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Get disk usage for all mountpoints
disk_info=""
while IFS= read -r line; do
    fs=$(echo "$line" | awk "{print \$1}")
    size=$(echo "$line" | awk "{print \$2}")
    used=$(echo "$line" | awk "{print \$3}")
    avail=$(echo "$line" | awk "{print \$4}")
    percent=$(echo "$line" | awk "{print \$5}" | tr -d "%")
    mount=$(echo "$line" | awk "{print \$6}")
    
    if [ -n "$disk_info" ]; then
        disk_info="$disk_info,"
    fi
    disk_info="$disk_info{\"filesystem\":\"$fs\",\"size\":\"$size\",\"used\":\"$used\",\"available\":\"$avail\",\"percent_used\":$percent,\"mount\":\"$mount\"}"
done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2)

# Get inode usage
inode_info=""
while IFS= read -r line; do
    fs=$(echo "$line" | awk "{print \$1}")
    total=$(echo "$line" | awk "{print \$2}")
    used=$(echo "$line" | awk "{print \$3}")
    percent=$(echo "$line" | awk "{print \$5}" | tr -d "%")
    mount=$(echo "$line" | awk "{print \$6}")
    
    if [ -n "$inode_info" ]; then
        inode_info="$inode_info,"
    fi
    inode_info="$inode_info{\"filesystem\":\"$fs\",\"total_inodes\":\"$total\",\"used_inodes\":\"$used\",\"percent_used\":$percent,\"mount\":\"$mount\"}"
done < <(df -i --output=source,itotal,iused,iavail,ipcent,target -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2)

# Top 5 largest directories in /var (common culprit)
large_var=""
if [ -d /var ]; then
    while IFS= read -r line; do
        size=$(echo "$line" | awk "{print \$1}")
        path=$(echo "$line" | awk "{print \$2}")
        if [ -n "$large_var" ]; then
            large_var="$large_var,"
        fi
        large_var="$large_var{\"size\":\"$size\",\"path\":\"$path\"}"
    done < <(du -sh /var/*/ 2>/dev/null | sort -rh | head -5)
fi

# Top 5 largest directories in /home
large_home=""
if [ -d /home ]; then
    while IFS= read -r line; do
        size=$(echo "$line" | awk "{print \$1}")
        path=$(echo "$line" | awk "{print \$2}")
        if [ -n "$large_home" ]; then
            large_home="$large_home,"
        fi
        large_home="$large_home{\"size\":\"$size\",\"path\":\"$path\"}"
    done < <(du -sh /home/*/ 2>/dev/null | sort -rh | head -5)
fi

# Check /tmp usage
tmp_size=$(du -sh /tmp 2>/dev/null | awk "{print \$1}" || echo "0")

# Critical disk check (any > 90%)
critical_disks=""
while IFS= read -r line; do
    percent=$(echo "$line" | awk "{print \$5}" | tr -d "%")
    mount=$(echo "$line" | awk "{print \$6}")
    if [ "$percent" -ge 90 ]; then
        if [ -n "$critical_disks" ]; then
            critical_disks="$critical_disks,"
        fi
        critical_disks="$critical_disks\"$mount ($percent%)\""
    fi
done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2)

# Output JSON
cat << EOF
{
  "script": "02_disk_analysis",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "filesystems": [$disk_info],
  "inodes": [$inode_info],
  "large_directories": {
    "var": [$large_var],
    "home": [$large_home]
  },
  "tmp_usage": "$tmp_size",
  "critical_disks": [$critical_disks],
  "has_critical": $([ -n "$critical_disks" ] && echo "true" || echo "false")
}
EOF
'
