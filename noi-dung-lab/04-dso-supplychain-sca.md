# Bảo mật chuỗi cung ứng phần mềm — Software Composition Analysis (SCA) & SBOM

**Mức độ:** Trung bình  |  **Phân loại:** DevSecOps / Supply Chain Security / Container

> Ánh xạ khung tham chiếu: **OWASP Top 10 — A06:2021 Vulnerable & Outdated Components**, **OWASP DevSecOps Guideline** (Software Composition Analysis, SBOM), **MITRE ATT&CK — T1195 Supply Chain Compromise**.

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `dso-supplychain-sca` |
| **Mức độ** | Trung bình |
| **Công cụ sử dụng** | `syft` (sinh SBOM), `trivy` (SCA/quét lỗ hổng, DB offline), `grype` (tùy chọn), `npm audit`, `curl`, `jq`, `git` |
| **Kiến thức yêu cầu** | Kiến thức cơ bản về dòng lệnh Linux; hiểu sơ lược một ứng dụng web (client/server, HTTP request/response); khái niệm "thư viện phụ thuộc" (dependency) và trình quản lý gói (npm/pip). Bài **độc lập**, mọi khái niệm cốt lõi được nhắc lại ở mục 3. |

**Mục tiêu học tập**
- Hiểu khái niệm **chuỗi cung ứng phần mềm (software supply chain)** và vì sao thư viện phụ thuộc bên thứ ba là bề mặt tấn công lớn (OWASP A06, MITRE T1195).
- Biết cách sinh **SBOM (Software Bill of Materials)** theo chuẩn CycloneDX/SPDX bằng Syft/Trivy để có "danh mục vật liệu" đầy đủ của ứng dụng.
- Thực hiện **Software Composition Analysis (SCA)**: quét mã nguồn/lockfile để phát hiện phụ thuộc chứa CVE đã biết.
- Chứng minh hậu quả thực tế: **khai thác** một CVE của phụ thuộc trên ứng dụng đang chạy để lấy flag.
- Áp dụng tư duy DevSecOps: **khắc phục (remediation)** bằng nâng cấp/ghim phiên bản an toàn và tích hợp cổng quét (security gate) vào pipeline.

**Kỹ năng đạt được**
- Kỹ năng sinh và đọc SBOM (CycloneDX JSON), đối chiếu thành phần với cơ sở dữ liệu lỗ hổng.
- Kỹ năng dùng `trivy fs` (chế độ offline) và `npm audit` để lọc, xếp hạng phụ thuộc theo mức độ nghiêm trọng (severity) và số CVE.
- Kỹ năng xác định **package + phiên bản + CVE** cụ thể là nguyên nhân gốc, đọc CVSS và đường tấn công.
- Kỹ năng khai thác một lỗ hổng phụ thuộc (ví dụ chèn lệnh/deserialization) qua HTTP để chiếm quyền thực thi trên máy chủ.
- Kỹ năng vá lỗ hổng theo hướng dịch chuyển sang trái (shift-left): pin phiên bản trong lockfile, cấu hình quét chặn build khi có lỗ hổng nghiêm trọng.

---

## 2. Kịch bản

**Tình huống:**
Sinh viên là một kỹ sư **DevSecOps** vừa tiếp nhận mã nguồn ứng dụng web nội bộ `vuln-notes` (một API ghi chú viết bằng Node.js) do một nhóm khác bàn giao. Ứng dụng được cài đặt "vội", `package.json` khai báo vài thư viện phụ thuộc đã **cũ và chưa vá**. Đội bảo mật yêu cầu sinh viên: lập danh mục thành phần (SBOM), quét phát hiện lỗ hổng phụ thuộc, và **chứng minh** rằng một trong các phụ thuộc đó có thể bị khai thác từ xa trên bản đang chạy (đóng vai attacker để lấy flag). Sau khi xác nhận rủi ro là thật, sinh viên chuyển vai phòng thủ: vá phụ thuộc và dựng cơ chế quét tự động chặn phiên bản có lỗ hổng.

**Vai trò của sinh viên:**
- Trên máy `dev`: sinh SBOM cho mã nguồn `vuln-notes` bằng Syft/Trivy và quét lỗ hổng phụ thuộc bằng Trivy (DB offline) và `npm audit`.
- Phân tích kết quả để chỉ đích danh **package + phiên bản + CVE** nguy hiểm nhất và hiểu cơ chế khai thác.
- Đóng vai attacker: gửi HTTP request khai thác CVE đó tới `appserver` để thực thi lệnh và đọc flag.
- Chuyển vai phòng thủ: nâng cấp/ghim phiên bản an toàn, quét lại chứng minh đã sạch, và cấu hình `trivy` làm **security gate** cho pipeline (thoát mã khác 0 khi còn lỗ hổng HIGH/CRITICAL).

