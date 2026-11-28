# BUILD NOTES - dso-waf-crs (Coraza)

Ba container, net 172.38.0.0/24: client (terminal SV: curl/nikto), waf (terminal
SV, reverse proxy Go nhung Coraza v3 + OWASP CRS, cong 80), webapp (khong terminal,
Flask app lo hong cong 8080 + dich vu issuer cong 8099 phat flag).

**Doi tu ModSecurity sang Coraza (2026-10-31):** tranh phai bien dich libmodsecurity
C++ (rat cham/OOM tren VM 3GB). Coraza v3 la engine WAF viet bang Go, DUNG CHUNG
SecLang + OWASP CRS nen bai hoc va cach cham GIU NGUYEN (SecRuleEngine On, exclusion
ctl:ruleRemoveTargetById, 403). WAF = 1 proxy Go nho (/opt/corazasrc/main.go) nhung
coraza/v3 + coraza/v3/http, nap directive tu /etc/coraza/main.conf (Include coraza.conf
-> crs-setup.conf -> custom-rules.conf -> crs/rules/*.conf). Build 1 lan luc build
bang Go 1.22.6 (go-ed sau khi build); runtime offline.

Config SV sua: /etc/coraza/coraza.conf (SecRuleEngine DetectionOnly->On) va
/etc/coraza/custom-rules.conf (exclusion), roi `sudo systemctl restart caddy`.

Flag: 3 flag HASH_REPLACE BARE, deu tren webapp (khong co shell). flag1 path
traversal truc tiep; flag2/flag3 do issuer (webapp:8099) phat sau khi TU PROBE
qua WAF thay dung end-state (403 cho tan cong, 200 cho request hop le). waf co
shell+sudo nen KHONG dat flag o day.

Cham/verify: solver chay tren client, dieu khien trang thai WAF qua helper wafctl
(waf:9091, /engine-on + /apply-exclusion -> sua /etc/coraza + restart caddy).
wafctl KHONG co trong guide; SV tu sua tay tren terminal waf. Grader chi grep/sed/awk.

Rui ro: (1) caddy v2.8.4 + coraza-caddy + CRS v4.10 phai tuong thich (CRS co test coraza - OK).
(2) go build can internet luc build (co). (3) Flag3: payload benign /feedback phai
403 TRUOC exclusion va 200 SAU, con XSS /feedback luon 403 - can test thuc te,
danh sach rule-id dong bo o wafctl.py va issuer.py.
