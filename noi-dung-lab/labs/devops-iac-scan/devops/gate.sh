#!/bin/bash
set -u

PROJ="$HOME/iac-project"
CI_HOST="172.31.0.20"
CI_URL="http://${CI_HOST}:8000/gate"
FLAG_FILE="$HOME/flag.txt"

if [ ! -d "$PROJ" ]; then
  echo "[!] Project directory not found: $PROJ"
  exit 1
fi

TFFILES=$(cd "$PROJ" && ls *.tf 2>/dev/null)
if [ -z "$TFFILES" ]; then
  echo "[!] No *.tf files in $PROJ"
  exit 1
fi

TARBALL="$(mktemp /tmp/iac-XXXXXX.tar.gz)"
tar czf "$TARBALL" -C "$PROJ" $TFFILES

echo "[*] Sending Terraform code to CI quality gate: $CI_URL"
RESP="$(curl -s --max-time 90 -F "project=@${TARBALL}" "$CI_URL")"
rc=$?
rm -f "$TARBALL"

if [ $rc -ne 0 ] || [ -z "$RESP" ]; then
  echo "[!] Cannot connect to CI gate ($CI_URL)."
  echo "    Check: ping $CI_HOST ; make sure the ci container is running."
  exit 2
fi

echo "$RESP" | grep -v '^FLAG='

FLAGVAL="$(echo "$RESP" | sed -n 's/^FLAG=//p' | head -n1 | tr -d '\r\n ')"
if [ -n "$FLAGVAL" ]; then
  printf '%s\n' "$FLAGVAL" > "$FLAG_FILE"
  echo ""
  echo "[+] Flag saved to $FLAG_FILE"
  echo "    (value: $FLAGVAL )"
else
  echo ""
  echo "[i] Gate not passed - no flag yet. Fix the remaining HIGH/CRITICAL issues and run ~/gate.sh again"
fi
