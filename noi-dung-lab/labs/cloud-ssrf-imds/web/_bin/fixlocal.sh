#!/bin/bash

set -u
PASS="${1:-}"
HOME_DIR="/home/ubuntu"
APP_DIR="$HOME_DIR/webapp"

touch "$HOME_DIR/fetch.log"
echo "$PASS" | sudo -S chown ubuntu:ubuntu "$HOME_DIR/fetch.log" "$APP_DIR/config.yaml" 2>/dev/null

echo "$PASS" | sudo -S systemctl daemon-reload
echo "$PASS" | sudo -S systemctl enable webapp.service
echo "$PASS" | sudo -S systemctl restart webapp.service

for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://127.0.0.1:8080/health"; then
        break
    fi
    sleep 0.5
done

exit 0
