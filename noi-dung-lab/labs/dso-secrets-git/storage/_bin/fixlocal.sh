#!/bin/bash
#
# dso-secrets-git : storage/_bin/fixlocal.sh
# ----------------------------------------------------------------------------
# Chay SAU khi tham so hoa (flag_object.txt da duoc thay the bang gia tri
# rieng cho tung sinh vien qua co che HASH_REPLACE). Khong can quyen root
# (cong 9000/9001 khong phai privileged port).
#
#   1. Khoi dong MinIO server (S3-compatible object storage) tren cong 9000.
#   2. Tao bucket private "corp-backups".
#   3. Tao mot MinIO user co access key / secret key = CHINH cap AWS key gia
#      da bi lo trong lich su Git tren may dev (xem dev/_bin/fixlocal.sh) —
#      day la diem noi giua "khai thac" va "dich vu muc tieu". Gan quyen
#      readonly.
#   4. Upload object flag (da duoc parameterize) vao corp-backups/flags/flag.txt.
#
# Khong dung curl de cho MinIO san sang (khong co trong image storage) — dung
# chinh `mc` de retry, tranh phai sua Dockerfile.
# ----------------------------------------------------------------------------
set -u

HOME_DIR="${HOME:-/home/ubuntu}"
DATADIR="$HOME_DIR/miniodata"
STATE_DIR="$HOME_DIR/state"
mkdir -p "$DATADIR" "$STATE_DIR"

export MINIO_ROOT_USER="miniolabadmin"
export MINIO_ROOT_PASSWORD="Lab-Adm1n-R00t-2024-DoNotShare"

# ---- 1) Khoi dong MinIO server chay nen ----
nohup minio server "$DATADIR" --address ":9000" --console-address ":9001" \
      >"$STATE_DIR/minio.log" 2>&1 &
disown 2>/dev/null || true

# ---- Doi MinIO san sang (toi da ~30s), dung mc thay vi curl ----
READY=0
for i in $(seq 1 30); do
  if mc alias set local "http://127.0.0.1:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" \
       >"$STATE_DIR/mc_alias.log" 2>&1 \
     && mc ls local >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done

if [ "$READY" -ne 1 ]; then
  echo "[fixlocal:storage][WARN] MinIO chua san sang sau 30s, cac buoc seed co the that bai" \
    >>"$STATE_DIR/minio.log"
fi

# ---- 2) Bucket private (MinIO mac dinh khong cho anonymous truy cap) ----
mc mb --ignore-existing local/corp-backups >>"$STATE_DIR/minio.log" 2>&1

# ---- 3) User = cap AWS key GIA da lo trong Git history (may dev) ----
LEAK_ACCESS_KEY="AKIAZ7Q2X8VNK4RPDLW3"
LEAK_SECRET_KEY="wWw0kQfZ9pL3xR7bN2sV6yH1tG4mD8cU5aJ0eKqP"
mc admin user add local "$LEAK_ACCESS_KEY" "$LEAK_SECRET_KEY" >>"$STATE_DIR/minio.log" 2>&1

# Gan quyen readonly cho user nay (du de liet ke + doc object flag).
# Cu phap `mc admin policy` da doi qua nhieu phien ban -> thu ca hai.
mc admin policy attach local readonly --user "$LEAK_ACCESS_KEY" >>"$STATE_DIR/minio.log" 2>&1 \
  || mc admin policy set local readonly user="$LEAK_ACCESS_KEY" >>"$STATE_DIR/minio.log" 2>&1 \
  || echo "[fixlocal:storage][WARN] khong gan duoc policy readonly - kiem tra cu phap mc admin policy cua phien ban dang dung" \
       >>"$STATE_DIR/minio.log"

# ---- 4) Upload object flag (da duoc HASH_REPLACE thanh gia tri per-student) ----
mc cp "$HOME_DIR/flag_object.txt" local/corp-backups/flags/flag.txt >>"$STATE_DIR/minio.log" 2>&1

echo "[fixlocal:storage] MinIO san sang tren cong 9000; bucket corp-backups/flags/flag.txt da duoc seed."
