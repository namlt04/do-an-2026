#!/bin/bash
homedir=$1
destdir=$2
home="$homedir/$destdir"
out="$home/.local/result"
mkdir -p "$out"

if [ ! -s "$home/flag_result.txt" ]; then printf 'NOTYET\n' > "$home/flag_result.txt"; fi

ok_layers=NO
if [ -s "$home/findings.txt" ] && grep -qiE 'COPY|ADD' "$home/findings.txt" && grep -qiE 'RUN.*rm|rm ' "$home/findings.txt"; then ok_layers=OK; fi
echo "$ok_layers" > "$home/findings.txt"

ok_secret=NO
if [ -s "$home/secret.txt" ] && grep -q '^AKIA' "$home/secret.txt"; then ok_secret=OK; fi
echo "$ok_secret" > "$home/secret.txt"

ok_cve=NO
if [ -s "$home/cve-report.txt" ] && grep -qiE 'HIGH|CRITICAL' "$home/cve-report.txt"; then ok_cve=OK; fi
echo "$ok_cve" > "$home/cve-report.txt"

ok_harden=NO
f="$home/Dockerfile.secure"
di="$home/.dockerignore"
if [ -s "$f" ] && [ "$(grep -ci '^FROM ' "$f")" -ge 2 ] && grep -qi '^USER ' "$f" \
   && [ "$(grep -i '^USER ' "$f" | tail -1 | awk '{print $2}')" != "root" ] \
   && ! grep -qiE '^(COPY|ADD).*(\.env|secrets)' "$f" \
   && [ -s "$di" ] && grep -qE '^\.env' "$di" && grep -qE '^secrets' "$di"; then ok_harden=OK; fi
echo "$ok_harden" > "$out/harden_ok.txt"
