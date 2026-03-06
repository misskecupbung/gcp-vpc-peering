#!/bin/bash
apt-get update && apt-get install -y nginx traceroute
echo "Hello from security-vm" > /var/www/html/index.html
systemctl enable nginx && systemctl start nginx
