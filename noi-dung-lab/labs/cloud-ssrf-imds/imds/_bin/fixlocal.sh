#!/bin/bash

set -u
PASS="$1"
HOME_DIR="/home/ubuntu"
APP_DIR="$HOME_DIR/imds_app"
LOG_OUT="$HOME_DIR/imds_app.out.log"

touch "$HOME_DIR/imds_access.log"
chown ubuntu:ubuntu "$HOME_DIR/imds_access.log" 2>/dev/null

IFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
if [ -n "${IFACE:-}" ]; then
    echo "$PASS" | sudo -S ip addr add 169.254.169.254/32 dev "$IFACE" label "$IFACE:imds" >/dev/null 2>&1
fi

echo "$PASS" | sudo -S bash -c "cd '$APP_DIR' && nohup python3 '$APP_DIR/app.py' > '$LOG_OUT' 2>&1 < /dev/null & disown"

for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://127.0.0.1:80/health"; then
        break
    fi
    sleep 0.5
done

exit 0
