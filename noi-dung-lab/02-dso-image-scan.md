# HƯỚNG DẪN THỰC HÀNH — Bảo mật Image Container: Săn Secret trong Layer & Quét lỗ hổng Image

**Học viện Công nghệ Bưu chính Viễn thông — SecLab PTIT**

**Mức độ:** Trung bình | **Phân loại:** DevSecOps / Container Security / Supply-chain Security

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `dso-image-scan` |
| **Mức độ** | Trung bình |
| **Công cụ sử dụng** | `docker` (history / save / inspect), `tar`, `grep`, `Trivy`, `dive` (tùy chọn), `jq`, `curl` |
| **Kiến thức yêu cầu** | Cơ bản về Docker (image, layer, container), dòng lệnh Linux, khái niệm CVE. Tất cả kiến thức nền được nhắc lại ở Mục 3 — bài độc lập, không cần làm bài nào trước. |

### Mục tiêu học tập
- Hiểu **cơ chế phân lớp (layer) của Docker image** và vì sao một secret "đã xóa" vẫn tồn tại vĩnh viễn trong lịch sử layer.
- Nắm được rủi ro **image supply-chain**: secret bị nhúng (hard-coded) và lỗ hổng thừa hưởng từ base image cũ.
- Biết cách **quét lỗ hổng image offline** bằng Trivy và đọc hiểu báo cáo CVE theo mức độ nghiêm trọng.
- Hiểu và áp dụng các **biện pháp hardening** cho quy trình build image theo OWASP DevSecOps và CIS Docker Benchmark.

### Kỹ năng đạt được
- Kỹ năng dùng `docker history` và giải nén image (`docker save` + `tar`) để **khảo cổ (forensics) từng layer**, trích xuất secret bị lộ lọt.
- Kỹ năng dùng **Trivy** để quét lỗ hổng ở cả chế độ image và filesystem, lọc theo severity.
- Kỹ năng **khai thác secret tìm được** để truy cập một dịch vụ nội bộ và lấy flag (tư duy attacker).
- Kỹ năng **viết lại Dockerfile an toàn**: multi-stage build, `.dockerignore`, base image tối giản/đã vá, pin version, không nhúng secret.
- Kỹ năng ánh xạ phát hiện vào khung **MITRE ATT&CK (Unsecured Credentials)** và **CIS Docker Benchmark**.

---

## 2. Kịch bản

### Tình huống
Sinh viên đóng vai một **DevSecOps engineer** của công ty được giao rà soát một Docker image nội bộ tên `internal-app:1.0` trước khi nó được đẩy lên registry sản xuất. Image này do một lập trình viên khác build vội. Có tin đồn rằng trong quá trình build, một tập tin cấu hình chứa khóa bí mật đã "vô tình bị commit rồi xóa đi", và image dùng một base image khá cũ.

Nhiệm vụ của sinh viên là **kiểm chứng các nghi ngờ đó bằng chứng cứ kỹ thuật**: soi lịch sử layer để moi secret còn sót, quét CVE để định lượng rủi ro, chứng minh secret thực sự "sống" bằng cách dùng nó truy cập một dịch vụ nội bộ (`vault-svc`) và lấy flag. Cuối cùng, với vai trò phòng thủ, sinh viên phải **viết lại Dockerfile theo hướng an toàn** và chứng minh bằng lần quét lại rằng lỗ hổng đã giảm.

### Vai trò của sinh viên
- Trên container `workstation` (nơi có sẵn Docker và image mẫu), thực hiện điều tra lịch sử layer của image.
- Giải nén image, trích xuất secret bị lộ trong layer trung gian.
- Quét lỗ hổng image bằng Trivy (offline), phân loại CVE nghiêm trọng.
- Dùng secret để xác thực tới dịch vụ `vault-svc` và lấy flag.
- Viết lại Dockerfile an toàn, build image mới và quét lại để đối chiếu.

### Sơ đồ mạng (mô tả text)

