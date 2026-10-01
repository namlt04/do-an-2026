#!/bin/bash
: <<'END'
pregrade.sh — dso-secrets-git

Chay TRUOC khi cham diem (phia instructor/GRADE host), nhan:
  $1 = homedir  (thu muc goc noi framework thu thap artifact cua sinh vien)
  $2 = destdir  (thu muc con ung voi container GRADE_CONTAINER = dev)

Muc dich: doi chieu BANG CHUNG THAT thay vi chi tin loi sinh vien tu khai
(LAB-BUILD-RULES.md #4.4): kiem tra git history that, dem finding trong
gitleaks.json, so sanh credential trich xuat voi hang so noi bo (KHONG ship
cho sinh vien), kiem tra hook thuc thi... roi ghi tom tat vao
.local/result/pregrade_summary.txt de instr_config/results.config va
goals.config tham chieu.

Cac gia tri credential "goc" duoi day CHI dung o day (phia cham diem) de doi
chieu — day la file instructor-side, KHONG nam trong tar phat cho sinh vien.
PHAI khop dev/_bin/fixlocal.sh, app/app.py, storage/_bin/fixlocal.sh.
END

set -u

homedir=${1:-}
destdir=${2:-}

if [ -z "$homedir" ] || [ -z "$destdir" ]; then
  echo "[pregrade] thieu tham so homedir/destdir, bo qua."
  exit 0
fi

cd "$homedir/$destdir" 2>/dev/null || {
  echo "[pregrade] khong the cd vao $homedir/$destdir, bo qua."
  exit 0
}

OUTDIR=".local/result"
mkdir -p "$OUTDIR"
SUMMARY="$OUTDIR/pregrade_summary.txt"
: > "$SUMMARY"

# ---- Gia tri credential GOC (PHAI KHOP dev/_bin/fixlocal.sh, app/app.py, storage) ----
LEAK_AWS_ACCESS_KEY_ID="AKIAZ7Q2X8VNK4RPDLW3"
LEAK_AWS_SECRET_ACCESS_KEY="wWw0kQfZ9pL3xR7bN2sV6yH1tG4mD8cU5aJ0eKqP"
LEAK_DB_PASSWORD="S3cr3t-DB-Pw-2024!"
LEAK_API_TOKEN="app_tok_5f4e3d2c1b0a9988776655443322110f"
SENSITIVE_PATH="deploy/credentials.yaml"

# =============================================================================
# 1) RECON — doi chieu ADD_COMMIT / REMOVE_COMMIT sinh vien ghi trong
#    ~/recon_answers.txt voi git log THAT cua ~/repo (khong chi tin loi khai).
# =============================================================================
RECON=FAIL
if [ -f recon_answers.txt ] && [ -d repo/.git ]; then
  ADD_COMMIT=$(sed -n 's/^ADD_COMMIT=//p' recon_answers.txt | tr -d ' \t\r\n')
  REMOVE_COMMIT=$(sed -n 's/^REMOVE_COMMIT=//p' recon_answers.txt | tr -d ' \t\r\n')
  if [ -n "$ADD_COMMIT" ] && [ -n "$REMOVE_COMMIT" ]; then
    ADDED=$(git -C repo show --stat "$ADD_COMMIT" 2>/dev/null | grep -c "$SENSITIVE_PATH")
    REMOVED=$(git -C repo show --stat "$REMOVE_COMMIT" 2>/dev/null | grep -c "$SENSITIVE_PATH")
    if [ "${ADDED:-0}" -ge 1 ] && [ "${REMOVED:-0}" -ge 1 ] && [ "$ADD_COMMIT" != "$REMOVE_COMMIT" ]; then
      RECON=OK
    fi
  fi
fi
echo "RECON=$RECON" >> "$SUMMARY"

# =============================================================================
# 2) GITLEAKS — bao cao ton tai va co >=3 finding (dem so RuleID trong JSON).
# =============================================================================
GITLEAKS=FAIL
if [ -f gitleaks.json ]; then
  N=$(grep -c '"RuleID"' gitleaks.json 2>/dev/null)
  N=${N:-0}
  if [ "$N" -ge 3 ]; then
    GITLEAKS=OK
  fi
fi
echo "GITLEAKS=$GITLEAKS" >> "$SUMMARY"

# =============================================================================
# 3) CREDS — sinh vien trich xuat dung ca 4 gia tri credential vao
#    ~/secrets_found.txt (so sanh CHINH XAC voi hang so noi bo o tren).
# =============================================================================
CREDS=FAIL
if [ -f secrets_found.txt ]; then
  A=$(sed -n 's/^AWS_ACCESS_KEY_ID=//p' secrets_found.txt | tr -d '\r\n')
  B=$(sed -n 's/^AWS_SECRET_ACCESS_KEY=//p' secrets_found.txt | tr -d '\r\n')
  C=$(sed -n 's/^DB_PASSWORD=//p' secrets_found.txt | tr -d '\r\n')
  D=$(sed -n 's/^API_TOKEN=//p' secrets_found.txt | tr -d '\r\n')
  if [ "$A" = "$LEAK_AWS_ACCESS_KEY_ID" ] && [ "$B" = "$LEAK_AWS_SECRET_ACCESS_KEY" ] \
     && [ "$C" = "$LEAK_DB_PASSWORD" ] && [ "$D" = "$LEAK_API_TOKEN" ]; then
    CREDS=OK
  fi
fi
echo "CREDS=$CREDS" >> "$SUMMARY"

# =============================================================================
# 4) HOOK — pre-commit hook ton tai, co quyen thuc thi, va thuc su goi gitleaks.
# =============================================================================
HOOK=FAIL
HOOKFILE="repo/.git/hooks/pre-commit"
if [ -f "$HOOKFILE" ] && [ -x "$HOOKFILE" ] && grep -q "gitleaks" "$HOOKFILE" 2>/dev/null; then
  HOOK=OK
fi
echo "HOOK=$HOOK" >> "$SUMMARY"

echo "[pregrade] dso-secrets-git: RECON=$RECON GITLEAKS=$GITLEAKS CREDS=$CREDS HOOK=$HOOK"

#
# Giu lai hanh vi mac dinh cua template (xu ly firefox places.sqlite neu co,
# vo hai neu khong dung).
#
is_sqlite=$(which sqlite3 2>/dev/null)
if [ -n "$is_sqlite" ]; then
  here=$(pwd)
  places="$here"/.mozilla/firefox/*default/places.sqlite
  for fname in $(ls $places 2> /dev/null); do
    if [ -f "$fname" ]; then
      outpath="$here/.local/result"
      outfile="$outpath/moz_places.txt"
      mkdir -p "$outpath"
      sqlite3 "$fname" "SELECT moz_places.* FROM moz_places;" > "$outfile"
    fi
  done
fi
