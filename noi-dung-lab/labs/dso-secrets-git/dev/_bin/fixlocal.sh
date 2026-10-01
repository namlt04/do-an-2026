#!/bin/bash
#
# dso-secrets-git : dev/_bin/fixlocal.sh
# ----------------------------------------------------------------------------
# Chay SAU khi tham so hoa (parameterization) da hoan tat, voi quyen cua nguoi
# dung container (khong phai root). $1 = password, $2 = uid (khong dung o day
# vi khong can thao tac quyen root).
#
# Nhiem vu:
#   1. Dung mot Git repository "that" tai ~/repo, voi lich su commit trong do
#      mot file cau hinh (deploy/credentials.yaml) TUNG chua secret (AWS key
#      gia, DB password, API token) o mot commit qua khu, roi bi "git rm" o
#      commit sau -> KHONG con o HEAD nhung VAN nam trong history (CWE-798 /
#      MITRE T1552.001). Day la doi tuong chinh de sinh vien dao boi.
#   2. Cap quyen thuc thi cho ~/rotate_secrets.sh (file NAY moi la file sinh
#      vien nhin thay va chay - no KHONG chua secret dang plaintext, vi no tu
#      dao gia tri tu chinh ~/repo luc chay).
#
# QUAN TRONG (chong bypass): script nay nam trong _bin/, theo tai lieu thiet
# ke Labtainer thi moi noi dung trong _bin/ va _system/ KHONG duoc copy vao
# $HOME cua sinh vien (chi cac file/thu muc truc tiep duoi <container>/ moi
# xuat hien o ~). Vi vay cac hang so secret gia lap duoi day AN TOAN de dat
# ngay trong script nay: sinh vien khong co cach nao doc duoc noi dung file
# nay tu ben trong container (khong co lenh nao "cat ~/_bin/fixlocal.sh").
# Neu sau nay ai do doi kien truc va chuyen script nay ra ngoai <container>/
# (vi du dev/build_repo.sh) thi PHAI xoa moi gia tri secret plaintext khoi no,
# vi khi do no se lo ra o ~/build_repo.sh va pha vo toan bo Nhiem vu 1-3.
# ----------------------------------------------------------------------------
set -u

HOME_DIR="${HOME:-/home/ubuntu}"

# ==== LEAKED CREDENTIALS (tinh, PHAI KHOP CHINH XAC voi app/app.py va =======
# ====  storage/_bin/fixlocal.sh de chuoi khai thac thong suot)      ========
AWS_ACCESS_KEY_ID="AKIAZ7Q2X8VNK4RPDLW3"
AWS_SECRET_ACCESS_KEY="wWw0kQfZ9pL3xR7bN2sV6yH1tG4mD8cU5aJ0eKqP"
DB_USER="appuser"
DB_PASSWORD="S3cr3t-DB-Pw-2024!"
API_TOKEN="app_tok_5f4e3d2c1b0a9988776655443322110f"
# =============================================================================

REPO="$HOME_DIR/repo"
rm -rf "$REPO"
mkdir -p "$REPO"
cd "$REPO" || exit 1

git init -q
git config user.email "dev@corp.local"
git config user.name "Corp Dev Team"
git config commit.gpgsign false
git config advice.detachedHead false

commit() {  # commit <message> <iso-date>
  export GIT_AUTHOR_DATE="$2"
  export GIT_COMMITTER_DATE="$2"
  git add -A
  git commit -q -m "$1"
}

# ---- Commit 1: khoi tao ma nguon "sach" ----
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

# ---- Commit 2: noise ----
cat >> README.md <<'EOF'

## Chay local
    python3 src/app.py
EOF
commit "docs: them huong dan chay local" "2024-01-08T10:02:00"

# ---- Commit 3: noise ----
cat > src/health.py <<'EOF'
def healthcheck():
    return {"status": "ok"}
EOF
commit "feat: them endpoint healthcheck" "2024-01-11T14:20:00"

# ---- Commit 4: VO TINH commit file credential (SECRET LO O DAY) ----
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

# ---- Commit 5: noise (sau khi secret da vao history) ----
cat >> config/settings.ini <<'EOF'

[metrics]
enabled = true
EOF
commit "feat: bat metrics" "2024-01-18T09:31:00"

# ---- Commit 6: "GO" file credential khoi HEAD (nhung van con trong history) ----
git rm -q deploy/credentials.yaml
cat >> README.md <<'EOF'

## Bao mat
Credential da duoc chuyen sang secret manager. Khong luu trong repo.
EOF
commit "security: remove sensitive config from repo (moved to vault)" "2024-01-22T11:05:00"

# ---- (Tuy chon) mot nhanh phu de kiem tra ky nang --all cua sinh vien ----
git branch -q feature/backup-rotation 2>/dev/null || true

git checkout -q master 2>/dev/null || git checkout -q main 2>/dev/null || true

# Don dep bien nhay cam khoi moi truong shell hien tai (khong dung nua tu day)
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY DB_USER DB_PASSWORD API_TOKEN

# ---- Cap quyen thuc thi cho cac file cong cu sinh vien nhin thay o ~ ----
chmod +x "$HOME_DIR/rotate_secrets.sh" 2>/dev/null

echo "[fixlocal:dev] Repo git da san sang tai $REPO"