```
+-------------------------------------------------+
|  workstation  (172.60.2.10)                     |
|  - Docker engine (dockerd cục bộ)               |
|  - Image mẫu: internal-app:1.0 (đã nạp sẵn)     |
|  - Công cụ: docker, tar, trivy, jq, dive, curl  |
|  - DB Trivy offline: /root/.cache/trivy         |
|  (nơi sinh viên gõ toàn bộ lệnh)                 |
+-------------------------------------------------+
             |
             |  HTTP (dùng secret để xác thực)
             v
+-------------------------------------------------+
|  vault-svc  (172.60.2.20)                        |
|  - HTTP service nhỏ, cổng 8080                    |
|  - Xác thực bằng API key / AWS-like key giả       |
|  - Trả về flag khi key hợp lệ (/flag)             |
+-------------------------------------------------+
```

Luồng: `workstation` moi secret từ layer image → dùng secret gọi HTTP tới `vault-svc` → nhận flag. Đồng thời `workstation` quét CVE cục bộ (không cần Internet nhờ DB Trivy offline).

---

## 3. Kiến thức bổ trợ

### Kiến thức nền tảng

**Docker image & layer:** Một image gồm nhiều **layer** xếp chồng (union filesystem). Mỗi câu lệnh `RUN`/`COPY`/`ADD` trong Dockerfile tạo một layer mới, **chỉ ghi thêm (append-only)**. Vì vậy nếu một layer `COPY` một file secret vào rồi layer sau `RUN rm` xóa nó đi, file chỉ bị "che" ở layer cuối (whiteout) chứ **vẫn nằm nguyên trong layer trước**. Bất kỳ ai có image đều đọc lại được — đây là lỗi supply-chain kinh điển.

**Image supply-chain security:** Rủi ro phát sinh trong toàn bộ vòng đời image: base image chứa CVE, dependency lỗi thời, secret bị nhúng, image không được ký/kiểm chứng. Phòng thủ gồm quét (scan), tối giản bề mặt tấn công, pin version và không đưa secret vào image.

**Secret trong image:** Gồm API key, khóa AWS (dạng `AKIA...`), private key SSH/TLS, file `.env`, token. Không bao giờ được `COPY` vào image; phải nạp lúc runtime qua biến môi trường/secret manager hoặc Docker BuildKit secret mount.

**CVE & image scanning:** CVE là định danh chuẩn cho lỗ hổng đã công bố. Trình quét như **Trivy** so khớp danh sách gói (OS packages + thư viện ngôn ngữ) trong image với cơ sở dữ liệu lỗ hổng, xếp hạng theo severity (LOW/MEDIUM/HIGH/CRITICAL). Trivy có thể chạy **offline** nếu DB lỗ hổng đã được nạp sẵn vào cache.

**Multi-stage build & hardening:** Kỹ thuật dùng nhiều `FROM` trong một Dockerfile: stage "builder" chứa toolchain/nguồn, stage cuối chỉ `COPY` artifact cần thiết sang base image tối giản (vd `distroless`/`alpine` vá mới). Nhờ đó secret và công cụ build **không lọt vào image cuối**. `.dockerignore` chặn file nhạy cảm bị đưa vào build context.

### Thành phần cần quan sát trong bài lab

| Thành phần | Vai trò |
|---|---|
| Image `internal-app:1.0` | Image mẫu cần rà soát; chứa secret trong layer trung gian và base image cũ nhiều CVE. |
| `docker history` output | Lịch sử các layer + câu lệnh tạo ra chúng; manh mối layer nào đã `COPY` secret. |
| Các file `layer.tar` (sau `docker save`) | Nội dung thực của từng layer; nơi moi được file secret dù đã bị "xóa". |
| Secret bị lộ (API key / AWS key / `.env` / private key) | Bằng chứng lộ lọt; dùng để xác thực tới `vault-svc`. |
| Báo cáo Trivy | Danh sách CVE theo severity, chỉ ra rủi ro từ base image cũ. |
| Dịch vụ `vault-svc` (172.60.2.20:8080) | Nơi dùng secret để lấy flag. |
| Dockerfile hardened + image mới | Sản phẩm phòng thủ; quét lại phải cho kết quả cải thiện. |

