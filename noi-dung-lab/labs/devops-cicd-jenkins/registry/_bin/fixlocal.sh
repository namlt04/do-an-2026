#!/bin/bash
set -u
PW="$1"
REGPASS="$(tr -d '\r\n' < /opt/regseed/regpass.txt)"
echo "$PW" | sudo -S bash -c "htpasswd -Bbn deployer '$REGPASS' > /auth/htpasswd"
echo "$PW" | sudo -S python3 /opt/regseed/regseed.py
echo "$PW" | sudo -S chown -R ubuntu:ubuntu /var/lib/registry /auth /opt/regseed
echo "$PW" | sudo -S systemctl daemon-reload
echo "$PW" | sudo -S systemctl enable registry.service
echo "$PW" | sudo -S systemctl restart registry.service
for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:5000/v2/ && break; sleep 2; done
