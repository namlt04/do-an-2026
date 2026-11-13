# HƯỚNG DẪN THỰC HÀNH — Lab 1: Quét bảo mật Infrastructure as Code (Terraform)

- **Mã lab:** `dso-iac-scan`
- **Mức độ:** 1/4 (Cơ bản)
- **Công cụ:** `terraform` (init/validate), `tfsec`, `trivy config`, `grep`, `git diff`
- **Kiến thức cần:** cú pháp Terraform cơ bản (block `resource`, `variable`), khái niệm Security Group / S3 / IAM, dòng lệnh Linux

> Guide này theo hướng **tư duy**: mỗi nhiệm vụ cho **mục tiêu + gợi ý + khung lệnh có chỗ trống `<...>`**. Bạn tự điền chỗ trống dựa trên gợi ý. Đáp án đầy đủ không có sẵn ở đây. Mức 1 là bài cơ bản nên khung lệnh gần như đầy đủ, mỗi lệnh chỉ thiếu một chỗ nhỏ.

## Bối cảnh
Bạn là DevSecOps engineer được giao review một bộ mã Terraform (VPC, Security Group, S3, EC2, IAM) do đội dev viết vội, chứa nhiều lỗi cấu hình. Chính sách công ty: **không được triển khai nếu còn lỗi HIGH/CRITICAL**. Bạn quét lỗi, sửa mã, rồi chứng minh bằng lần quét lại sạch để vượt cổng CI và nhận flag.

Bài này **phân tích tĩnh, offline**: không có AWS thật, không chạy `terraform apply`.

Sơ đồ: container `devsecops` (có terminal, mã Terraform ở `~/iac-project/`, script `~/gate.sh`) ──HTTP──► container `ci` (không có terminal, dịch vụ quality gate: tự quét lại mã bạn gửi và chỉ trả flag khi HIGH/CRITICAL = 0). Bạn chỉ thao tác trên `devsecops`.

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-iac-scan.tar
labtainer dso-iac-scan
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn).

---

## Nhiệm vụ 1 — Quét baseline và phân loại rủi ro
**Mục tiêu:** Tạo báo cáo quét ban đầu `~/baseline.json` và đếm được số lỗi theo từng mức độ (baseline phải có lỗi HIGH/CRITICAL > 0).

**Gợi ý tư duy:**
- Trước khi quét, hãy chắc mã hợp lệ: `terraform init` (không cần backend từ xa) rồi `terraform validate`.
- `tfsec` đọc mã Terraform và báo lỗi kèm **rule ID** và **mức độ**. Nó có thể xuất kết quả ra JSON bằng cặp cờ `--format` và `--out`.
- Trong file JSON, mỗi lỗi có trường `"severity"`. Bạn dùng `grep -o` rồi `sort | uniq -c` để đếm số lỗi mỗi mức.
- `trivy config` là công cụ thứ hai với bộ rule khác, dùng để đối chiếu.

**Khung lệnh (điền chỗ trống):**
```bash
cd ~/iac-project
ls -la
terraform init -backend=false
terraform validate
tfsec .
tfsec . --format json --out ~/<TÊN_FILE_BASELINE>
grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/baseline.json | sort | uniq -c
trivy config .
trivy config --severity <CÁC_MỨC_CẦN_LỌC> .
```
(Gợi ý chỗ trống: file báo cáo tên là `baseline.json`; chỉ lọc hai mức nghiêm trọng nhất, cách nhau bằng dấu phẩy.)

**Hoàn thành khi:** `~/baseline.json` tồn tại, bảng đếm severity hiện số HIGH/CRITICAL > 0, `terraform validate` báo hợp lệ.

**Câu hỏi:** Vì sao pipeline thường chạy nhiều hơn một công cụ quét (tfsec và trivy) thay vì tin tuyệt đối một công cụ? → Trả lời: ____

---

## Nhiệm vụ 2 — Sửa lỗi mạng (Security Group) và lưu trữ (S3)
**Mục tiêu:** Không còn lỗi HIGH/CRITICAL thuộc nhóm network (ingress mở 0.0.0.0/0 tới cổng nhạy cảm) và nhóm S3 (public / thiếu mã hóa).

