#!/bin/bash
set -u
PW="$1"
echo "$PW" | sudo -S mkdir -p /var/log/coraza
echo "$PW" | sudo -S chmod 1777 /var/log/coraza
echo "$PW" | sudo -S systemctl daemon-reload
echo "$PW" | sudo -S systemctl enable caddy.service wafctl.service
echo "$PW" | sudo -S systemctl restart caddy.service
echo "$PW" | sudo -S systemctl restart wafctl.service
for i in $(seq 1 40); do curl -s -o /dev/null http://localhost:80/ && break; sleep 2; done