### Bảng công cụ & cú pháp

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `docker` | `docker images` | Liệt kê các image có sẵn trên máy. |
| `docker` | `docker history --no-trunc <image>` | Hiện đầy đủ câu lệnh tạo từng layer (không cắt chuỗi) — tìm layer nghi ngờ. |
| `docker` | `docker inspect <image>` | Xem metadata image (ENV, labels, cấu hình) — có thể lộ secret trong biến môi trường. |
| `docker` | `docker save <image> -o <file>.tar` | Xuất toàn bộ image ra một file tar để giải nén offline. |
| `tar` | `tar -xf <file>.tar -C <dir>` | Giải nén archive image; bên trong có nhiều thư mục layer chứa `layer.tar`. |
| `tar` | `tar -tf <layer>.tar \| grep <keyword>` | Liệt kê nội dung một layer và lọc theo tên file (vd `.env`, `.pem`). |
| `grep` | `grep -rniE "AKIA\|api[_-]?key\|BEGIN.*PRIVATE" <dir>` | Quét đệ quy tìm mẫu secret trong các file đã giải nén. |
| `Trivy` | `trivy image --offline-scan <image>` | Quét CVE của image, dùng DB cache offline (không gọi mạng). |
| `Trivy` | `trivy image --severity HIGH,CRITICAL <image>` | Chỉ hiển thị lỗ hổng mức cao/nghiêm trọng. |
| `Trivy` | `trivy image --scanners secret <image>` | Bật bộ dò secret tích hợp của Trivy trên image. |
| `Trivy` | `trivy fs <dir>` | Quét lỗ hổng/secret trên một thư mục đã giải nén (filesystem scan). |
| `dive` | `dive <image>` | (Tùy chọn) Duyệt tương tác từng layer, xem file được thêm/xóa ở mỗi layer. |
| `jq` | `jq '.' manifest.json` | Đọc manifest image (thứ tự layer) sau khi giải nén. |
| `curl` | `curl -H "Authorization: Bearer <key>" http://<IP>:8080/flag` | Gửi request kèm secret để lấy flag từ `vault-svc`. |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-image-scan.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer dso-image-scan
```

(Chú ý: sinh viên sử dụng **mã sinh viên** của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm.)

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy `workstation` — nơi có sẵn Docker, image mẫu `internal-app:1.0` và các công cụ quét.

---

### Nhiệm vụ 1 — `inspect_layers`: Điều tra lịch sử layer của image

**Mục tiêu:** Xác định image mẫu và dùng `docker history` để tìm layer khả nghi từng đưa secret vào image, đồng thời nhận diện base image cũ.

**Bước 1:** Liệt kê các image hiện có và xác nhận image mẫu:
```bash
docker images
```

**Bước 2:** Xem đầy đủ lịch sử các layer (không cắt chuỗi):
```bash
docker history --no-trunc internal-app:1.0
```
Quan sát các dòng có `COPY`/`ADD` đưa file vào, và dòng `RUN rm ...` xóa file ở layer sau — đây là dấu hiệu secret bị "xóa" nhưng vẫn còn trong layer trước.

**Bước 3:** Xem metadata và biến môi trường của image (một số secret có thể nằm ở `ENV`):
```bash
docker inspect internal-app:1.0 | jq '.[0].Config.Env, .[0].Config.Labels'
```

**Bước 4:** Ghi lại tên/ID base image và các câu lệnh layer đáng ngờ (file gì bị copy vào, ở layer thứ mấy).

**Điều kiện hoàn thành nhiệm vụ:** Sinh viên chạy được `docker history --no-trunc internal-app:1.0`, và chỉ ra được (ghi vào file `findings.txt` bằng `docker history ... > findings.txt`) ít nhất một câu lệnh layer `COPY`/`ADD` đã đưa file nhạy cảm vào image cùng câu lệnh `RM` che nó ở layer sau.

**Câu hỏi 1:** Vì sao việc thêm một câu lệnh `RUN rm secret.file` ở cuối Dockerfile **không** loại bỏ được secret khỏi image? Cơ chế layer nào của Docker gây ra điều này?

Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `extract_secret`: Giải nén layer và trích xuất secret bị lộ

**Mục tiêu:** Xuất image ra tar, giải nén từng layer và moi ra secret (API key / khóa AWS giả / `.env` / private key) còn sót trong layer trung gian.

**Bước 1:** Xuất image ra một archive tar:
```bash
docker save internal-app:1.0 -o image.tar
```

**Bước 2:** Giải nén archive vào một thư mục làm việc:
```bash
mkdir -p unpacked && tar -xf image.tar -C unpacked
ls unpacked
```

**Bước 3:** Đọc `manifest.json` / `index.json` để biết thứ tự các layer:
```bash
cat unpacked/manifest.json | jq '.'
```

**Bước 4:** Duyệt và liệt kê nội dung từng layer để tìm file nhạy cảm:
```bash
for L in $(find unpacked -name "layer.tar"); do echo "== $L =="; tar -tf "$L" | grep -Ei '\.env|\.pem|\.key|secret|credential'; done
```

**Bước 5:** Khi xác định được layer chứa secret, giải nén layer đó ra và đọc nội dung file:
```bash
mkdir -p layerdump && tar -xf unpacked/<layer_id>/layer.tar -C layerdump
grep -rniE "AKIA[0-9A-Z]{16}|api[_-]?key|-----BEGIN.*PRIVATE KEY-----|password" layerdump
```

**Bước 6 (thay thế nhanh):** Có thể dùng bộ dò secret của Trivy để đối chiếu:
```bash
trivy image --scanners secret internal-app:1.0
```

**Điều kiện hoàn thành nhiệm vụ:** Sinh viên trích xuất được **giá trị secret** (API key / AWS-like key) từ layer trung gian và lưu vào file `secret.txt`. Giá trị này khớp với secret hợp lệ mà `vault-svc` chấp nhận (dùng để chấm ở Nhiệm vụ 3).

**Câu hỏi 2:** Ngoài việc "xóa file ở layer sau", hãy nêu **hai cách đúng** để đưa secret vào quá trình build/chạy container mà không để nó lưu vĩnh viễn trong image. Kỹ thuật này ánh xạ tới mục nào của MITRE ATT&CK (gợi ý: Unsecured Credentials — T1552)?

Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `scan_and_pwn`: Quét CVE và dùng secret lấy flag

**Mục tiêu:** Định lượng rủi ro CVE của image (chứng minh base image cũ nguy hiểm) và dùng secret vừa moi được để truy cập `vault-svc` lấy flag.

**Bước 1:** Quét toàn bộ lỗ hổng image ở chế độ offline:
```bash
trivy image --offline-scan internal-app:1.0
```

**Bước 2:** Lọc chỉ các lỗ hổng nghiêm trọng và xuất báo cáo:
```bash
trivy image --offline-scan --severity HIGH,CRITICAL internal-app:1.0 > cve-report.txt
cat cve-report.txt
```
Ghi lại: base image tên/phiên bản gì, có bao nhiêu CVE CRITICAL, một CVE tiêu biểu (mã CVE-xxxx).

**Bước 3:** Dùng secret (API key/AWS-like key) tìm được ở Nhiệm vụ 2 để gọi dịch vụ `vault-svc` lấy flag:
```bash
curl -s -H "Authorization: Bearer <SECRET_KEY>" http://172.60.2.20:8080/flag
```
Nếu key hợp lệ, phản hồi sẽ chứa chuỗi **flag** của bài.

**Điều kiện hoàn thành nhiệm vụ:** (1) Sinh viên tạo được `cve-report.txt` chứa ít nhất một CVE mức CRITICAL/HIGH; và (2) truy cập `vault-svc` thành công, phản hồi chứa chuỗi flag đúng định dạng.

**Câu hỏi 3:** Trình bày chuỗi tấn công đầy đủ từ image tĩnh đến khi lấy flag. Vì sao một image có thể "vượt qua kiểm thử chức năng" nhưng vẫn là **rủi ro nghiêm trọng** về mặt bảo mật? Việc dùng base image cũ liên quan gì đến rủi ro CVE?

Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `harden_image`: Viết lại Dockerfile an toàn và quét đối chiếu (Phòng thủ / DevSecOps)

**Mục tiêu:** Với vai trò phòng thủ, khắc phục cả hai lỗ hổng (secret nhúng + base image cũ) bằng cách viết lại Dockerfile theo chuẩn hardening, build image mới và chứng minh cải thiện bằng lần quét lại.

**Bước 1:** Xem Dockerfile gốc kèm bộ mã nguồn mẫu đã cung cấp:
```bash
cat /root/app/Dockerfile
ls /root/app
```

**Bước 2:** Tạo `.dockerignore` để chặn file nhạy cảm lọt vào build context:
```bash
cat > /root/app/.dockerignore <<'EOF'
.env
*.pem
*.key
secrets/
.git
EOF
```

**Bước 3:** Viết lại Dockerfile theo hướng an toàn (đặt là `Dockerfile.secure`) áp dụng đồng thời:
- **Multi-stage build**: stage builder biên dịch/cài dependency, stage cuối chỉ `COPY` artifact.
- **Base image tối giản & đã vá**, **pin version cụ thể** (không dùng tag `latest`), ví dụ base image alpine phiên bản mới hoặc distroless.
- **Không `COPY` secret** vào image; secret nạp lúc runtime qua biến môi trường.
- Chạy bằng **user không phải root** (`USER appuser`).

Gợi ý khung:
```dockerfile
# ----- Stage 1: builder -----
FROM <base-builder-pinned> AS builder
WORKDIR /src
COPY <chỉ file nguồn cần thiết> .
RUN <build/cài dependency>

