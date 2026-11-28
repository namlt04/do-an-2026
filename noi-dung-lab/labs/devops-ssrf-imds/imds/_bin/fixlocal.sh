#!/bin/bash

set -u
PASS="$1"
HOME_DIR="/home/ubuntu"

touch "$HOME_DIR/imds_access.log"
echo "$PASS" | sudo -S chown ubuntu:ubuntu "$HOME_DIR/imds_access.log" 2>/dev/null

echo "$PASS" | sudo -S systemctl daemon-reload
echo "$PASS" | sudo -S systemctl enable imdsapp.service
echo "$PASS" | sudo -S systemctl restart imdsapp.service

for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://127.0.0.1:80/health"; then
        break
    fi
    sleep 0.5
done

exit 0
