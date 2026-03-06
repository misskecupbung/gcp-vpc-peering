#!/bin/bash
apt-get update && apt-get install -y nginx traceroute postgresql

# Configure nginx
echo "Hello from data-vm" > /var/www/html/index.html
systemctl enable nginx && systemctl start nginx

# Configure PostgreSQL to listen on all interfaces
PG_CONF=$(find /etc/postgresql -name postgresql.conf)
PG_HBA=$(find /etc/postgresql -name pg_hba.conf)

sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF
echo "host    appdb    appuser    10.1.0.0/24    md5" >> $PG_HBA

systemctl restart postgresql

# Create database and user
sudo -u postgres psql -c "CREATE USER appuser WITH PASSWORD 'changeme123';"
sudo -u postgres psql -c "CREATE DATABASE appdb OWNER appuser;"
sudo -u postgres psql -d appdb -c "CREATE TABLE orders (id SERIAL PRIMARY KEY, product TEXT, quantity INT, created_at TIMESTAMP DEFAULT NOW());"
sudo -u postgres psql -d appdb -c "INSERT INTO orders (product, quantity) VALUES ('Widget A', 10), ('Widget B', 25), ('Widget C', 5);"
sudo -u postgres psql -d appdb -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO appuser;"
sudo -u postgres psql -d appdb -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO appuser;"
