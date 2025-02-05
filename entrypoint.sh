#!/bin/bash
set -e  # Exit script on any error

echo "🚀 Ensuring entrypoint script is executable..."
chmod +x /entrypoint.sh

echo "🚀 Waiting for MySQL Primary and Replica to be ready..."

# Function to wait for MySQL to be ready
wait_for_mysql() {
  local host="$1"
  echo "⏳ Waiting for $host..."
  until mysql -h "$host" -u root -prootpassword -e "SELECT 1" &> /dev/null; do
    echo "⏳ Still waiting for $host..."
    sleep 5
  done
  echo "✅ $host is ready!"
}

# Wait for MySQL servers
wait_for_mysql mysql-primary
wait_for_mysql mysql-replica

echo "✅ MySQL servers are up! Setting up replication..."

# Set up MySQL Primary
mysql -h mysql-primary -u root -prootpassword <<EOF
  CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY 'replpassword';
  GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
  FLUSH PRIVILEGES;
EOF

# Set up MySQL Replica
mysql -h mysql-replica -u root -prootpassword <<EOF
  STOP REPLICA;
  RESET REPLICA;
  CHANGE REPLICATION SOURCE TO 
    SOURCE_HOST='mysql-primary', 
    SOURCE_USER='replicator', 
    SOURCE_LOG_FILE='mysql-bin.000001',
    SOURCE_LOG_POS=154;
  START REPLICA;
  SHOW REPLICA STATUS\G;
EOF

echo "✅ Replication set up! Configuring ProxySQL..."

# Wait for ProxySQL to be ready
until mysql -u admin -padmin -h proxysql -P 6032 -e "SELECT 1" &> /dev/null; do
  echo "⏳ Waiting for ProxySQL..."
  sleep 5
done
proxysqlformysqlloadbalancing-proxysql-1 mysql -u admin -padmin -h
# Configure ProxySQL
mysql -u admin -padmin -h proxysql -P 6032 <<EOF
  DELETE FROM mysql_servers;
  INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (1, 'mysql-primary', 3306);
  INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (2, 'mysql-replica', 3306);

  DELETE FROM mysql_query_rules;
  INSERT INTO mysql_query_rules (rule_id, match_pattern, destination_hostgroup) VALUES (1, '^SELECT', 2);
  INSERT INTO mysql_query_rules (rule_id, match_pattern, destination_hostgroup) VALUES (2, '^INSERT|^UPDATE|^DELETE', 1);

  LOAD MYSQL SERVERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
  LOAD MYSQL QUERY RULES TO RUNTIME;
  SAVE MYSQL QUERY RULES TO DISK;
EOF

echo "✅ ProxySQL configured! Starting ProxySQL..."
exec /entrypoint.sh "$@"
