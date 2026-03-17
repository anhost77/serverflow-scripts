#!/bin/bash
# ==============================================================================
# ServerFlow Support Script - Service Discovery
# READ-ONLY - No write operations
# Timeout: 10s max
# Output: JSON
#
# This script discovers what services, runtimes, and applications are installed
# on the server. It's the first script to run to understand the server profile.
# ==============================================================================

set -e
timeout 10 bash -c '

# Helper function to check if command exists
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Helper function to check if service is active
service_active() {
    systemctl is-active "$1" >/dev/null 2>&1
}

# ============================================
# DETECT WEB SERVERS
# ============================================
web_servers="[]"
web_list=""

if cmd_exists nginx; then
    nginx_running=$(service_active nginx && echo "true" || echo "false")
    nginx_version=$(nginx -v 2>&1 | grep -oP "nginx/\K[0-9.]+" || echo "unknown")
    web_list="${web_list}{\"name\":\"nginx\",\"running\":${nginx_running},\"version\":\"${nginx_version}\"},"
fi

if cmd_exists apache2 || cmd_exists httpd; then
    apache_cmd=$(cmd_exists apache2 && echo "apache2" || echo "httpd")
    apache_running=$(service_active apache2 || service_active httpd && echo "true" || echo "false")
    apache_version=$($apache_cmd -v 2>/dev/null | head -1 | grep -oP "Apache/\K[0-9.]+" || echo "unknown")
    web_list="${web_list}{\"name\":\"apache\",\"running\":${apache_running},\"version\":\"${apache_version}\"},"
fi

if cmd_exists caddy; then
    caddy_running=$(service_active caddy && echo "true" || echo "false")
    caddy_version=$(caddy version 2>/dev/null | head -1 || echo "unknown")
    web_list="${web_list}{\"name\":\"caddy\",\"running\":${caddy_running},\"version\":\"${caddy_version}\"},"
fi

# Remove trailing comma and wrap in array
web_list="${web_list%,}"
[ -n "$web_list" ] && web_servers="[${web_list}]"

# ============================================
# DETECT DATABASES
# ============================================
databases="[]"
db_list=""

if cmd_exists mysql || cmd_exists mariadb; then
    mysql_running=$(service_active mysql || service_active mariadb || service_active mysqld && echo "true" || echo "false")
    if cmd_exists mysql; then
        mysql_version=$(mysql --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "unknown")
        mysql_type=$(mysql --version 2>/dev/null | grep -qi mariadb && echo "mariadb" || echo "mysql")
    else
        mysql_version="unknown"
        mysql_type="mysql"
    fi
    db_list="${db_list}{\"name\":\"${mysql_type}\",\"running\":${mysql_running},\"version\":\"${mysql_version}\"},"
fi

