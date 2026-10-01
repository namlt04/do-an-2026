#!/bin/bash
#
# dso-secrets-git : app/_bin/fixlocal.sh
# ----------------------------------------------------------------------------
# Chay SAU khi tham so hoa (flag_api.txt va flag_rotate.txt da duoc thay the
# bang gia tri rieng cho tung sinh vien qua co che HASH_REPLACE). Container
# nay chay he thong (/sbin/init) nhung khong can quyen root cho cac buoc duoi
# day (cong 8080 khong phai privileged port).
#
#   1. Cau hinh mc voi tai khoan admin NOI BO cua MinIO (chi de app tu dieu
#      phoi buoc rotate sau nay — khong lien quan Git history).
#   2. Khoi dong Flask API (app.py) chay nen tren cong 8080.
# ----------------------------------------------------------------------------
set -u

HOME_DIR="${HOME:-/home/ubuntu}"
STATE_DIR="$HOME_DIR/state"
mkdir -p "$STATE_DIR"

MINIO_ROOT_USER="miniolabadmin"
MINIO_ROOT_PASSWORD="Lab-Adm1n-R00t-2024-DoNotShare"

# Alias mc cho tai khoan ROOT cua MinIO (dung khi /admin/rotate can vo hieu
# hoa AWS key gia). Khong bat buoc storage phai san sang ngay luc nay vi lenh
# nay chi luu cau hinh cuc bo; ket noi thuc su chi xay ra khi rotate duoc goi.
mc alias set labadmin "http://storage:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" \
  >"$STATE_DIR/mc_alias.log" 2>&1 || true

# Khoi dong Flask API chay nen, log ra $HOME/state/app.log
cd "$HOME_DIR" || exit 1
nohup python3 "$HOME_DIR/app.py" >"$STATE_DIR/app.log" 2>&1 &
disown 2>/dev/null || true

echo "[fixlocal:app] corp-backend API dang khoi dong tren cong 8080 (PID $!)"
