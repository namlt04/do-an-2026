#!/bin/bash
#
#  cloud-ssrf-imds : imds (gia lap Instance Metadata Service) - fixlocal
#
#  Chay sau khi parameterization hoan tat.
#  $1 = mat khau user container, $2 = uid
#
#  1) (Best-effort, KHONG bat buoc) thu gan them alias 169.254.169.254 len
#     interface cua chinh container nay, de mo phong sat hon dia chi that
#     cua IMDS tren cloud. Neu Docker bridge khong cho phep dinh tuyen dia
#     chi ngoai subnet LAB_NET toi day, buoc nay se im lang that bai va
#     KHONG anh huong gi den bai lab - duong dan chinh thuc/duoc cham diem
#     la ten DNS noi bo "imds" (172.34.0.40). Xem BUILD-NOTES.md.
#  2) Khoi dong Flask app tren cong 80 (can quyen root de bind cong <1024).

set -u
PASS="$1"
HOME_DIR="/home/ubuntu"
APP_DIR="$HOME_DIR/imds_app"
LOG_OUT="$HOME_DIR/imds_app.out.log"

touch "$HOME_DIR/imds_access.log"
chown ubuntu:ubuntu "$HOME_DIR/imds_access.log" 2>/dev/null

# --- (1) Best-effort: alias 169.254.169.254 -----------------------------
IFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
if [ -n "${IFACE:-}" ]; then
    echo "$PASS" | sudo -S ip addr add 169.254.169.254/32 dev "$IFACE" label "$IFACE:imds" >/dev/null 2>&1
fi

# --- (2) Khoi dong imds-mock tren cong 80 (can root) ---------------------
echo "$PASS" | sudo -S bash -c "cd '$APP_DIR' && nohup python3 '$APP_DIR/app.py' > '$LOG_OUT' 2>&1 < /dev/null & disown"

for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://127.0.0.1:80/health"; then
        break
    fi
    sleep 0.5
done

exit 0