**Sơ đồ mạng (mô tả text):**

```
+-----------------------------------+           +------------------------------------+
|  dev  (172.60.2.10)               |           |  appserver (172.60.2.20)           |
|-----------------------------------|   HTTP    |------------------------------------|
|  - Ma nguon vuln-notes/           |  cong     |  - vuln-notes dang CHAY (Node.js)  |
|  - syft, trivy (DB offline),      | ========> |  - Lang nghe API tren cong 3000    |
|    grype(tuy chon), npm audit,    |  curl     |  - Dung DUNG phien ban phu thuoc   |
|    curl, jq                       |           |    co lo hong nhu trong ma nguon   |
|  Noi sinh vien go lenh            |           |  - /flag hoac file flag tren may   |
+-----------------------------------+           +------------------------------------+
         |                                                        ^
         |  Phan tich SBOM + SCA (offline) tren dev               |
         +--------- Xac dinh CVE -> khai thac qua HTTP ------------+
```

Luồng: `dev` phân tích tĩnh (SBOM + SCA) mã nguồn cục bộ → chỉ ra CVE → dùng `curl` khai thác `appserver` đang chạy → lấy flag → quay lại `dev` để vá và dựng security gate.

---

## 3. Kiến thức bổ trợ

### Kiến thức nền tảng

- **Chuỗi cung ứng phần mềm (Software Supply Chain) & MITRE T1195:** một ứng dụng hiện đại chỉ có khoảng 10-20% mã do đội phát triển tự viết; phần còn lại là **thư viện phụ thuộc bên thứ ba** kéo về qua npm/pip/maven... Kẻ tấn công không cần lỗ hổng trong mã của bạn — chỉ cần một phụ thuộc (kể cả phụ thuộc *gián tiếp/transitive*) chứa lỗ hổng là đủ. Đây chính là kỹ thuật **Supply Chain Compromise (T1195)**.
- **OWASP A06:2021 — Vulnerable and Outdated Components:** hạng mục xếp việc dùng thành phần đã lỗi thời/chưa vá là một trong 10 rủi ro hàng đầu. Nguyên nhân phổ biến: không biết mình đang dùng phiên bản nào, không theo dõi CVE, ngại nâng cấp.
- **SCA (Software Composition Analysis):** kỹ thuật rà soát tự động toàn bộ phụ thuộc (trực tiếp + gián tiếp) của dự án, đối chiếu với cơ sở dữ liệu lỗ hổng (NVD/CVE, GitHub Advisory, OSV) để phát hiện thành phần dễ tổn thương. Điểm mấu chốt: SCA đọc **lockfile** (`package-lock.json`, `requirements.txt`...) nên thấy được cả phụ thuộc gián tiếp.
- **SBOM (Software Bill of Materials):** "danh mục vật liệu phần mềm" — liệt kê mọi thành phần, phiên bản, giấy phép, quan hệ phụ thuộc. Hai chuẩn phổ biến: **CycloneDX** và **SPDX**. SBOM là đầu vào để quét lỗ hổng lặp lại nhanh và để truy vết khi có CVE mới công bố (ví dụ khi Log4Shell nổ ra, ai có SBOM thì tra được ngay mình có bị ảnh hưởng không).
- **CVE / CVSS:** CVE là mã định danh một lỗ hổng công khai (ví dụ `CVE-YYYY-NNNNN`); CVSS là điểm số 0.0-10.0 phản ánh mức nghiêm trọng (LOW/MEDIUM/HIGH/CRITICAL). SCA dùng severity để ưu tiên vá.
- **DB offline của Trivy:** Trivy tải sẵn cơ sở dữ liệu lỗ hổng về dạng file; trong lab (không có Internet) DB được nạp trước để quét hoàn toàn cục bộ (`--offline-scan`, `--skip-db-update`).
- **Shift-left & Security Gate:** triết lý DevSecOps đưa việc kiểm tra bảo mật về sớm (trong lúc code/CI) thay vì kiểm sau khi đã lên production. **Security gate** là bước trong pipeline dùng mã thoát (exit code) của công cụ quét để **chặn build** khi còn lỗ hổng vượt ngưỡng.

