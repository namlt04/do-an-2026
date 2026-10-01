#!/bin/bash
#
#  cloud-ssrf-imds : web (imgproxy-portal) - fixlocal
#
#  Chay sau khi parameterization hoan tat. Khoi dong Flask app o nen
#  (khong dung systemd de don gian hoa - xem LAB-BUILD-RULES.md muc 3).
#  $1 = mat khau user container, $2 = uid

set -u
HOME_DIR="/home/ubuntu"
APP_DIR="$HOME_DIR/webapp"
LOG_OUT="$HOME_DIR/webapp.out.log"

touch "$HOME_DIR/fetch.log"
chown ubuntu:ubuntu "$HOME_DIR/fetch.log" "$APP_DIR/config.yaml" 2>/dev/null

cd "$APP_DIR" || exit 1
nohup python3 "$APP_DIR/app.py" > "$LOG_OUT" 2>&1 < /dev/null &
disown

# Doi service san sang (toi da ~15s) de cac container khac (WAIT_FOR) va
# sinh vien khong gap loi ket noi ngay nhung giay dau.
for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://127.0.0.1:8080/health"; then
        break
    fi
    sleep 0.5
done

exit 0
