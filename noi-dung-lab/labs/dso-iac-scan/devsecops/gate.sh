#!/bin/bash
set -u

PROJ="$HOME/iac-project"
CI_HOST="172.31.0.20"
CI_URL="http://${CI_HOST}:8000/gate"
FLAG_FILE="$HOME/flag.txt"

if [ ! -d "$PROJ" ]; then
  echo "[!] Khong tim thay thu muc du an: $PROJ"
  exit 1
fi

TFFILES=$(cd "$PROJ" && ls *.tf 2>/dev/null)
if [ -z "$TFFILES" ]; then
  echo "[!] Khong co file *.tf trong $PROJ"
  exit 1
fi

TARBALL="$(mktemp /tmp/iac-XXXXXX.tar.gz)"
tar czf "$TARBALL" -C "$PROJ" $TFFILES

echo "[*] Gui bo ma Terraform toi CI quality gate: $CI_URL"
RESP="$(curl -s --max-time 90 -F "project=@${TARBALL}" "$CI_URL")"
rc=$?
rm -f "$TARBALL"

if [ $rc -ne 0 ] || [ -z "$RESP" ]; then
  echo "[!] Khong ket noi duoc toi CI gate ($CI_URL)."
  echo "    Kiem tra: ping $CI_HOST ; container ci dang chay."
  exit 2
fi

echo "$RESP" | grep -v '^FLAG='

FLAGVAL="$(echo "$RESP" | sed -n 's/^FLAG=//p' | head -n1 | tr -d '\r\n ')"
if [ -n "$FLAGVAL" ]; then
  printf '%s\n' "$FLAGVAL" > "$FLAG_FILE"
  echo ""
  echo "[+] Da luu flag vao $FLAG_FILE"
  echo "    (gia tri: $FLAGVAL )"
else
  echo ""
  echo "[i] Gate chua dat - chua co flag. Hay sua tiep cac loi HIGH/CRITICAL roi chay lai ~/gate.sh"
fi