### Thành phần cần quan sát trong bài lab

| Thành phần | Vai trò |
|---|---|
| `vuln-notes/package.json` & `package-lock.json` | Khai báo phụ thuộc trực tiếp và ghim toàn bộ cây phụ thuộc (kể cả gián tiếp) — đầu vào chính cho SCA. |
| SBOM (CycloneDX JSON) | Danh mục thành phần sinh bởi Syft/Trivy; dùng để đối chiếu và tra lỗ hổng. |
| Báo cáo Trivy / `npm audit` | Kết quả SCA: package, phiên bản đang dùng, phiên bản đã vá, CVE, severity. |
| Package + phiên bản dễ tổn thương | Phụ thuộc chứa CVE cho phép khai thác từ xa — mục tiêu cần chỉ đích danh. |
| `appserver` (cổng 3000) | Ứng dụng đang chạy dùng đúng phiên bản phụ thuộc có lỗ hổng — bề mặt để chứng minh khai thác. |
| flag | Chuỗi lấy được sau khi khai thác thành công CVE trên `appserver`. |
| Lockfile sau khi vá + cấu hình gate | Bằng chứng remediation: quét lại sạch và pipeline chặn được lỗ hổng. |

### Bảng tùy chọn và cú pháp công cụ sử dụng trong bài

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `syft` | `syft dir:<đường_dẫn> -o cyclonedx-json=<file>` | Sinh SBOM chuẩn CycloneDX (JSON) từ một thư mục mã nguồn. |
| `syft` | `syft dir:<đường_dẫn> -o spdx-json=<file>` | Sinh SBOM theo chuẩn SPDX (tùy chọn, để so sánh). |
| `trivy` | `trivy fs --scanners vuln --offline-scan --skip-db-update <đường_dẫn>` | Quét lỗ hổng phụ thuộc trên hệ thống tệp, hoàn toàn offline. |
| `trivy` | `trivy fs -f json -o <file> ...` | Xuất báo cáo quét ra JSON để lọc/xử lý bằng `jq`. |
| `trivy` | `trivy fs --severity HIGH,CRITICAL ...` | Chỉ hiển thị lỗ hổng mức HIGH và CRITICAL. |
| `trivy` | `trivy fs --exit-code 1 --severity HIGH,CRITICAL ...` | Trả về mã thoát 1 nếu còn lỗ hổng — dùng làm **security gate**. |
| `trivy` | `trivy sbom <sbom.json> --offline-scan --skip-db-update` | Quét lỗ hổng dựa trên SBOM đã sinh sẵn (thay vì quét lại mã nguồn). |
| `grype` | `grype sbom:<sbom.json>` | (Tùy chọn) Công cụ SCA thứ hai để đối chiếu chéo kết quả. |
| `npm audit` | `npm audit` / `npm audit --json` | Quét lỗ hổng theo dữ liệu advisory của npm dựa trên lockfile. |
| `npm` | `npm install <pkg>@<phiên_bản_an_toàn>` | Nâng cấp/ghim phiên bản phụ thuộc đã vá. |
| `jq` | `jq '.Results[].Vulnerabilities[]'` (lọc trường id/pkg/severity) | Lọc và định dạng báo cáo JSON của Trivy. |
| `curl` | `curl -s -X POST http://<IP>:3000/<path> -H 'Content-Type: application/json' -d '<payload>'` | Gửi request khai thác tới ứng dụng đang chạy. |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-supplychain-sca.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer dso-supplychain-sca
```

(chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm)

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy phân tích: `dev`. Mã nguồn ứng dụng nằm ở thư mục `~/vuln-notes`. Máy chủ ứng dụng `appserver` (172.60.2.20) đã chạy sẵn ứng dụng trên cổng 3000.

---

### Nhiệm vụ 1 — `generate_sbom`: Sinh SBOM và lập danh mục thành phần

**Mục tiêu:** Tạo bức tranh đầy đủ về mọi thư viện phụ thuộc của `vuln-notes` — bước nền tảng của quản trị chuỗi cung ứng.

**Bước 1:** Vào thư mục mã nguồn và xem khai báo phụ thuộc trực tiếp:
```bash
cd ~/vuln-notes
cat package.json
```

**Bước 2:** Sinh SBOM chuẩn CycloneDX bằng Syft:
```bash
syft dir:. -o cyclonedx-json=sbom.cdx.json
```

**Bước 3:** Đếm tổng số thành phần (gồm cả phụ thuộc gián tiếp) trong SBOM:
```bash
jq '.components | length' sbom.cdx.json
```

**Bước 4:** Liệt kê tên + phiên bản từng thành phần để đối chiếu về sau:
```bash
jq -r '.components[] | "\(.name)@\(.version)"' sbom.cdx.json | sort | head -n 50
```

**Điều kiện hoàn thành nhiệm vụ:** Đã sinh được file `sbom.cdx.json` hợp lệ (định dạng CycloneDX), và liệt kê được danh sách thành phần kèm phiên bản (số thành phần > số phụ thuộc khai báo trực tiếp trong `package.json`, cho thấy có phụ thuộc gián tiếp).

**Câu hỏi 1:** Vì sao số thành phần trong SBOM lại nhiều hơn số phụ thuộc khai báo trực tiếp trong `package.json`? Điều này nói lên rủi ro gì đối với việc chỉ rà soát các thư viện "mình chủ động cài"?

Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `scan_dependencies`: Quét SCA và xác định CVE nguy hiểm

**Mục tiêu:** Dùng SCA để phát hiện phụ thuộc chứa lỗ hổng, xếp hạng theo mức nghiêm trọng và chỉ đích danh **package + phiên bản + CVE** là nguy cơ khai thác cao nhất.

**Bước 1:** Quét lỗ hổng phụ thuộc bằng Trivy ở chế độ hoàn toàn offline:
```bash
cd ~/vuln-notes
trivy fs --scanners vuln --offline-scan --skip-db-update .
```

**Bước 2:** Lọc riêng các lỗ hổng mức HIGH và CRITICAL và xuất JSON để xử lý:
```bash
trivy fs --scanners vuln --offline-scan --skip-db-update \
  --severity HIGH,CRITICAL -f json -o trivy-report.json .
