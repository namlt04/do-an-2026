#!/bin/bash
set -a
# shellcheck disable=SC1091
source /home/ubuntu/minio_env.sh
set +a
mkdir -p /home/ubuntu/miniodata
exec /usr/local/bin/minio server /home/ubuntu/miniodata --address ":9000" --console-address ":9001"
