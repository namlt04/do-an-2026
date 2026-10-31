#!/bin/bash
homedir=$1
destdir=$2
home="$homedir/$destdir"
out="$home/.local/result"
mkdir -p "$out"
proj="$home/vuln-notes"

if [ ! -s "$home/flag_loot.txt" ]; then printf 'NOTYET\n' > "$home/flag_loot.txt"; fi

ok_sbom=NO
sb="$proj/sbom.cdx.json"
if [ -s "$sb" ] && grep -q 'CycloneDX' "$sb" && [ "$(grep -o '"purl"' "$sb" | wc -l)" -gt 2 ]; then ok_sbom=OK; fi
echo "$ok_sbom" > "$out/sbom_ok.txt"

ok_scan=NO
rep="$proj/trivy-report.json"
if [ -s "$rep" ] && grep -q 'CVE-2022-29078' "$rep" && grep -qi '"ejs"' "$rep"; then ok_scan=OK; fi
echo "$ok_scan" > "$out/scan_ok.txt"

ok_rem=NO
lock="$proj/package-lock.json"
gate="$home/gate_result.txt"
ejsver=""
if [ -s "$lock" ]; then
    ejsver=$(grep -A2 '"ejs": {' "$lock" | grep -m1 '"version"' | sed 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/')
fi
if [ "$ejsver" = "3.1.10" ] && [ -s "$gate" ] && grep -q 'SCA gate PASSED' "$gate"; then ok_rem=OK; fi
echo "$ok_rem" > "$out/remediate_ok.txt"