# ----- Stage 2: runtime tối giản -----
FROM <base-runtime-toi-gian-pinned>
RUN adduser -D appuser
WORKDIR /app
COPY --from=builder /src/<artifact> /app/
USER appuser
ENTRYPOINT ["<lệnh chạy app>"]
```

**Bước 4:** Build image mới từ Dockerfile an toàn:
```bash
docker build -f /root/app/Dockerfile.secure -t internal-app:secure /root/app
```

**Bước 5:** Quét đối chiếu image mới và kiểm chứng không còn secret:
```bash
trivy image --offline-scan --severity HIGH,CRITICAL internal-app:secure > cve-report-secure.txt
trivy image --scanners secret internal-app:secure
docker save internal-app:secure -o secure.tar && mkdir -p chk && tar -xf secure.tar -C chk
grep -rniE "AKIA[0-9A-Z]{16}|-----BEGIN.*PRIVATE KEY-----|password" chk || echo "NO SECRET FOUND"
```

**Điều kiện hoàn thành nhiệm vụ:** Sinh viên build thành công `internal-app:secure`; file `cve-report-secure.txt` cho thấy **số CVE HIGH/CRITICAL giảm rõ rệt** so với `cve-report.txt`; và lệnh grep secret trên image mới trả về `NO SECRET FOUND` (không còn secret trong bất kỳ layer nào). Dockerfile mới có multi-stage, base image pin version và `USER` không phải root.

**Câu hỏi 4:** Đối chiếu các thay đổi bạn thực hiện với **CIS Docker Benchmark** (ví dụ: không chạy bằng root, dùng image tin cậy/pin version, giảm bề mặt tấn công). Nêu tối thiểu ba mục CIS mà bản Dockerfile hardened của bạn đã thỏa mãn, và giải thích vì sao multi-stage build vừa giảm CVE vừa chống lộ secret.

Trả lời: _______________________________________

---

## Ánh xạ khung tham chiếu

| Phát hiện trong lab | Khung tham chiếu |
|---|---|
| Secret nhúng trong layer, dùng để truy cập dịch vụ | MITRE ATT&CK **T1552 — Unsecured Credentials** (T1552.001 Credentials In Files) |
| Quét CVE image trong pipeline | **OWASP DevSecOps Guideline** — Image/Dependency Scanning |
| Base image cũ, không pin version, chạy root | **CIS Docker Benchmark** (mục 4.x — Container Images & Build File) |
| Multi-stage build, minimal base, non-root, `.dockerignore` | Hardening theo OWASP DevSecOps + CIS |

---

## Ghi chú triển khai (cho người xây lab)

**Container cần dựng:**
- `workstation` (172.60.2.10): base có Docker-in-Docker (hoặc dockerd cục bộ), cài sẵn `trivy`, `jq`, `tar`, `dive` (tùy chọn), `curl`. Đây là container sinh viên thao tác.
- `vault-svc` (172.60.2.20): HTTP service nhỏ (Python Flask / busybox httpd) lắng nghe cổng 8080, chấp nhận header `Authorization: Bearer <key>`; nếu key khớp secret nhúng trong image thì trả về flag ở endpoint `/flag`.

**Image mẫu `internal-app:1.0` cần chuẩn bị (build sẵn khi đóng gói lab):**
- Dùng **base image cũ có CVE nghiêm trọng đã biết** (ví dụ một tag cũ của `node`/`python`/`debian` — chọn tag mà DB Trivy offline chắc chắn báo CRITICAL/HIGH).
- Trong Dockerfile mẫu: `COPY` một file secret (vd `.env` chứa API key + một khóa AWS-like `AKIA...` + một private key giả) vào một layer, rồi `RUN rm` ở layer sau — để secret còn trong layer trung gian.
- Giá trị secret hợp lệ phải **khớp** với key mà `vault-svc` kiểm tra.

**Nạp image mẫu:** Vì Labtainer chạy offline, nên đóng gói image mẫu dưới dạng tar (`docker save internal-app:1.0 -o internal-app.tar`) và `docker load` trong entrypoint/init của container `workstation`, HOẶC build image từ Dockerfile mẫu ngay lúc container khởi tạo (cần cache base image sẵn trong container).

**DB Trivy offline:** Nạp sẵn thư mục cache `/root/.cache/trivy` (chứa `db/trivy.db` và `metadata.json`) vào image `workstation` để `trivy image --offline-scan` chạy được không cần Internet. Cần cập nhật DB tại thời điểm đóng gói lab và ghi rõ ngày DB để kết quả CVE ổn định (tham số hóa để mỗi sinh viên vẫn thấy cùng bộ CVE).

**Flag & goals dự kiến:**
- `inspect_layers`: artifact = `findings.txt` chứa câu lệnh layer đáng ngờ.
- `extract_secret`: goal = giá trị secret trong `secret.txt` khớp secret chuẩn.
- `scan_and_pwn`: goal = flag lấy từ `vault-svc` (tham số hóa theo mã sinh viên) + tồn tại CVE CRITICAL trong `cve-report.txt`.
- `harden_image`: goal = image `internal-app:secure` build thành công + `cve-report-secure.txt` có số HIGH/CRITICAL nhỏ hơn báo cáo gốc + grep secret trả về rỗng.

**Điểm cần lưu ý về tài nguyên:**
- Docker-in-Docker hoặc dockerd trong container `workstation` là điểm nặng nhất — cần cấp thêm RAM/CPU cho VM Labtainer và bật privileged cho container này. Nếu DinD quá nặng, phương án nhẹ hơn: **không cần Docker chạy thật** mà cung cấp sẵn file `image.tar` để sinh viên `tar -xf` và `trivy image --input image.tar` / `trivy fs`, giảm phụ thuộc daemon (nên ghi rõ lựa chọn này khi triển khai).
- Kích thước image mẫu nên nhỏ gọn để tar không quá lớn khi phân phối qua `imodule`.
- Tham số hóa flag theo mã sinh viên; secret key có thể cố định (để trích xuất) nhưng flag trả về từ `vault-svc` nên khác nhau mỗi sinh viên.