```

**Bước 3:** Trích danh sách CVE, tên package, phiên bản đang dùng và phiên bản đã vá:
```bash
jq -r '.Results[].Vulnerabilities[]? | "\(.Severity)\t\(.PkgName)@\(.InstalledVersion)\t\(.VulnerabilityID)\tfixed:\(.FixedVersion)"' trivy-report.json | sort
```

**Bước 4:** Đối chiếu bằng công cụ thứ hai (`npm audit`) để tăng độ tin cậy:
```bash
npm audit || true
```

**Bước 5 (tùy chọn):** Quét chéo bằng grype dựa trên SBOM đã có ở Nhiệm vụ 1:
```bash
grype sbom:sbom.cdx.json
```

**Bước 6:** Chọn ra một CVE **cho phép thực thi mã/lệnh từ xa** (RCE / injection / deserialization / prototype pollution) — đây sẽ là mục tiêu khai thác ở Nhiệm vụ 3. Ghi lại chính xác: tên package, phiên bản đang dùng, mã CVE.

**Điều kiện hoàn thành nhiệm vụ:** Đã tạo được `trivy-report.json` chứa ít nhất một lỗ hổng mức HIGH/CRITICAL; sinh viên xác định đúng **tên package + phiên bản đang dùng + mã CVE** của phụ thuộc dễ tổn thương dẫn tới thực thi mã từ xa (đối chiếu khớp giữa Trivy và `npm audit`/grype).

**Câu hỏi 2:** Trong báo cáo có thể có nhiều CVE. Sinh viên dựa trên những tiêu chí nào (severity/CVSS, có mã khai thác công khai, phụ thuộc có nằm trên đường đi của request người dùng hay không...) để ưu tiên xử lý một CVE trước các CVE khác?

Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `exploit_dependency`: Khai thác lỗ hổng phụ thuộc và lấy flag

**Mục tiêu:** Chứng minh hậu quả thực tế — dùng CVE đã xác định ở Nhiệm vụ 2 để khai thác `appserver` (172.60.2.20) đang chạy và đọc flag. Điều này chứng tỏ một phụ thuộc dễ tổn thương gây hậu quả thật chứ không chỉ là cảnh báo trên giấy.

**Bước 1:** Xác nhận ứng dụng đang chạy và khảo sát các endpoint:
```bash
curl -s http://172.60.2.20:3000/ | head
```

**Bước 2:** Dựa trên CVE đã chọn, dựng payload khai thác gửi qua HTTP. Điền endpoint/tham số dễ tổn thương và payload phù hợp với cơ chế lỗ hổng (ví dụ: chèn tham số kích hoạt lỗ hổng của phụ thuộc để thực thi lệnh trên server):
```bash
curl -s -X POST http://172.60.2.20:3000/<endpoint_dễ_tổn_thương> \
  -H 'Content-Type: application/json' \
  -d '<payload_khai_thác_kích_hoạt_CVE>'
