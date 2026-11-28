# BUILD NOTES - dso-supplychain-sca

Hai container: `dev` (terminal SV, co syft+trivy+DB offline+node/npm) va `appserver`
(khong terminal, chay vuln-notes Node.js cong 3000). Lo hong: `ejs@3.1.6 (CVE-2022-29078, RCE qua EJS template injection, va o 3.1.7+; nang len 3.1.10).
(CVE-2021-21315, command injection, va o 5.3.1; package 0-dependency nen va offline gon).

Flag `HASH_REPLACE` dat tai `appserver:/flag.txt` (qua `_system/flag.txt`). Khai thac:
chen ma qua EJS options; sao chep flag qua `/api/ping?host=` de `cp /flag.txt` sang thu muc tinh `public/`, roi
`curl` tai ve -> flag chac chan tra ve duoc (khong phu thuoc output cua ping).

Offline: trivy DB nap san (`--download-db-only`), bien TRIVY_* qua /etc/profile.d (vi
terminal SV mo bang `su -` lam mat ENV cua Dockerfile). npm cache nap san
systeminformation@5.3.1 + .npmrc prefer-offline de `npm install @5.3.1` chay offline.

Grader khong co jq -> pregrade dung grep/sed. SBOM dem thanh phan bang `grep -c '"purl"'`.
