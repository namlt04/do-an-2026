#!/bin/bash
set -u

HOME_DIR="${HOME:-/home/ubuntu}"

AWS_ACCESS_KEY_ID="AKIAZ7Q2X8VNK4RPDLW3"
AWS_SECRET_ACCESS_KEY="wWw0kQfZ9pL3xR7bN2sV6yH1tG4mD8cU5aJ0eKqP"
DB_USER="appuser"
DB_PASSWORD="S3cr3t-DB-Pw-2024!"
API_TOKEN="app_tok_5f4e3d2c1b0a9988776655443322110f"

REPO="$HOME_DIR/repo"
rm -rf "$REPO"
mkdir -p "$REPO"
cd "$REPO" || exit 1

git init -q
git config user.email "dev@corp.local"
git config user.name "Corp Dev Team"
git config commit.gpgsign false
git config advice.detachedHead false

commit() {
  export GIT_AUTHOR_DATE="$2"
  export GIT_COMMITTER_DATE="$2"
  git add -A
  git commit -q -m "$1"
}

mkdir -p src deploy config
cat > README.md <<'EOF'
# corp-backend

Backend service noi bo (payments + object storage sync).
Trien khai qua script trong thu muc deploy/.
EOF
cat > src/app.py <<'EOF'
import os

def get_config():
    # Doc cau hinh tu bien moi truong (chuan DevSecOps).
    return {
        "db_user": os.environ.get("DB_USER", ""),
        "db_password": os.environ.get("DB_PASSWORD", ""),
        "api_token": os.environ.get("API_TOKEN", ""),
    }

if __name__ == "__main__":
    print("corp-backend starting...")
EOF
cat > src/storage_sync.py <<'EOF'
import os

# Dong bo backup len object storage (S3-compatible).
S3_ENDPOINT = os.environ.get("S3_ENDPOINT", "http://storage:9000")
BUCKET = "corp-backups"
EOF
cat > config/settings.ini <<'EOF'
[app]
name = corp-backend
listen = 0.0.0.0:8080
log_level = info
EOF
cat > .gitignore <<'EOF'
__pycache__/
*.pyc
EOF
commit "Initial import of corp-backend service" "2024-01-05T09:14:00"

cat >> README.md <<'EOF'

## Chay local
    python3 src/app.py
EOF
commit "docs: them huong dan chay local" "2024-01-08T10:02:00"

cat > src/health.py <<'EOF'
def healthcheck():
    return {"status": "ok"}
EOF
commit "feat: them endpoint healthcheck" "2024-01-11T14:20:00"

cat > deploy/credentials.yaml <<EOF
# !! deploy config - do NOT share !!
# (Lap trinh vien vo tinh commit file nay)
aws:
  access_key_id: ${AWS_ACCESS_KEY_ID}
  secret_access_key: ${AWS_SECRET_ACCESS_KEY}
  region: ap-southeast-1
  endpoint: http://storage:9000
  bucket: corp-backups

database:
  host: db.internal.corp
  port: 5432
  username: ${DB_USER}
  password: ${DB_PASSWORD}

api:
  base_url: http://app:8080
  token: ${API_TOKEN}
EOF
commit "chore: add deployment credentials for staging" "2024-01-15T16:47:00"

cat >> config/settings.ini <<'EOF'

[metrics]
enabled = true
EOF
commit "feat: bat metrics" "2024-01-18T09:31:00"

git rm -q deploy/credentials.yaml
cat >> README.md <<'EOF'

## Bao mat
Credential da duoc chuyen sang secret manager. Khong luu trong repo.
EOF
commit "security: remove sensitive config from repo (moved to vault)" "2024-01-22T11:05:00"

git branch -q feature/backup-rotation 2>/dev/null || true

git checkout -q master 2>/dev/null || git checkout -q main 2>/dev/null || true

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY DB_USER DB_PASSWORD API_TOKEN

chmod +x "$HOME_DIR/rotate_secrets.sh" 2>/dev/null

echo "[fixlocal:dev] Repo git da san sang tai $REPO"
