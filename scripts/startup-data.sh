#!/bin/bash
set -e

apt-get update && apt-get install -y nginx traceroute postgresql

# Configure nginx
echo "Hello from data-vm" > /var/www/html/index.html
systemctl enable nginx && systemctl start nginx

# Start PostgreSQL explicitly
systemctl start postgresql || true

# Wait for postgres user to exist
timeout=30
elapsed=0
while ! id postgres &>/dev/null; do
  if [ $elapsed -ge $timeout ]; then
    echo "Timeout waiting for postgres user"
    exit 1
  fi
  echo "Waiting for postgres user..."
  sleep 2
  elapsed=$((elapsed + 2))
done

# Configure PostgreSQL to listen on all interfaces
PG_CONF=$(find /etc/postgresql -name postgresql.conf | head -1)
PG_HBA=$(find /etc/postgresql -name pg_hba.conf | head -1)

sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
echo "host    appdb    appuser    10.1.0.0/24    md5" >> "$PG_HBA"

systemctl restart postgresql

# Wait for PostgreSQL to accept connections
timeout=30
elapsed=0
while ! sudo -u postgres pg_isready -q; do
  if [ $elapsed -ge $timeout ]; then
    echo "Timeout waiting for PostgreSQL"
    exit 1
  fi
  echo "Waiting for PostgreSQL to be ready..."
  sleep 2
  elapsed=$((elapsed + 2))
done

# Create database and user
sudo -u postgres psql <<EOF
CREATE USER appuser WITH PASSWORD 'changeme123';
CREATE DATABASE appdb OWNER appuser;
\c appdb
CREATE TABLE orders (id SERIAL PRIMARY KEY, product TEXT, quantity INT, created_at TIMESTAMP DEFAULT NOW());
INSERT INTO orders (product, quantity) VALUES ('Widget A', 10), ('Widget B', 25), ('Widget C', 5);
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO appuser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO appuser;
EOF

echo "PostgreSQL setup complete"
