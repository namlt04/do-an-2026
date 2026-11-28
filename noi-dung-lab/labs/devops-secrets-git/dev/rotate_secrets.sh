#!/bin/bash
set -u

REPO="$HOME/repo"
APP_URL="http://app:8080/admin/rotate"
SENSITIVE_PATH="deploy/credentials.yaml"
OUT_FILE="$HOME/loot_rotate.txt"

if [ ! -d "$REPO/.git" ]; then
  echo "[rotate_secrets] ~/repo not found (no Git repo). Stopping."
  exit 1
fi

echo "[rotate_secrets] Recovering the original credentials from Git history in $REPO ..."

ADD_COMMIT="$(git -C "$REPO" log --all --diff-filter=A --format='%H' -- "$SENSITIVE_PATH" | tail -n1)"

if [ -z "$ADD_COMMIT" ]; then
  echo "[rotate_secrets] No commit adding '$SENSITIVE_PATH' found in history."
  echo "                 Make sure ~/repo is the original repo provided by the lab (do not modify it)."
  exit 2
fi

CONTENT="$(git -C "$REPO" show "$ADD_COMMIT:$SENSITIVE_PATH" 2>/dev/null)"
if [ -z "$CONTENT" ]; then
  echo "[rotate_secrets] Cannot read the file content at commit $ADD_COMMIT."
  exit 2
fi

OLD_AWS_ACCESS_KEY_ID="$(echo "$CONTENT" | sed -n 's/^[[:space:]]*access_key_id:[[:space:]]*//p' | tr -d '\r')"
OLD_AWS_SECRET_ACCESS_KEY="$(echo "$CONTENT" | sed -n 's/^[[:space:]]*secret_access_key:[[:space:]]*//p' | tr -d '\r')"
OLD_DB_PASSWORD="$(echo "$CONTENT" | sed -n 's/^[[:space:]]*password:[[:space:]]*//p' | tr -d '\r')"
OLD_API_TOKEN="$(echo "$CONTENT" | sed -n 's/^[[:space:]]*token:[[:space:]]*//p' | tr -d '\r')"

if [ -z "$OLD_AWS_ACCESS_KEY_ID" ] || [ -z "$OLD_AWS_SECRET_ACCESS_KEY" ] \
   || [ -z "$OLD_DB_PASSWORD" ] || [ -z "$OLD_API_TOKEN" ]; then
  echo "[rotate_secrets] Credential extraction failed (config file format is not as expected)."
  exit 2
fi

echo "[rotate_secrets] Original credentials recovered (partially masked for reference):"
echo "                 AWS_ACCESS_KEY_ID     = ${OLD_AWS_ACCESS_KEY_ID:0:6}************"
echo "                 AWS_SECRET_ACCESS_KEY = ${OLD_AWS_SECRET_ACCESS_KEY:0:4}************************************"
echo "                 DB_PASSWORD           = ****************"
echo "                 API_TOKEN             = ${OLD_API_TOKEN:0:8}************"

PAYLOAD="$(printf '{"aws_access_key_id":"%s","aws_secret_access_key":"%s","db_password":"%s","api_token":"%s"}' \
  "$OLD_AWS_ACCESS_KEY_ID" "$OLD_AWS_SECRET_ACCESS_KEY" "$OLD_DB_PASSWORD" "$OLD_API_TOKEN")"

echo "[rotate_secrets] Calling the rotate API at $APP_URL ..."
RESP="$(curl -sS --max-time 15 -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" "$APP_URL")"
RC=$?

if [ $RC -ne 0 ] || [ -z "$RESP" ]; then
  echo "[rotate_secrets] Cannot connect to $APP_URL (rc=$RC). Check the network / app service."
  exit 3
fi

STATUS="$(echo "$RESP" | jq -r '.status // empty' 2>/dev/null)"
if [ "$STATUS" != "rotated" ]; then
  echo "[rotate_secrets] Rotate FAILED. Server response:"
  echo "$RESP" | jq . 2>/dev/null || echo "$RESP"
  exit 4
fi

ROTATE_FLAG="$(echo "$RESP" | jq -r '.rotate_flag // empty' 2>/dev/null)"
if [ -z "$ROTATE_FLAG" ]; then
  echo "[rotate_secrets] Rotate succeeded but no rotate-proof was received. Try again later."
  exit 5
fi

echo "$ROTATE_FLAG" > "$OUT_FILE"
echo "[rotate_secrets] ROTATE SUCCEEDED."
echo "                 - DB password and API token ON app have been replaced (old values are invalid)."
echo "                 - The fake AWS key ON storage has been disabled (mc admin user disable)."
echo "                 - Rotate-proof saved to: $OUT_FILE"
echo
echo "Verify it yourself: reuse the OLD AWS key to access storage; the request must be denied."