**Gợi ý tư duy:**
- Tìm chỗ sai bằng `grep` với mẫu `0.0.0.0/0`. Cổng quản trị (22) và cơ sở dữ liệu (3306) **không bao giờ** nên mở cho cả Internet; hãy thu hẹp về dải nội bộ `10.0.0.0/16`. Egress cũng nên giới hạn trong VPC.
- Với S3, cần đủ 3 thứ: **chặn public access** (resource `aws_s3_bucket_public_access_block`, cả 4 cờ đều `true`), **mã hóa at-rest** (`aws_s3_bucket_server_side_encryption_configuration`, thuật toán `AES256`) và **versioning** bật `Enabled`. Xóa mọi `acl = "public-read"`.
- Sửa trực tiếp trong `network.tf` và `storage.tf` bằng editor (`nano`/`vim`).

**Khung lệnh (điền chỗ trống):**
```bash
grep -rniE "0.0.0.0/0" ~/iac-project
grep -niE "acl|public|encryption|versioning" ~/iac-project/storage.tf
nano ~/iac-project/network.tf     # sửa cidr_blocks của ingress 22 và 3306
nano ~/iac-project/storage.tf     # thêm/sửa các resource S3
```
Mẫu khối cần có (chỉ điền chỗ trống):
```hcl
# network.tf - mỗi cổng nhạy cảm
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["<DẢI_NỘI_BỘ>"]
}

# storage.tf
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = <true_hay_false>
  block_public_policy     = <true_hay_false>
  ignore_public_acls      = <true_hay_false>
  restrict_public_buckets = <true_hay_false>
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "<THUẬT_TOÁN_MÃ_HÓA>"
    }
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "<TRẠNG_THÁI>"
  }
}
```
Sau khi sửa, kiểm tra và xem thay đổi:
```bash
terraform validate
tfsec . --minimum-severity HIGH
git diff network.tf storage.tf
```

**Hoàn thành khi:** `tfsec` không còn lỗi HIGH/CRITICAL của nhóm network/storage, `terraform validate` hợp lệ, `git diff network.tf storage.tf` cho thấy thay đổi đã áp dụng.

**Câu hỏi:** Đồng nghiệp nói "cứ mở 0.0.0.0/0 cho tiện, app có mật khẩu rồi". Nêu ít nhất 2 lý do phản bác (gợi ý: bề mặt tấn công, brute-force, defense in depth). → Trả lời: ____

---

## Nhiệm vụ 3 — Loại bỏ secret hardcode và siết quyền IAM
**Mục tiêu:** Không còn secret ghi cứng trong mã và không còn IAM policy `Action:*` / `Resource:*`.

**Gợi ý tư duy:**
- Dùng `grep -r` (không phân biệt hoa thường) tìm các từ `password`, `secret`, `access_key` để lộ ra giá trị ghi cứng trong `variables.tf`.
- Cách đúng: **xóa `default`** chứa giá trị thật và đánh dấu biến là nhạy cảm (`sensitive = true`); giá trị thật sẽ truyền lúc chạy (biến môi trường `TF_VAR_...`), không nằm trong mã.
- IAM theo nguyên tắc **least privilege**: chỉ cho đúng hành động cần thiết (đọc/ghi object) trên đúng tài nguyên (bucket của ứng dụng), không dùng dấu `*`.

**Khung lệnh (điền chỗ trống):**
```bash
grep -rniE "password|secret|access_key" ~/iac-project
nano ~/iac-project/variables.tf
nano ~/iac-project/iam.tf
```
Mẫu khối cần có:
```hcl
# variables.tf - KHÔNG còn dòng default chứa giá trị thật
variable "db_password" {
  type      = string
  sensitive = <true_hay_false>
}

# iam.tf - trong policy
Effect   = "Allow"
Action   = ["s3:<HÀNH_ĐỘNG_ĐỌC>", "s3:<HÀNH_ĐỘNG_GHI>"]
Resource = ["arn:aws:s3:::${var.app_bucket_name}/*"]
```
(Gợi ý chỗ trống: hai hành động là `GetObject` và `PutObject`.)

