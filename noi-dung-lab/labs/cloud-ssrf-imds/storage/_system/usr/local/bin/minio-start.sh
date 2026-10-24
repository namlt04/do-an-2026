#!/bin/bash
# Wrapper cho systemd: nap MINIO_ROOT_USER/PASSWORD da parameterize (HASH_REPLACE)
# tu minio_env.sh roi chay minio. Nho vay MinIO auto-start qua systemd moi lan
# boot/restart (khong chi dua vao fixlocal lan dau).
set -a
# shellcheck disable=SC1091
source /home/ubuntu/minio_env.sh
set +a
mkdir -p /home/ubuntu/miniodata
exec /usr/local/bin/minio server /home/ubuntu/miniodata --address ":9000" --console-address ":9001"
