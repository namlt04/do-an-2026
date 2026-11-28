#!/bin/bash
set -u
PW="${1:-}"
echo "$PW" | sudo -S systemctl daemon-reload
echo "$PW" | sudo -S systemctl enable minio.service minio-seed.service
echo "$PW" | sudo -S systemctl restart minio.service
echo "$PW" | sudo -S systemctl restart minio-seed.service
echo "[fixlocal:storage] MinIO (systemd) + seed enabled; survives restart."
