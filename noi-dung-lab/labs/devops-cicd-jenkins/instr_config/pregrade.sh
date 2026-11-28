#!/bin/bash
homedir=$1
destdir=$2
home="$homedir/$destdir"
out="$home/.local/result"
mkdir -p "$out"

for f in flag_ci.txt regpass_loot.txt flag_pivot.txt; do
    if [ -s "$home/$f" ]; then
        tr -d '\r\n ' < "$home/$f" > "$home/$f.norm" && mv "$home/$f.norm" "$home/$f"
    else
        printf 'NOTYET\n' > "$home/$f"
    fi
done

ok_recon=NO
if [ -s "$home/recon.txt" ] && grep -qi 'build-app' "$home/recon.txt" && grep -qi 'jenkins' "$home/recon.txt"; then ok_recon=OK; fi
echo "$ok_recon" > "$out/recon_ok.txt"

ok_harden=NO
hv="$home/harden_verify.txt"
if [ -s "$hv" ] && grep -qE 'api_anonymous=(401|403)' "$hv" && grep -qE 'script_anonymous=(401|403)' "$hv"; then ok_harden=OK; fi
echo "$ok_harden" > "$out/harden_ok.txt"