Kiểm tra lại:
```bash
tfsec . --minimum-severity HIGH
git diff variables.tf iam.tf
```

**Hoàn thành khi:** `grep` không còn thấy giá trị bí mật thật, không còn lỗi HIGH/CRITICAL nhóm secret/IAM, biến nhạy cảm có `sensitive = true`.

**Câu hỏi:** Access key từng bị commit rồi xóa ở commit sau: vì sao chưa an toàn và cần làm thêm gì? → Trả lời: ____

---

## Nhiệm vụ 4 — Bật logging, quét lại và vượt cổng CI
**Mục tiêu:** `~/after.json` có **0 HIGH và 0 CRITICAL**, `~/gate.sh` báo vượt cổng và lưu flag vào `~/flag.txt`.

**Gợi ý tư duy:**
- Còn lại là nhóm **logging**: bật access logging cho bucket dữ liệu (`aws_s3_bucket_logging` trỏ tới bucket log riêng) và VPC flow log (`aws_flow_log` + log group + IAM role cho flow log). Đọc rule ID `tfsec` còn báo để biết còn thiếu gì, đừng đoán.
- Lỗi phụ có thể còn sót ở EC2: bắt buộc **IMDSv2** (`http_tokens`) và **mã hóa ổ root** (`encrypted`).
- Quét lại, so sánh baseline với after, rồi chạy `~/gate.sh`: script gửi mã sang container `ci`, dịch vụ đó tự quét độc lập và chỉ trả flag khi đạt 0 HIGH/CRITICAL.

**Khung lệnh (điền chỗ trống):**
```bash
cd ~/iac-project
nano logging.tf       # bật S3 access logging, flow log
nano compute.tf       # http_tokens = "<GIÁ_TRỊ_BẮT_BUỘC_IMDSv2>", encrypted = true
terraform validate
tfsec . --format json --out ~/<TÊN_FILE_SAU_KHI_SỬA>
grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/after.json | sort | uniq -c
echo "== BASELINE =="; grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/baseline.json | sort | uniq -c
echo "== AFTER =="; grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/after.json | sort | uniq -c
~/gate.sh
cat ~/flag.txt
```
(Gợi ý chỗ trống: file kết quả sau sửa tên `after.json`; IMDSv2 bắt buộc dùng giá trị `required`.)

**Hoàn thành khi:** `after.json` không còn HIGH/CRITICAL, `terraform validate` hợp lệ, `gate.sh` báo GATE PASSED và `~/flag.txt` có nội dung (chuỗi riêng của bạn).

**Câu hỏi:** Vì sao cổng đặt ở "0 HIGH/CRITICAL" chứ không phải "0 lỗi mọi mức"? Nêu một rủi ro nếu gate quá lỏng và một rủi ro nếu quá chặt. → Trả lời: ____

---

## Chấm điểm
```bash
checkwork dso-iac-scan
```
Đạt khi cả 4 mục tiêu = **Y**: `baseline_scan`, `fix_network_storage`, `fix_secret_iam`, `pass_gate`.

Bằng chứng hệ thống kiểm tra: `~/baseline.json` và lịch sử lệnh quét baseline (Nhiệm vụ 1); lịch sử `git diff network.tf storage.tf` cùng trạng thái mã đã sửa (Nhiệm vụ 2); `git diff variables.tf iam.tf` và mã không còn secret (Nhiệm vụ 3); `~/after.json` (0 HIGH/CRITICAL), cấu hình logging đã bật và `~/flag.txt` do `gate.sh` lưu (Nhiệm vụ 4).

> Gợi ý cuối: nếu một mục chưa Y, đọc lại **gợi ý tư duy** của nhiệm vụ tương ứng, chạy lại đúng lệnh bằng chứng (`tfsec`, `git diff`, `~/gate.sh`) rồi `checkwork` lại.
