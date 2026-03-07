#!/bin/bash
# ServerFlow - Get database status (JSON output)
echo '{'

# PostgreSQL
echo -n '"postgresql":{'
if command -v psql &> /dev/null; then
  PG_VERSION=$(psql --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "unknown")
  PG_RUNNING=$(systemctl is-active postgresql 2>/dev/null || echo "inactive")
  echo -n '"installed":true,"running":"'$PG_RUNNING'","version":"'$PG_VERSION'","port":5432'
else
  echo -n '"installed":false'
fi
echo '},'

# MySQL/MariaDB
echo -n '"mysql":{'
if command -v mysql &> /dev/null; then
  MYSQL_VERSION=$(mysql --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
  MYSQL_RUNNING=$(systemctl is-active mariadb 2>/dev/null || systemctl is-active mysql 2>/dev/null || echo "inactive")
  echo -n '"installed":true,"running":"'$MYSQL_RUNNING'","version":"'$MYSQL_VERSION'","port":3306'
else
  echo -n '"installed":false'
fi
echo '},'

# Redis
echo -n '"redis":{'
if command -v redis-cli &> /dev/null; then
  REDIS_VERSION=$(redis-server --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
  REDIS_RUNNING=$(systemctl is-active redis-server 2>/dev/null || systemctl is-active redis 2>/dev/null || echo "inactive")
  echo -n '"installed":true,"running":"'$REDIS_RUNNING'","version":"'$REDIS_VERSION'","port":6379'
else
  echo -n '"installed":false'
fi
echo '}'

echo '}'
