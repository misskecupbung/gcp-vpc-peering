#!/bin/bash
apt-get update && apt-get install -y nginx traceroute postgresql-client
echo "Hello from app-vm" > /var/www/html/index.html
systemctl enable nginx && systemctl start nginx
