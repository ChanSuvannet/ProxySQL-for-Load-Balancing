## 📌 Project Flow
Start MySQL Primary and Replica

- mysql-primary (Handles INSERT, UPDATE, DELETE)
- mysql-replica (Handles SELECT)
  Set up replication between Primary & Replica.
Start ProxySQL

ProxySQL waits for MySQL to be ready.
ProxySQL configures itself:
Queries go to replica for SELECT.
Queries go to primary for INSERT, UPDATE, DELETE.
Saves configurations.
Testing & Validation

Ensure replication works.
Ensure ProxySQL routes queries correctly.
📜 1. docker-compose.yml
yaml
Copy
Edit
```docker
version: "3.8"
services:
  mysql-primary:
    image: mysql:latest
    container_name: mysql-primary
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: mydatabase
      MYSQL_USER: myuser
      MYSQL_PASSWORD: mypassword
    ports:
      - "3307:3306"
    networks:
      - mysql-network
    command: --server-id=1 --log-bin=mysql-bin --binlog-do-db=mydatabase
    volumes:
      - mysql_primary_data:/var/lib/mysql

  mysql-replica:
    image: mysql:latest
    container_name: mysql-replica
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: mydatabase
      MYSQL_USER: myuser
      MYSQL_PASSWORD: mypassword
    ports:
      - "3308:3306"
    networks:
      - mysql-network
    command: --server-id=2 --log-bin=mysql-bin --binlog-do-db=mydatabase --relay-log=relay-bin
    volumes:
      - mysql_replica_data:/var/lib/mysql

  proxysql:
    image: proxysql/proxysql
    container_name: proxysql
    restart: always
    ports:
      - "6032:6032"
      - "6033:6033"
    networks:
      - mysql-network
    volumes:
      - ./entrypoint.sh:/docker-entrypoint-initdb.d/entrypoint.sh
    entrypoint: ["/bin/bash", "/docker-entrypoint-initdb.d/entrypoint.sh"]

networks:
  mysql-network:
    driver: bridge

volumes:
  mysql_primary_data:
  mysql_replica_data:
```
📜 2. entrypoint.sh (Full Auto Configuration)
bash
Copy
Edit
#!/bin/bash

echo "🚀 Waiting for MySQL Primary and Replica to be ready..."

# Wait for MySQL Primary to be ready
until mysql -h mysql-primary -u root -prootpassword -e "SELECT 1"; do
  sleep 1
done

# Wait for MySQL Replica to be ready
until mysql -h mysql-replica -u root -prootpassword -e "SELECT 1"; do
  sleep 1
done

echo "✅ MySQL is up! Setting up replication..."

# Set up MySQL Primary
mysql -h mysql-primary -u root -prootpassword <<EOF
  CREATE USER 'replicator'@'%' IDENTIFIED BY 'replpassword';
  GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
  FLUSH PRIVILEGES;
  SHOW MASTER STATUS;
EOF

# Get log file and position
PRIMARY_LOG_FILE=$(mysql -h mysql-primary -u root -prootpassword -e "SHOW MASTER STATUS\G" | grep File | awk '{print $2}')
PRIMARY_LOG_POS=$(mysql -h mysql-primary -u root -prootpassword -e "SHOW MASTER STATUS\G" | grep Position | awk '{print $2}')

# Set up MySQL Replica
mysql -h mysql-replica -u root -prootpassword <<EOF
  CHANGE MASTER TO 
  MASTER_HOST='mysql-primary', 
  MASTER_USER='replicator', 
  MASTER_PASSWORD='replpassword', 
  MASTER_LOG_FILE='$PRIMARY_LOG_FILE', 
  MASTER_LOG_POS=$PRIMARY_LOG_POS;
  START SLAVE;
  SHOW SLAVE STATUS\G;
EOF

echo "✅ Replication set up! Configuring ProxySQL..."

# Wait for ProxySQL to be ready
until mysql -u admin -padmin -h 127.0.0.1 -P 6032 -e "SELECT 1"; do
  sleep 1
done

# Configure ProxySQL
mysql -u admin -padmin -h 127.0.0.1 -P 6032 <<EOF
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
🔬 3. Testing & Validation
1️⃣ Check if Everything is Running
sh
Copy
Edit
docker ps
You should see:

mysql-primary
mysql-replica
proxysql
2️⃣ Verify Replication
sh
Copy
Edit
docker exec -it mysql-primary mysql -u root -prootpassword -e "SHOW MASTER STATUS;"
docker exec -it mysql-replica mysql -u root -prootpassword -e "SHOW SLAVE STATUS\G;"
✅ If SHOW SLAVE STATUS\G; returns "Waiting for master to send event", replication is working.

3️⃣ Test Read/Write Splitting via ProxySQL
📌 Run an INSERT Query (Should go to Primary)
sh
Copy
Edit
mysql -h 127.0.0.1 -P 6033 -u myuser -pmypassword -e "INSERT INTO mydatabase.test_table (column1) VALUES ('test_data');"
📌 Verify INSERT Went to Primary
sh
Copy
Edit
docker exec -it mysql-primary mysql -u root -prootpassword -e "SELECT * FROM mydatabase.test_table;"
✅ The data should be there.

📌 Verify Replication to Replica
sh
Copy
Edit
docker exec -it mysql-replica mysql -u root -prootpassword -e "SELECT * FROM mydatabase.test_table;"
✅ If the data appears, replication is working.

4️⃣ Verify Query Routing in ProxySQL
sh
Copy
Edit
docker exec -it proxysql mysql -u admin -padmin -h 127.0.0.1 -P 6032 -e "SELECT * FROM mysql_query_rules;"
docker exec -it proxysql mysql -u admin -padmin -h 127.0.0.1 -P 6032 -e "SELECT * FROM mysql_servers;"
✅ This confirms ProxySQL is routing queries correctly.

🎯 Summary
✔ MySQL Primary & Replica auto-configured.
✔ Replication setup is automatic.
✔ ProxySQL auto-configured for read/write splitting.
✔ Fully automated in docker-compose up -d.

