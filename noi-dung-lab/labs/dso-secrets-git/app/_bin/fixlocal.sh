#!/bin/bash
set -u

HOME_DIR="${HOME:-/home/ubuntu}"
STATE_DIR="$HOME_DIR/state"
mkdir -p "$STATE_DIR"

MINIO_ROOT_USER="miniolabadmin"
MINIO_ROOT_PASSWORD="Lab-Adm1n-R00t-2024-DoNotShare"

mc alias set labadmin "http://storage:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" \
  >"$STATE_DIR/mc_alias.log" 2>&1 || true

cd "$HOME_DIR" || exit 1
nohup python3 "$HOME_DIR/app.py" >"$STATE_DIR/app.log" 2>&1 &
disown 2>/dev/null || true

echo "[fixlocal:app] corp-backend API dang khoi dong tren cong 8080 (PID $!)"
