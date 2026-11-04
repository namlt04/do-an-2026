#!/bin/bash
# Idempotent seed for MinIO, runs after minio.service is ready. Runs on every boot
# (via minio-seed.service) so the bucket/user/flag always exist even after a restart.
set -u
EP="http://127.0.0.1:9000"
RU="miniolabadmin"; RP="Lab-Adm1n-R00t-2024-DoNotShare"
LEAK_ACCESS_KEY="AKIAZ7Q2X8VNK4RPDLW3"
LEAK_SECRET_KEY="wWw0kQfZ9pL3xR7bN2sV6yH1tG4mD8cU5aJ0eKqP"
FLAG_SRC="/home/ubuntu/flag_object.txt"

for i in $(seq 1 60); do
    curl -sf "$EP/minio/health/live" >/dev/null 2>&1 && break
    sleep 1
done

mc alias set local "$EP" "$RU" "$RP" >/dev/null 2>&1
mc mb --ignore-existing local/corp-backups >/dev/null 2>&1
mc admin user add local "$LEAK_ACCESS_KEY" "$LEAK_SECRET_KEY" >/dev/null 2>&1 || true
mc admin policy attach local readonly --user "$LEAK_ACCESS_KEY" >/dev/null 2>&1 || true
mc cp "$FLAG_SRC" local/corp-backups/flags/flag.txt >/dev/null 2>&1 || true
exit 0
