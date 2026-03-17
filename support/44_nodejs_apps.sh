#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Node.js Applications Status
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check Node.js installation
node_installed="false"
node_version=""
npm_version=""

if command -v node &>/dev/null; then
    node_installed="true"
    node_version=$(node --version 2>/dev/null || echo "unknown")
fi

if command -v npm &>/dev/null; then
    npm_version=$(npm --version 2>/dev/null || echo "unknown")
fi

# Check PM2
pm2_installed="false"
pm2_version=""
pm2_apps=""

if command -v pm2 &>/dev/null; then
    pm2_installed="true"
    pm2_version=$(pm2 --version 2>/dev/null || echo "unknown")
    
    # Get PM2 process list
    pm2_json=$(pm2 jlist 2>/dev/null || echo "[]")
    
    if [ "$pm2_json" != "[]" ] && [ -n "$pm2_json" ]; then
        pm2_apps=$(echo "$pm2_json" | head -c 4000 | tr -d "\n")
    fi
fi

# Find running node processes (not via PM2)
node_processes=""
node_proc_count=0
if [ "$node_installed" = "true" ]; then
    node_processes=$(ps aux | grep "[n]ode " | grep -v "pm2" | head -10 | while read -r line; do
        pid=$(echo "$line" | awk "{print \$2}")
        user=$(echo "$line" | awk "{print \$1}")
        cpu=$(echo "$line" | awk "{print \$3}")
        mem=$(echo "$line" | awk "{print \$4}")
        cmd=$(echo "$line" | awk "{for(i=11;i<=NF;i++) printf \"%s \", \$i}" | head -c 100)
        
        # Get working directory
        cwd=$(readlink -f /proc/$pid/cwd 2>/dev/null || echo "unknown")
        
        echo "{\"pid\":$pid,\"user\":\"$user\",\"cpu\":$cpu,\"mem\":$mem,\"cwd\":\"$cwd\",\"cmd\":\"$(echo "$cmd" | sed "s/\"/\\\\\"/g")\"}"
    done | paste -sd "," - | tr -d "\n")
    
    node_proc_count=$(ps aux | grep "[n]ode " | grep -v "pm2" | wc -l || echo 0)
fi

# Check for NVM
nvm_installed="false"
nvm_versions=""
if [ -d "$HOME/.nvm" ] || [ -d "/root/.nvm" ]; then
    nvm_installed="true"
    nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    [ ! -d "$nvm_dir" ] && nvm_dir="/root/.nvm"
    if [ -d "$nvm_dir/versions/node" ]; then
        nvm_versions=$(ls -1 "$nvm_dir/versions/node" 2>/dev/null | while read -r v; do
            echo "\"$v\""
        done | paste -sd "," - | tr -d "\n")
    fi
fi

# Check for Yarn
yarn_installed="false"
yarn_version=""
if command -v yarn &>/dev/null; then
    yarn_installed="true"
    yarn_version=$(yarn --version 2>/dev/null || echo "unknown")
fi

# Check for pnpm
pnpm_installed="false"
pnpm_version=""
if command -v pnpm &>/dev/null; then
    pnpm_installed="true"
    pnpm_version=$(pnpm --version 2>/dev/null || echo "unknown")
fi

# Find package.json files (potential Node.js apps)
nodejs_apps=""
apps_found=$(find /var/www /srv /home -maxdepth 4 -name "package.json" -type f 2>/dev/null | head -10)
if [ -n "$apps_found" ]; then
    nodejs_apps=$(echo "$apps_found" | while read -r pkg; do
        dir=$(dirname "$pkg")
        name=$(grep "\"name\"" "$pkg" 2>/dev/null | head -1 | grep -oP "\"name\":\s*\"\\K[^\"]+(?=\")" || basename "$dir")
        version=$(grep "\"version\"" "$pkg" 2>/dev/null | head -1 | grep -oP "\"version\":\s*\"\\K[^\"]+(?=\")" || echo "")
        
        # Check if has node_modules
        has_modules="false"
        [ -d "$dir/node_modules" ] && has_modules="true"
        
        # Check for common frameworks
        framework="unknown"
        if grep -q "\"next\"" "$pkg" 2>/dev/null; then
            framework="nextjs"
        elif grep -q "\"express\"" "$pkg" 2>/dev/null; then
            framework="express"
        elif grep -q "\"@nestjs/core\"" "$pkg" 2>/dev/null; then
            framework="nestjs"
        elif grep -q "\"nuxt\"" "$pkg" 2>/dev/null; then
            framework="nuxt"
        elif grep -q "\"react\"" "$pkg" 2>/dev/null; then
            framework="react"
        elif grep -q "\"vue\"" "$pkg" 2>/dev/null; then
            framework="vue"
        fi
        
        echo "{\"path\":\"$dir\",\"name\":\"$(echo "$name" | sed "s/\"/\\\\\"/g")\",\"version\":\"$version\",\"framework\":\"$framework\",\"has_node_modules\":$has_modules}"
    done | paste -sd "," - | tr -d "\n")
fi

# PM2 summary
pm2_online=0
pm2_errored=0
pm2_stopped=0
if [ -n "$pm2_apps" ] && [ "$pm2_apps" != "[]" ]; then
    pm2_online=$(echo "$pm2_apps" | grep -o "\"status\":\"online\"" | wc -l || echo 0)
    pm2_errored=$(echo "$pm2_apps" | grep -o "\"status\":\"errored\"" | wc -l || echo 0)
    pm2_stopped=$(echo "$pm2_apps" | grep -o "\"status\":\"stopped\"" | wc -l || echo 0)
fi

cat << EOF
{
  "script": "44_nodejs_apps",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "node": {
    "installed": $node_installed,
    "version": "$node_version",
    "npm_version": "$npm_version"
  },
  "package_managers": {
    "yarn": {"installed": $yarn_installed, "version": "$yarn_version"},
    "pnpm": {"installed": $pnpm_installed, "version": "$pnpm_version"}
  },
  "nvm": {
    "installed": $nvm_installed,
    "versions": [${nvm_versions:-}]
  },
  "pm2": {
    "installed": $pm2_installed,
    "version": "$pm2_version",
    "summary": {"online": $pm2_online, "errored": $pm2_errored, "stopped": $pm2_stopped},
    "apps": ${pm2_apps:-[]}
  },
  "standalone_processes": {
    "count": $node_proc_count,
    "processes": [${node_processes:-}]
  },
  "detected_apps": [${nodejs_apps:-}]
}
EOF
'