```

**Bước 3:** Thông qua khả năng thực thi lệnh vừa đạt được, đọc file flag trên `appserver`:
```bash
# Vi du chen lenh doc flag qua chuoi khai thac (dieu chinh theo co che CVE):
curl -s -X POST http://172.60.2.20:3000/<endpoint_dễ_tổn_thương> \
  -H 'Content-Type: application/json' \
  -d '<payload_thực_thi: cat /flag.txt>'
```

**Bước 4:** Trích chuỗi flag từ phản hồi (dùng `jq`/`grep` nếu cần) và lưu lại để nộp.

**Điều kiện hoàn thành nhiệm vụ:** Gửi thành công request khai thác tới `appserver`, thực thi được lệnh trên máy chủ thông qua phụ thuộc dễ tổn thương, và thu được chuỗi flag đúng định dạng của bài (chuỗi flag xuất hiện trong stdout/lịch sử lệnh trên `dev`).

**Câu hỏi 3:** Vì sao một lỗ hổng chỉ nằm trong một **thư viện phụ thuộc** (không phải trong mã do đội phát triển tự viết) lại có thể dẫn tới chiếm quyền thực thi trên máy chủ? Hãy liên hệ với kỹ thuật **Supply Chain Compromise (MITRE T1195)**.

Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `remediate_and_gate`: Vá phụ thuộc và dựng cổng quét trong pipeline

**Mục tiêu:** Chuyển sang vai phòng thủ (DevSecOps). Nâng cấp/ghim phiên bản an toàn của phụ thuộc, quét lại chứng minh đã sạch, và cấu hình một **security gate** để pipeline tự động chặn khi còn lỗ hổng nghiêm trọng.

**Bước 1:** Nâng cấp package dễ tổn thương lên phiên bản đã vá (`FixedVersion` lấy ở Nhiệm vụ 2), ghim chính xác trong lockfile:
```bash
cd ~/vuln-notes
npm install <tên_package>@<phiên_bản_đã_vá>
```

**Bước 2:** Quét lại để xác nhận CVE đã biến mất khỏi báo cáo:
```bash
trivy fs --scanners vuln --offline-scan --skip-db-update \
  --severity HIGH,CRITICAL .
```

**Bước 3:** Sinh lại SBOM sau khi vá và so sánh phiên bản của package đã nâng cấp:
```bash
syft dir:. -o cyclonedx-json=sbom-fixed.cdx.json
jq -r '.components[] | select(.name=="<tên_package>") | "\(.name)@\(.version)"' sbom-fixed.cdx.json
```

**Bước 4:** Dựng **security gate**: chạy Trivy với `--exit-code 1` để lệnh trả về mã thoát khác 0 khi còn lỗ hổng HIGH/CRITICAL (đây là cách CI chặn build). Sau khi đã vá, lệnh này phải trả về mã thoát 0:
```bash
trivy fs --scanners vuln --offline-scan --skip-db-update \
  --severity HIGH,CRITICAL --exit-code 1 .
echo "Ma thoat cua security gate: $?"
```

**Bước 5:** Ghi một script gate tối giản (`scan-gate.sh`) mô phỏng bước quét trong pipeline CI để tái sử dụng:
```bash
cat > scan-gate.sh <<'EOS'
#!/bin/bash
set -e
echo "[CI] Running SCA security gate..."
trivy fs --scanners vuln --offline-scan --skip-db-update \
  --severity HIGH,CRITICAL --exit-code 1 .
