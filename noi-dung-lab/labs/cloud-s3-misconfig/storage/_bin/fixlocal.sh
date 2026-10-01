#!/bin/bash
#
# storage/_bin/fixlocal.sh - cloud-s3-misconfig
#
# Chay SAU KHI parameterization hoan tat: cac file token trong ~/seed/*.token da
# duoc thay placeholder (LEAKACCESSKEY, LEAKSECRETKEY, RUNFLAG, HARDENACCESSKEY,
# HARDENSECRETKEY) bang gia tri hash RIENG CHO TUNG SINH VIEN (tinh tu
# LAB_MASTER_SEED + email SV, xem config/parameter.config).
#
# Script nay:
#   1) Bat dich vu MinIO qua systemd (unit: _system/etc/systemd/system/minio.service).
#   2) Tao 2 bucket: public-assets (se bi lam public) va secure-data (private).
#   3) Nap du lieu vao public-assets: vai file tinh vo hai + 1 file backup CHUA
#      credential bi lo (o dang .env va dang .tar.gz de buoc SV giai nen).
#   4) Dat policy anonymous list+get cho public-assets — DAY LA CAU HINH SAI
#      trong tam bai lab, sinh vien phai tu phat hien va khai thac.
#   5) Tao mot MinIO user UNG VOI credential bi lo, chi cap quyen GetObject/
#      ListBucket tren secure-data (least-privilege ve pham vi, nhung van "lo").
#   6) Dat object flag vao secure-data/confidential/flag.txt.
#   7) Tao mot MinIO user RIENG cho Nhiem vu 4 (hardening), voi quyen sua
#      bucket policy / versioning tren 2 bucket cua bai — day la credential duoc
#      CAP CONG KHAI cho SV qua ~/hardening-admin.env (KHONG phai credential lo).
#   8) Don sach cac file token nhay cam tren dia sau khi da seed xong.
#
# $1 = mat khau user container, $2 = uid
#
set -u
PASSWD="${1:-}"
LOGF=/tmp/cloud-s3-misconfig-fixlocal.log
exec >>"$LOGF" 2>&1
echo "===== fixlocal storage $(date) ====="

SEED_DIR="$HOME/seed"
ENDPOINT="http://127.0.0.1:9000"
PUBLIC_ENDPOINT="http://172.33.0.30:9000"
MINIO_ROOT_USER="labadmin"
MINIO_ROOT_PASSWORD="Labtainer_M1n10_Root_2026_s3misconfig"

# ---- 0) doc gia tri DA duoc parameterize (rieng cho tung sinh vien) ----
LEAK_ACCESS_KEY="$(cat "$SEED_DIR/leaked_access_key.token" 2>/dev/null)"
LEAK_SECRET_KEY="$(cat "$SEED_DIR/leaked_secret_key.token" 2>/dev/null)"
FLAG_VALUE="$(cat "$SEED_DIR/flag.token" 2>/dev/null)"
HARDEN_ACCESS_KEY="$(cat "$SEED_DIR/harden_access_key.token" 2>/dev/null)"
HARDEN_SECRET_KEY="$(cat "$SEED_DIR/harden_secret_key.token" 2>/dev/null)"

if [ -z "$LEAK_ACCESS_KEY" ] || [ -z "$FLAG_VALUE" ] || [ -z "$HARDEN_ACCESS_KEY" ]; then
  echo "[!] Khong doc duoc gia tri da parameterize trong $SEED_DIR - dung lai."
  exit 1
fi

# ---- 1) bat dich vu MinIO qua systemd ----
echo "$PASSWD" | sudo -S systemctl daemon-reload
echo "$PASSWD" | sudo -S systemctl enable minio.service
echo "$PASSWD" | sudo -S systemctl restart minio.service

# ---- 2) cho MinIO san sang ----
READY=0
for i in $(seq 1 40); do
  if curl -sf "$ENDPOINT/minio/health/live" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then
  echo "[!] MinIO khong san sang sau 40s - kiem tra: systemctl status minio.service"
fi

# ---- 3) alias quan tri NOI BO (chi dung ben trong script nay, SV khong biet) ----
mc alias set local "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1

# ---- 4) tao 2 bucket (bo qua loi neu da ton tai - script co the chay lai) ----
mc mb local/public-assets 2>/dev/null || true
mc mb local/secure-data   2>/dev/null || true

# ---- 5) noi dung bucket public: file tinh vo hai + backup lo credential ----
STAGE="/tmp/s3misconfig-seed"
rm -rf "$STAGE"
mkdir -p "$STAGE/static" "$STAGE/backup" "$STAGE/secure"

cat > "$STAGE/static/index.html" <<'EOF'
<html><head><title>Internal static mirror</title></head>
<body><h1>public-assets - static mirror</h1><p>Noi luu file tinh dung chung (anh, html).</p></body></html>
EOF

cat > "$STAGE/static/notice.txt" <<'EOF'
Bucket nay chi danh cho file tinh dung chung.
KHONG duoc dat backup/cau hinh/credential vao day.
EOF

cat > "$STAGE/backup/app-config.env" <<EOF
# legacy backup - object-storage-app config (2025-08-11)
# TODO: quen xoa truoc khi bat public bucket nay - phai rotate + di doi ngay!
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

# ---- 6) CAU HINH SAI can khai thac: cho phep anonymous list+get tren public-assets ----
mc anonymous set download local/public-assets

# ---- 7) user ung voi credential bi lo -> CHI duoc GET/LIST tren secure-data ----
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

# ---- 8) object flag trong bucket private (secure-data KHONG co policy anonymous) ----
# Khong them '\n' cuoi de tranh lech chuoi khi so sanh voi parameter.s3flag.
printf '%s' "$FLAG_VALUE" > "$STAGE/secure/flag.txt"
mc cp "$STAGE/secure/flag.txt" local/secure-data/confidential/flag.txt

# ---- 9) user rieng cho Nhiem vu 4 (hardening) - CHI du quyen sua policy/versioning ----
#         (khong phai credential bi lo; duoc cap CONG KHAI qua ~/hardening-admin.env tren client)
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

# ---- 10) don token nhay cam tren dia may storage (khong con can sau khi da seed) ----
rm -f "$SEED_DIR"/*.token
rm -rf "$STAGE"

echo "===== fixlocal storage: DONE ====="