if cmd_exists psql; then
    pg_running=$(service_active postgresql && echo "true" || echo "false")
    pg_version=$(psql --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+" | head -1 || echo "unknown")
    db_list="${db_list}{\"name\":\"postgresql\",\"running\":${pg_running},\"version\":\"${pg_version}\"},"
fi

if cmd_exists mongod || cmd_exists mongo; then
    mongo_running=$(service_active mongod || service_active mongodb && echo "true" || echo "false")
    mongo_version=$(mongod --version 2>/dev/null | head -1 | grep -oP "v[0-9.]+" || echo "unknown")
    db_list="${db_list}{\"name\":\"mongodb\",\"running\":${mongo_running},\"version\":\"${mongo_version}\"},"
fi

if [ -f /var/lib/sqlite3 ] || cmd_exists sqlite3; then
    db_list="${db_list}{\"name\":\"sqlite\",\"running\":true,\"version\":\"$(sqlite3 --version 2>/dev/null | cut -d\" \" -f1 || echo \"unknown\")\"},"
fi

db_list="${db_list%,}"
[ -n "$db_list" ] && databases="[${db_list}]"

# ============================================
# DETECT CACHE SERVICES
# ============================================
caches="[]"
cache_list=""

if cmd_exists redis-cli; then
    redis_running=$(service_active redis || service_active redis-server && echo "true" || echo "false")
    redis_version=$(redis-cli --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
    cache_list="${cache_list}{\"name\":\"redis\",\"running\":${redis_running},\"version\":\"${redis_version}\"},"
fi

if cmd_exists memcached; then
    memcached_running=$(service_active memcached && echo "true" || echo "false")
    memcached_version=$(memcached -h 2>&1 | head -1 | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
    cache_list="${cache_list}{\"name\":\"memcached\",\"running\":${memcached_running},\"version\":\"${memcached_version}\"},"
fi

cache_list="${cache_list%,}"
[ -n "$cache_list" ] && caches="[${cache_list}]"

# ============================================
# DETECT RUNTIMES
# ============================================
runtimes="[]"
rt_list=""

if cmd_exists php; then
    php_version=$(php -v 2>/dev/null | head -1 | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
    php_fpm_running=$(service_active "php*-fpm" 2>/dev/null || pgrep -x "php-fpm" >/dev/null 2>&1 && echo "true" || echo "false")
    rt_list="${rt_list}{\"name\":\"php\",\"version\":\"${php_version}\",\"fpm_running\":${php_fpm_running}},"
fi

if cmd_exists node; then
    node_version=$(node --version 2>/dev/null | tr -d "v" || echo "unknown")
    rt_list="${rt_list}{\"name\":\"nodejs\",\"version\":\"${node_version}\"},"
fi

if cmd_exists python3 || cmd_exists python; then
    python_cmd=$(cmd_exists python3 && echo "python3" || echo "python")
    python_version=$($python_cmd --version 2>&1 | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
    rt_list="${rt_list}{\"name\":\"python\",\"version\":\"${python_version}\"},"
fi

if cmd_exists ruby; then
    ruby_version=$(ruby --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
    rt_list="${rt_list}{\"name\":\"ruby\",\"version\":\"${ruby_version}\"},"
fi

if cmd_exists java; then
    java_version=$(java -version 2>&1 | head -1 | grep -oP "\"[0-9._]+\"" | tr -d "\"" || echo "unknown")
    rt_list="${rt_list}{\"name\":\"java\",\"version\":\"${java_version}\"},"
fi

if cmd_exists go; then
    go_version=$(go version 2>/dev/null | grep -oP "go[0-9.]+" | tr -d "go" || echo "unknown")
    rt_list="${rt_list}{\"name\":\"golang\",\"version\":\"${go_version}\"},"
fi

rt_list="${rt_list%,}"
[ -n "$rt_list" ] && runtimes="[${rt_list}]"

# ============================================
# DETECT CONTAINERS
# ============================================
containers="[]"
cont_list=""

if cmd_exists docker; then
    docker_running=$(service_active docker && echo "true" || echo "false")
    docker_version=$(docker --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
    container_count=$(docker ps -q 2>/dev/null | wc -l || echo "0")
    cont_list="${cont_list}{\"name\":\"docker\",\"running\":${docker_running},\"version\":\"${docker_version}\",\"container_count\":${container_count}},"
fi

if cmd_exists podman; then
    podman_running=$(systemctl is-active podman 2>/dev/null && echo "true" || echo "false")
    podman_version=$(podman --version 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
    cont_list="${cont_list}{\"name\":\"podman\",\"running\":${podman_running},\"version\":\"${podman_version}\"},"
fi

cont_list="${cont_list%,}"
[ -n "$cont_list" ] && containers="[${cont_list}]"

# ============================================
# DETECT MAIL SERVICES
# ============================================
mail_services="[]"
mail_list=""

if cmd_exists postfix || service_active postfix 2>/dev/null; then
    postfix_running=$(service_active postfix && echo "true" || echo "false")
    mail_list="${mail_list}{\"name\":\"postfix\",\"running\":${postfix_running}},"
fi

if cmd_exists exim || cmd_exists exim4 || service_active exim4 2>/dev/null; then
    exim_running=$(service_active exim4 || service_active exim && echo "true" || echo "false")
    mail_list="${mail_list}{\"name\":\"exim\",\"running\":${exim_running}},"
fi

if cmd_exists dovecot || service_active dovecot 2>/dev/null; then
    dovecot_running=$(service_active dovecot && echo "true" || echo "false")
    mail_list="${mail_list}{\"name\":\"dovecot\",\"running\":${dovecot_running}},"
fi

mail_list="${mail_list%,}"
[ -n "$mail_list" ] && mail_services="[${mail_list}]"

# ============================================
# DETECT WEB SITES AND APPLICATIONS
# ============================================
sites="[]"
site_list=""

# Common web directories to scan
for webroot in /var/www /home/*/public_html /home/*/www /srv/www; do
    [ ! -d "$webroot" ] && continue
    
    # Find directories that look like sites (max depth 2)
    for sitedir in "$webroot"/*/ "$webroot"/*/*/; do
        [ ! -d "$sitedir" ] && continue
        
        site_type="unknown"
        site_framework=""
        
        # Detect WordPress
        if [ -f "${sitedir}wp-config.php" ]; then
            site_type="wordpress"
            wp_version=$(grep "wp_version" "${sitedir}wp-includes/version.php" 2>/dev/null | grep -oP "[0-9]+\.[0-9]+\.?[0-9]*" | head -1 || echo "unknown")
            site_framework="WordPress ${wp_version}"
        # Detect Laravel
        elif [ -f "${sitedir}artisan" ] && [ -f "${sitedir}composer.json" ]; then
            site_type="laravel"
            laravel_version=$(grep -oP "\"laravel/framework\": \"\^?\K[0-9.]+" "${sitedir}composer.json" 2>/dev/null || echo "unknown")
            site_framework="Laravel ${laravel_version}"
        # Detect Symfony
        elif [ -f "${sitedir}symfony.lock" ] || [ -d "${sitedir}vendor/symfony" ]; then
            site_type="symfony"
            site_framework="Symfony"
        # Detect Node.js
        elif [ -f "${sitedir}package.json" ]; then
            site_type="nodejs"
            if grep -q "next" "${sitedir}package.json" 2>/dev/null; then
                site_framework="Next.js"
            elif grep -q "nuxt" "${sitedir}package.json" 2>/dev/null; then
                site_framework="Nuxt.js"
            elif grep -q "express" "${sitedir}package.json" 2>/dev/null; then
                site_framework="Express.js"
            else
                site_framework="Node.js"
            fi
        # Detect Python
        elif [ -f "${sitedir}requirements.txt" ] || [ -f "${sitedir}setup.py" ]; then
            site_type="python"
            if [ -f "${sitedir}manage.py" ]; then
                site_framework="Django"
            elif grep -q "flask" "${sitedir}requirements.txt" 2>/dev/null; then
                site_framework="Flask"
            else
                site_framework="Python"
            fi
        # Detect static site
        elif [ -f "${sitedir}index.html" ] && [ ! -f "${sitedir}index.php" ]; then
            site_type="static"
            site_framework="Static HTML"
        # Detect generic PHP
        elif [ -f "${sitedir}index.php" ]; then
            site_type="php"
            site_framework="PHP"
        fi
        
        # Skip unknown or common system dirs
        [ "$site_type" = "unknown" ] && continue
        [[ "$sitedir" == *"/html/"* ]] && [ "$site_type" = "unknown" ] && continue
        
        # Get directory name as site identifier
        site_name=$(basename "${sitedir%/}")
        site_path="${sitedir%/}"
        
        site_list="${site_list}{\"name\":\"${site_name}\",\"path\":\"${site_path}\",\"type\":\"${site_type}\",\"framework\":\"${site_framework}\"},"
    done
done

site_list="${site_list%,}"
[ -n "$site_list" ] && sites="[${site_list}]"

# ============================================
# DETECT PROCESS MANAGERS
# ============================================
process_managers="[]"
pm_list=""

if cmd_exists pm2; then
    pm2_apps=$(pm2 jlist 2>/dev/null | grep -c "\"name\"" || echo "0")
    pm_list="${pm_list}{\"name\":\"pm2\",\"managed_apps\":${pm2_apps}},"
fi

if cmd_exists supervisorctl; then
    supervisor_running=$(service_active supervisor && echo "true" || echo "false")
    pm_list="${pm_list}{\"name\":\"supervisor\",\"running\":${supervisor_running}},"
fi

pm_list="${pm_list%,}"
[ -n "$pm_list" ] && process_managers="[${pm_list}]"

# ============================================
# SYSTEM SUMMARY
# ============================================
os_name=$(grep -oP "^PRETTY_NAME=\"\K[^\"]+" /etc/os-release 2>/dev/null || uname -s)
os_version=$(grep -oP "^VERSION_ID=\"\K[^\"]+" /etc/os-release 2>/dev/null || uname -r)
hostname=$(hostname)
cpu_cores=$(nproc)
total_ram_mb=$(free -m | awk "/^Mem:/ {print \$2}")

# ============================================
# OUTPUT JSON
# ============================================
cat << EOF
{
  "script": "00_service_discovery",
  "timestamp": "$(date -Iseconds)",
  "status": "ok",
  "system": {
    "hostname": "${hostname}",
    "os": "${os_name}",
    "os_version": "${os_version}",
    "cpu_cores": ${cpu_cores},
    "ram_mb": ${total_ram_mb}
  },
  "web_servers": ${web_servers},
  "databases": ${databases},
  "caches": ${caches},
  "runtimes": ${runtimes},
  "containers": ${containers},
  "mail_services": ${mail_services},
  "process_managers": ${process_managers},
  "sites": ${sites},
  "summary": {
    "has_web": $([ -n "$web_list" ] && echo "true" || echo "false"),
    "has_database": $([ -n "$db_list" ] && echo "true" || echo "false"),
    "has_cache": $([ -n "$cache_list" ] && echo "true" || echo "false"),
    "has_mail": $([ -n "$mail_list" ] && echo "true" || echo "false"),
    "has_containers": $([ -n "$cont_list" ] && echo "true" || echo "false"),
    "site_count": $(echo "$site_list" | grep -c "\"name\"" || echo "0"),
    "wordpress_count": $(echo "$site_list" | grep -c "\"wordpress\"" || echo "0")
  }
}
EOF
'