echo "[CI] SCA gate PASSED: khong con lo hong HIGH/CRITICAL."
EOS
chmod +x scan-gate.sh
./scan-gate.sh
```

**Điều kiện hoàn thành nhiệm vụ:** Package dễ tổn thương đã được nâng lên phiên bản đã vá (thể hiện trong lockfile/SBOM mới); lần quét lại của Trivy **không còn** CVE HIGH/CRITICAL đã khai thác; và lệnh security gate (`--exit-code 1`) trả về **mã thoát 0** (script `scan-gate.sh` chạy thành công, in dòng "SCA gate PASSED").

**Câu hỏi 4:** So với việc rà soát bảo mật thủ công sau khi ứng dụng đã lên production, việc đặt một security gate SCA ngay trong pipeline CI mang lại lợi ích gì (chi phí sửa lỗi, thời gian phát hiện, tính lặp lại)? Nêu một rủi ro/hạn chế của security gate tự động và cách giảm thiểu (ví dụ: false positive, dùng cơ chế ignore có kiểm soát như `.trivyignore`).

Trả lời: _______________________________________

---

## 5. Ghi chú triển khai (cho người xây lab)

**Container cần dựng (khai báo trong `start.config`, mạng ảo `172.60.2.0/24`):**
- `dev` — 172.60.2.10: nơi sinh viên gõ lệnh. Cài offline qua Dockerfile: `syft`, `trivy` (kèm DB lỗ hổng nạp sẵn), `grype` (tùy chọn), Node.js + `npm`, `jq`, `curl`, `git`. Mã nguồn `vuln-notes` đặt tại `~/vuln-notes` gồm `package.json` + `package-lock.json` ghim đúng phiên bản dễ tổn thương.
- `appserver` — 172.60.2.20: chạy `vuln-notes` (Node.js) trên cổng 3000, **dùng đúng phiên bản phụ thuộc có lỗ hổng** như trong mã nguồn trên `dev`. Đặt file flag (ví dụ `/flag.txt`) và endpoint dễ tổn thương để chuỗi khai thác đọc được flag.
- (Có thể gộp `dev` và `appserver` làm một nếu muốn giảm tài nguyên, nhưng tách ra minh họa rõ hơn luồng "phân tích trên máy dev — khai thác máy chủ đang chạy".)

**Cơ sở dữ liệu offline (quan trọng):**
- Trivy DB (`trivy-db`, và `trivy-java-db` nếu cần) phải được **tải trước lúc build image** và đặt vào cache (`~/.cache/trivy`); mọi lệnh quét trong lab dùng `--skip-db-update --offline-scan` để không cần Internet.
- Nếu dùng `grype`, nạp sẵn DB grype tương tự.
- `npm audit` cần dữ liệu advisory offline; nếu không thu xếp được registry/advisory offline, xem `npm audit` là bước phụ (đối chiếu) và ưu tiên Trivy làm nguồn chấm điểm chính; hoặc dựng một npm registry nội bộ (Verdaccio) trong container để phục vụ cài đặt/audit.

**Chọn package/CVE cụ thể (người xây lab quyết định 1 phương án, ghim phiên bản tương ứng):**
- Ưu tiên CVE có **PoC đơn giản, khai thác được qua một HTTP request** để phù hợp mức Trung bình. Gợi ý các dạng:
  - Node.js: một package RCE/command-injection cũ (ví dụ dạng thư viện xử lý ảnh/chuyển đổi gọi lệnh hệ thống, hoặc lỗ hổng deserialization/template injection), hoặc một chuỗi **prototype pollution** dẫn tới RCE.
  - (Phương án Python thay thế): app Flask/FastAPI dùng một package có CVE deserialization (ví dụ dòng PyYAML `load` không an toàn) — khi đó thay `npm audit` bằng `pip-audit`/`osv-scanner` và Trivy quét `requirements.txt`.
- Ghim **đúng phiên bản dễ tổn thương** trong lockfile để SCA phát hiện được, và bảo đảm `FixedVersion` có sẵn để Nhiệm vụ 4 nâng cấp offline (đưa cả phiên bản đã vá vào registry nội bộ/cache npm).

**Flag & goals dự kiến (chấm điểm tự động qua artifacts: stdout, bash history, file output):**
- `generate_sbom`: tồn tại `sbom.cdx.json` hợp lệ + `jq .components | length` > số dep trực tiếp.
- `scan_dependencies`: `trivy-report.json` chứa CVE mục tiêu; so khớp chuỗi `PkgName`/`VulnerabilityID` sinh viên nêu.
- `exploit_dependency`: chuỗi **flag** xuất hiện trong stdout/history trên `dev` (tham số hóa flag theo mã sinh viên để mỗi người một flag khác nhau).
- `remediate_and_gate`: lần quét lại không còn CVE mục tiêu (kiểm bằng grep báo cáo) + `scan-gate.sh` exit 0 (kiểm bằng lịch sử lệnh/`$?`).

**Lưu ý tài nguyên:** Trivy DB có thể vài trăm MB — cân nhắc dung lượng image. Toàn bộ công cụ đều nhẹ, chạy tốt trên một VM Labtainer. Cần bảo đảm giờ hệ thống trong container hợp lý để Trivy không cảnh báo DB hết hạn (có thể dùng cờ bỏ qua kiểm tra hạn DB nếu framework cho phép).
