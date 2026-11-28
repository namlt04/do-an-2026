#!/bin/bash
set -a
# shellcheck disable=SC1091
source /home/ubuntu/minio_env.sh
export MINIO_AUDIT_WEBHOOK_ENABLE_primary="on"
export MINIO_AUDIT_WEBHOOK_ENDPOINT_primary="http://127.0.0.1:9100/audit"
set +a
mkdir -p /home/ubuntu/miniodata
exec /usr/local/bin/minio server /home/ubuntu/miniodata --address ":9000" --console-address ":9001"
