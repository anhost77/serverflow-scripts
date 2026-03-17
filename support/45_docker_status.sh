#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Docker Containers Status
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
# ==============================================================================

set -e
timeout 10 bash -c '
# Check Docker installation
docker_installed="false"
docker_running="false"
docker_version=""

if command -v docker &>/dev/null; then
    docker_installed="true"
    docker_version=$(docker --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
fi

if systemctl is-active docker >/dev/null 2>&1; then
    docker_running="true"
fi

# Check if user can access docker
docker_accessible="false"
if docker ps &>/dev/null 2>&1; then
    docker_accessible="true"
fi

# Container stats
containers_running=0
containers_stopped=0
containers_total=0
containers=""

if [ "$docker_accessible" = "true" ]; then
    containers_total=$(docker ps -a --format "{{.ID}}" 2>/dev/null | wc -l || echo 0)
    containers_running=$(docker ps --format "{{.ID}}" 2>/dev/null | wc -l || echo 0)
    containers_stopped=$((containers_total - containers_running))
    
    # Get container details
    containers=$(docker ps -a --format "{{json .}}" 2>/dev/null | head -20 | while read -r line; do
        echo "$line"
    done | paste -sd "," - | tr -d "\n")
fi

# Docker Compose projects
compose_projects=""
if [ "$docker_accessible" = "true" ] && command -v docker-compose &>/dev/null || docker compose version &>/dev/null 2>&1; then
    # Find docker-compose files
    compose_files=$(find /var/www /srv /home /opt -maxdepth 4 -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" 2>/dev/null | head -10)
    
    if [ -n "$compose_files" ]; then
        compose_projects=$(echo "$compose_files" | while read -r f; do
            dir=$(dirname "$f")
            project_name=$(basename "$dir")
            
            # Count services in compose file
            services=$(grep -c "^  [a-zA-Z]" "$f" 2>/dev/null || echo 0)
            
            echo "{\"path\":\"$dir\",\"project\":\"$project_name\",\"services\":$services}"
        done | paste -sd "," - | tr -d "\n")
    fi
fi

# Docker images
images_count=0
images=""
if [ "$docker_accessible" = "true" ]; then
    images_count=$(docker images --format "{{.ID}}" 2>/dev/null | wc -l || echo 0)
    
    # Get top 10 largest images
    images=$(docker images --format "{{json .}}" 2>/dev/null | head -10 | while read -r line; do
        echo "$line"
    done | paste -sd "," - | tr -d "\n")
fi

# Docker networks
networks=""
if [ "$docker_accessible" = "true" ]; then
    networks=$(docker network ls --format "{{json .}}" 2>/dev/null | while read -r line; do
        echo "$line"
    done | paste -sd "," - | tr -d "\n")
fi

# Docker volumes
volumes_count=0
if [ "$docker_accessible" = "true" ]; then
    volumes_count=$(docker volume ls --format "{{.Name}}" 2>/dev/null | wc -l || echo 0)
fi

# Disk usage
disk_usage=""
if [ "$docker_accessible" = "true" ]; then
    disk_usage=$(docker system df 2>/dev/null | tail -n +2 | while read -r line; do
        type=$(echo "$line" | awk "{print \$1}")
        total=$(echo "$line" | awk "{print \$2}")
        active=$(echo "$line" | awk "{print \$3}")
        size=$(echo "$line" | awk "{print \$4}")
        reclaimable=$(echo "$line" | awk "{print \$5}")
        echo "{\"type\":\"$type\",\"total\":\"$total\",\"active\":\"$active\",\"size\":\"$size\",\"reclaimable\":\"$reclaimable\"}"
    done | paste -sd "," - | tr -d "\n")
fi

# Unhealthy containers
unhealthy=""
if [ "$docker_accessible" = "true" ]; then
    unhealthy=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" 2>/dev/null | while read -r name; do
        [ -n "$name" ] && echo "\"$name\""
    done | paste -sd "," - | tr -d "\n")
fi

# Restarting containers
restarting=""
if [ "$docker_accessible" = "true" ]; then
    restarting=$(docker ps --filter "status=restarting" --format "{{.Names}}" 2>/dev/null | while read -r name; do
        [ -n "$name" ] && echo "\"$name\""
    done | paste -sd "," - | tr -d "\n")
fi

cat << EOF
{
  "script": "45_docker_status",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "docker": {
    "installed": $docker_installed,
    "running": $docker_running,
    "accessible": $docker_accessible,
    "version": "$docker_version"
  },
  "containers": {
    "total": $containers_total,
    "running": $containers_running,
    "stopped": $containers_stopped,
    "list": [${containers:-}]
  },
  "images": {
    "count": $images_count,
    "list": [${images:-}]
  },
  "volumes": {
    "count": $volumes_count
  },
  "networks": [${networks:-}],
  "compose_projects": [${compose_projects:-}],
  "disk_usage": [${disk_usage:-}],
  "warnings": {
    "unhealthy": [${unhealthy:-}],
    "restarting": [${restarting:-}]
  }
}
EOF
'
