#!/bin/bash
homedir=$1
destdir=$2
home="$homedir/$destdir"
out="$home/.local/result"
mkdir -p "$out"

if [ -s "$home/flag.txt" ]; then
    tr -d '\r\n ' < "$home/flag.txt" > "$home/flag.txt.norm" && mv "$home/flag.txt.norm" "$home/flag.txt"
else
    printf 'NOTYET\n' > "$home/flag.txt"
fi

ok_recon=NO
if [ -s "$home/recon.txt" ] && grep -qi 'list_secrets=yes' "$home/recon.txt" && grep -qi 'create_pods=yes' "$home/recon.txt"; then ok_recon=OK; fi
echo "$ok_recon" > "$out/recon_ok.txt"

ok_loot=NO
if [ -s "$home/loot.txt" ] && grep -qi 'legacy_api_key' "$home/loot.txt" && grep -qi 'S3cureDbP' "$home/loot.txt"; then ok_loot=OK; fi
echo "$ok_loot" > "$out/loot_ok.txt"

ok_harden=NO
if [ -s "$home/harden_verify.txt" ] && grep -qi 'list_secrets_after=no' "$home/harden_verify.txt"; then ok_harden=OK; fi
echo "$ok_harden" > "$out/harden_ok.txt"
