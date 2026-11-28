#!/bin/bash
set -u
PASSWD="${1:-}"
LOGF=/tmp/devops-s3-misconfig-fixlocal.log
exec >>"$LOGF" 2>&1
echo "===== fixlocal storage $(date) ====="

SEED_DIR="$HOME/seed"
ENDPOINT="http://127.0.0.1:9000"
PUBLIC_ENDPOINT="http://172.33.0.30:9000"
MINIO_ROOT_USER="labadmin"
MINIO_ROOT_PASSWORD="Labtainer_M1n10_Root_2026_s3misconfig"

LEAK_ACCESS_KEY="$(cat "$SEED_DIR/leaked_access_key.token" 2>/dev/null)"
LEAK_SECRET_KEY="$(cat "$SEED_DIR/leaked_secret_key.token" 2>/dev/null)"
FLAG_VALUE="$(cat "$SEED_DIR/flag.token" 2>/dev/null)"
HARDEN_ACCESS_KEY="$(cat "$SEED_DIR/harden_access_key.token" 2>/dev/null)"
HARDEN_SECRET_KEY="$(cat "$SEED_DIR/harden_secret_key.token" 2>/dev/null)"

if [ -z "$LEAK_ACCESS_KEY" ] || [ -z "$FLAG_VALUE" ] || [ -z "$HARDEN_ACCESS_KEY" ]; then
  echo "[!] Cannot read parameterized values in $SEED_DIR - aborting."
  exit 1
fi

echo "$PASSWD" | sudo -S systemctl daemon-reload
echo "$PASSWD" | sudo -S systemctl enable minio.service
echo "$PASSWD" | sudo -S systemctl restart minio.service

READY=0
for i in $(seq 1 40); do
  if curl -sf "$ENDPOINT/minio/health/live" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then
  echo "[!] MinIO not ready after 40s - check: systemctl status minio.service"
fi

mc alias set local "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1

mc mb local/public-assets 2>/dev/null || true
mc mb local/secure-data   2>/dev/null || true

STAGE="/tmp/s3misconfig-seed"
rm -rf "$STAGE"
mkdir -p "$STAGE/static" "$STAGE/backup" "$STAGE/secure"

cat > "$STAGE/static/index.html" <<'EOF'
<html><head><title>Internal static mirror</title></head>
<body><h1>public-assets - static mirror</h1><p>Shared static files (images, html).</p></body></html>
EOF

cat > "$STAGE/static/notice.txt" <<'EOF'
This bucket is for shared static files only.
Do NOT store backups/configs/credentials here.
EOF

cat > "$STAGE/backup/app-config.env" <<EOF
# legacy backup - object-storage-app config (2025-08-11)
# TODO: forgot to remove before making this bucket public - rotate + move it NOW!
APP_ENV=production
S3_ENDPOINT=${PUBLIC_ENDPOINT}
AWS_ACCESS_KEY_ID=${LEAK_ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${LEAK_SECRET_KEY}
AWS_DEFAULT_REGION=us-east-1
EOF

tar -C "$STAGE/backup" -czf "$STAGE/backup/app-backup-20250811.tar.gz" app-config.env

mc cp "$STAGE/static/index.html"              local/public-assets/static/index.html
mc cp "$STAGE/static/notice.txt"               local/public-assets/static/notice.txt
mc cp "$STAGE/backup/app-backup-20250811.tar.gz" local/public-assets/backup/app-backup-20250811.tar.gz

mc anonymous set download local/public-assets

mc admin user add local "$LEAK_ACCESS_KEY" "$LEAK_SECRET_KEY"
cat > "$STAGE/policy-leak-readonly.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::secure-data", "arn:aws:s3:::secure-data/*"]
    }
  ]
}
EOF
mc admin policy create local leak-readonly "$STAGE/policy-leak-readonly.json" 2>/dev/null \
  || mc admin policy add local leak-readonly "$STAGE/policy-leak-readonly.json"
mc admin policy attach local leak-readonly --user "$LEAK_ACCESS_KEY" 2>/dev/null \
  || mc admin policy set local leak-readonly user="$LEAK_ACCESS_KEY"

printf '%s' "$FLAG_VALUE" > "$STAGE/secure/flag.txt"
mc cp "$STAGE/secure/flag.txt" local/secure-data/confidential/flag.txt

mc admin user add local "$HARDEN_ACCESS_KEY" "$HARDEN_SECRET_KEY"
cat > "$STAGE/policy-harden-admin.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketPolicy", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
        "s3:GetBucketVersioning", "s3:PutBucketVersioning",
        "s3:ListBucket", "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::public-assets", "arn:aws:s3:::public-assets/*",
        "arn:aws:s3:::secure-data", "arn:aws:s3:::secure-data/*"
      ]
    }
  ]
}
EOF
mc admin policy create local harden-admin "$STAGE/policy-harden-admin.json" 2>/dev/null \
  || mc admin policy add local harden-admin "$STAGE/policy-harden-admin.json"
mc admin policy attach local harden-admin --user "$HARDEN_ACCESS_KEY" 2>/dev/null \
  || mc admin policy set local harden-admin user="$HARDEN_ACCESS_KEY"

rm -f "$SEED_DIR"/*.token
rm -rf "$STAGE"

echo "===== fixlocal storage: DONE ====="
