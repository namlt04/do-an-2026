#!/bin/bash

homedir=$1
destdir=$2
cd "$homedir/$destdir" || exit 0
outdir="$homedir/$destdir/.local/result"
mkdir -p "$outdir"

case "$destdir" in
  *web*)    for k in discover_ssrf steal_via_ssrf harden_blocks_ssrf; do [ -f "$outdir/$k.ok" ] || echo NO > "$outdir/$k.ok"; done ;;
  *imds*)   [ -f "$outdir/imdsv2_enforced.ok" ] || echo NO > "$outdir/imdsv2_enforced.ok" ;;
  *client*) for k in loot_accesskey remediation_ok; do [ -f "$outdir/$k.ok" ] || echo NO > "$outdir/$k.ok"; done ;;
esac

if [[ "$destdir" == *"web"* ]] && [ -f "fetch.log" ]; then
    if grep -q '"internal": true' fetch.log && \
       grep '"internal": true' fetch.log | grep -q '"allowed": true'; then
        echo "YES" > "$outdir/discover_ssrf.ok"
    fi

    if grep -q 'security-credentials' fetch.log && \
       grep 'security-credentials' fetch.log | grep -q '"allowed": true'; then
        echo "YES" > "$outdir/steal_via_ssrf.ok"
    fi

    if grep -q '"allowed": false' fetch.log && \
       grep '"allowed": false' fetch.log | grep -qE 'meta-data|"host": *"imds"|169\.254\.169\.254|172\.34\.0\.40'; then
        echo "YES" > "$outdir/harden_blocks_ssrf.ok"
    fi
fi

if [[ "$destdir" == *"imds"* ]] && [ -f "imds_access.log" ]; then
    if grep -q '"status": 401' imds_access.log && \
       grep -q '"has_valid_token": true' imds_access.log; then
        echo "YES" > "$outdir/imdsv2_enforced.ok"
    fi
fi

if [[ "$destdir" == *"client"* ]]; then
    if [ -f "remediation.txt" ] && \
       grep -qi 'allowlist' remediation.txt && \
       grep -qi 'imdsv2' remediation.txt && \
       grep -qiE 'least[ -]privilege' remediation.txt; then
        echo "YES" > "$outdir/remediation_ok.ok"
    fi

    if [ -f "creds.txt" ] && grep -q 'AccessKeyId' creds.txt; then
        echo "YES" > "$outdir/loot_accesskey.ok"
    fi
fi

exit 0
