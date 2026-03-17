#!/bin/bash
# ==============================================================================
# Test all support scripts on a VM via Proxmox qemu-guest-agent
# Usage: ./test-all-scripts.sh <pve_host> <pve_node> <vmid>
# Example: ./test-all-scripts.sh 10.1.0.2 pve03 1004
# ==============================================================================

set -e

PVE_HOST="${1:-10.1.0.2}"
PVE_NODE="${2:-pve03}"
VMID="${3:-1004}"
SCRIPT_DIR="$(dirname "$0")/support"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Testing all scripts on VM $VMID ($PVE_NODE @ $PVE_HOST)"
echo "=========================================="
echo ""

# Get API token from env or use default test token
PVE_TOKEN="${PVE_TOKEN:-root@pam!serverflow=179b1401-e1b4-4a25-b42a-e63b5a5621c3}"

total=0
passed=0
failed=0
failed_scripts=""

for script in "$SCRIPT_DIR"/*.sh; do
    script_name=$(basename "$script")
    total=$((total + 1))
    
    printf "%-35s" "$script_name"
    
    # Upload script
    content=$(cat "$script")
    ssh root@$PVE_HOST "curl -sk -X POST 'https://localhost:8006/api2/json/nodes/$PVE_NODE/qemu/$VMID/agent/file-write' \
        -H 'Authorization: PVEAPIToken=$PVE_TOKEN' \
        -d 'file=/tmp/sf-test-script.sh' \
        --data-urlencode 'content=$content'" > /dev/null 2>&1
    
    # Make executable
    pid=$(ssh root@$PVE_HOST "curl -sk -X POST 'https://localhost:8006/api2/json/nodes/$PVE_NODE/qemu/$VMID/agent/exec' \
        -H 'Authorization: PVEAPIToken=$PVE_TOKEN' \
        -d 'command=chmod' -d 'command=755' -d 'command=/tmp/sf-test-script.sh'" 2>/dev/null | grep -oP '"pid":\K[0-9]+' || echo "")
    
    if [ -z "$pid" ]; then
        echo -e "${RED}FAIL${NC} (chmod failed)"
        failed=$((failed + 1))
        failed_scripts="$failed_scripts $script_name"
        continue
    fi
    sleep 1
    
    # Execute script
    start_time=$(date +%s%3N)
    pid=$(ssh root@$PVE_HOST "curl -sk -X POST 'https://localhost:8006/api2/json/nodes/$PVE_NODE/qemu/$VMID/agent/exec' \
        -H 'Authorization: PVEAPIToken=$PVE_TOKEN' \
        -d 'command=/tmp/sf-test-script.sh'" 2>/dev/null | grep -oP '"pid":\K[0-9]+' || echo "")
    
    if [ -z "$pid" ]; then
        echo -e "${RED}FAIL${NC} (exec failed)"
        failed=$((failed + 1))
        failed_scripts="$failed_scripts $script_name"
        continue
    fi
    
    # Wait for completion (max 15s)
    for i in {1..30}; do
        sleep 0.5
        result=$(ssh root@$PVE_HOST "curl -sk 'https://localhost:8006/api2/json/nodes/$PVE_NODE/qemu/$VMID/agent/exec-status?pid=$pid' \
            -H 'Authorization: PVEAPIToken=$PVE_TOKEN'" 2>/dev/null)
        
        exited=$(echo "$result" | grep -oP '"exited":\K[0-9]+' || echo "0")
        if [ "$exited" = "1" ]; then
            break
        fi
    done
    
    end_time=$(date +%s%3N)
    duration=$((end_time - start_time))
    
    if [ "$exited" != "1" ]; then
        echo -e "${YELLOW}TIMEOUT${NC} (>${duration}ms)"
        failed=$((failed + 1))
        failed_scripts="$failed_scripts $script_name"
        continue
    fi
    
    # Check exit code
    exitcode=$(echo "$result" | grep -oP '"exitcode":\K[0-9]+' || echo "1")
    output=$(echo "$result" | grep -oP '"out-data":"\K[^"]+' || echo "")
    
    if [ "$exitcode" != "0" ]; then
        echo -e "${RED}FAIL${NC} (exit=$exitcode, ${duration}ms)"
        failed=$((failed + 1))
        failed_scripts="$failed_scripts $script_name"
        continue
    fi
    
    # Validate JSON
    # Decode and check if it's valid JSON
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        echo -e "${GREEN}OK${NC} (${duration}ms, valid JSON)"
        passed=$((passed + 1))
    else
        # Check if it at least starts with {
        if echo "$output" | grep -q '^{'; then
            echo -e "${YELLOW}WARN${NC} (${duration}ms, invalid JSON)"
            failed=$((failed + 1))
            failed_scripts="$failed_scripts $script_name"
        else
            echo -e "${RED}FAIL${NC} (${duration}ms, no JSON output)"
            failed=$((failed + 1))
            failed_scripts="$failed_scripts $script_name"
        fi
    fi
done

echo ""
echo "=========================================="
echo "Results: $passed/$total passed, $failed failed"
echo "=========================================="

if [ -n "$failed_scripts" ]; then
    echo ""
    echo "Failed scripts:"
    for s in $failed_scripts; do
        echo "  - $s"
    done
fi

# Cleanup
ssh root@$PVE_HOST "curl -sk -X POST 'https://localhost:8006/api2/json/nodes/$PVE_NODE/qemu/$VMID/agent/exec' \
    -H 'Authorization: PVEAPIToken=$PVE_TOKEN' \
    -d 'command=rm' -d 'command=-f' -d 'command=/tmp/sf-test-script.sh'" > /dev/null 2>&1 || true

exit $failed
