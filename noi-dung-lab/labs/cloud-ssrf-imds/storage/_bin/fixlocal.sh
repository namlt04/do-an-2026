#!/bin/bash
#
#  cloud-ssrf-imds : storage - fixlocal
#
#  Chay sau khi parameterization hoan tat (minio_env.sh va flag_seed.txt da
#  duoc thay the HASH_REPLACE per-student truoc khi script nay chay).
#  Khoi dong MinIO (cong 9000), tao bucket private "fin-reports" va seed
#  object flag.txt bang chinh AccessKeyId/SecretAccessKey ma 'imds' se cap
#  phat cho sinh vien (dam bao credential tam thiet danh cap PHAI dung).
#
#  $1 = mat khau user container, $2 = uid

set -u
HOME_DIR="/home/ubuntu"
DATA_DIR="$HOME_DIR/miniodata"
LOG_OUT="$HOME_DIR/minio.out.log"

mkdir -p "$DATA_DIR"

# shellcheck disable=SC1090
set -a
source "$HOME_DIR/minio_env.sh"
set +a

nohup /usr/local/bin/minio server "$DATA_DIR" --address ":9000" --console-address ":9001" \
    > "$LOG_OUT" 2>&1 < /dev/null &
disown

# --- Doi MinIO san sang ---------------------------------------------------
READY=0
for i in $(seq 1 40); do
    if curl -s -o /dev/null "http://127.0.0.1:9000/minio/health/live"; then
        READY=1
        break
    fi
    sleep 0.5
done

if [ "$READY" -ne 1 ]; then
    echo "CANH BAO: MinIO khong san sang sau ~20s, xem $LOG_OUT" >&2
fi

# --- Cau hinh alias + seed bucket/object private --------------------------
/usr/local/bin/mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --api S3v4 >/dev/null 2>&1
/usr/local/bin/mc mb -p local/fin-reports >/dev/null 2>&1
/usr/local/bin/mc cp "$HOME_DIR/flag_seed.txt" local/fin-reports/flag.txt >/dev/null 2>&1
# Bucket private tuyet doi: khong anonymous/public read/list, chi credential
# hop le (SigV4, trung voi MINIO_ROOT_USER/PASSWORD o tren) moi doc duoc.
/usr/local/bin/mc anonymous set none local/fin-reports >/dev/null 2>&1

exit 0
