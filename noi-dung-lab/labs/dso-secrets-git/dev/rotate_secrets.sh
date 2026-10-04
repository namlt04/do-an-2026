#!/bin/bash
set -u

REPO="$HOME/repo"
APP_URL="http://app:8080/admin/rotate"
SENSITIVE_PATH="deploy/credentials.yaml"
OUT_FILE="$HOME/loot_rotate.txt"

if [ ! -d "$REPO/.git" ]; then
  echo "[rotate_secrets] Khong tim thay ~/repo (chua co repo Git). Dung lai."
  exit 1
fi

echo "[rotate_secrets] Dang tu dao credential goc tu lich su Git tai $REPO ..."

ADD_COMMIT="$(git -C "$REPO" log --all --diff-filter=A --format='%H' -- "$SENSITIVE_PATH" | tail -n1)"

if [ -z "$ADD_COMMIT" ]; then
  echo "[rotate_secrets] Khong tim thay commit nao them '$SENSITIVE_PATH' trong history."
  echo "                 Hay chac chan ~/repo la repo goc do lab cung cap (dung sua doi)."
  exit 2
fi

CONTENT="$(git -C "$REPO" show "$ADD_COMMIT:$SENSITIVE_PATH" 2>/dev/null)"
if [ -z "$CONTENT" ]; then
  echo "[rotate_secrets] Khong doc duoc noi dung file tai commit $ADD_COMMIT."
  exit 2
fi

OLD_AWS_ACCESS_KEY_ID="$(echo "$CONTENT" | sed -n 's/^[[:space:]]*access_key_id:[[:space:]]*//p' | tr -d '\r')"
OLD_AWS_SECRET_ACCESS_KEY="$(echo "$CONTENT" | sed -n 's/^[[:space:]]*secret_access_key:[[:space:]]*//p' | tr -d '\r')"
OLD_DB_PASSWORD="$(echo "$CONTENT" | sed -n 's/^[[:space:]]*password:[[:space:]]*//p' | tr -d '\r')"
OLD_API_TOKEN="$(echo "$CONTENT" | sed -n 's/^[[:space:]]*token:[[:space:]]*//p' | tr -d '\r')"

if [ -z "$OLD_AWS_ACCESS_KEY_ID" ] || [ -z "$OLD_AWS_SECRET_ACCESS_KEY" ] \
   || [ -z "$OLD_DB_PASSWORD" ] || [ -z "$OLD_API_TOKEN" ]; then
  echo "[rotate_secrets] Trich xuat credential that bai (dinh dang file cau hinh khong nhu ky vong)."
  exit 2
fi

echo "[rotate_secrets] Da dao duoc credential goc (che dau mot phan de tham khao):"
echo "                 AWS_ACCESS_KEY_ID     = ${OLD_AWS_ACCESS_KEY_ID:0:6}************"
echo "                 AWS_SECRET_ACCESS_KEY = ${OLD_AWS_SECRET_ACCESS_KEY:0:4}************************************"
echo "                 DB_PASSWORD           = ****************"
echo "                 API_TOKEN             = ${OLD_API_TOKEN:0:8}************"

PAYLOAD="$(printf '{"aws_access_key_id":"%s","aws_secret_access_key":"%s","db_password":"%s","api_token":"%s"}' \
  "$OLD_AWS_ACCESS_KEY_ID" "$OLD_AWS_SECRET_ACCESS_KEY" "$OLD_DB_PASSWORD" "$OLD_API_TOKEN")"

echo "[rotate_secrets] Dang goi API rotate tren $APP_URL ..."
RESP="$(curl -sS --max-time 15 -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" "$APP_URL")"
RC=$?

if [ $RC -ne 0 ] || [ -z "$RESP" ]; then
  echo "[rotate_secrets] Khong ket noi duoc toi $APP_URL (rc=$RC). Kiem tra mang / dich vu app."
  exit 3
fi

STATUS="$(echo "$RESP" | jq -r '.status // empty' 2>/dev/null)"
if [ "$STATUS" != "rotated" ]; then
  echo "[rotate_secrets] Rotate THAT BAI. Phan hoi tu server:"
  echo "$RESP" | jq . 2>/dev/null || echo "$RESP"
  exit 4
fi

ROTATE_FLAG="$(echo "$RESP" | jq -r '.rotate_flag // empty' 2>/dev/null)"
if [ -z "$ROTATE_FLAG" ]; then
  echo "[rotate_secrets] Rotate thanh cong nhung khong nhan duoc rotate-proof. Thu lai sau."
  exit 5
fi

echo "$ROTATE_FLAG" > "$OUT_FILE"
echo "[rotate_secrets] ROTATE THANH CONG."
echo "                 - DB password va API token TREN app da duoc thay moi (gia tri cu vo hieu)."
echo "                 - AWS key gia TREN storage da bi vo hieu hoa (mc admin user disable)."
echo "                 - Rotate-proof da duoc luu vao: $OUT_FILE"
echo
echo "Hay tu kiem chung: dung lai AWS key CU de truy cap storage, ket qua phai bi tu choi."
