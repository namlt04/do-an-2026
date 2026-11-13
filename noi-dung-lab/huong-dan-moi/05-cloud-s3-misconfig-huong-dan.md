# HƯỚNG DẪN THỰC HÀNH — Lab 5: Khai thác cấu hình sai Object Storage (S3)

- **Mã lab:** `cloud-s3-misconfig`
- **Mức độ:** 2/4 (Trung bình)
- **Công cụ:** `aws-cli` (s3/s3api với `--endpoint-url`), `tar`, `grep`, `jq`
- **Kiến thức cần:** mô hình S3 (bucket/object/policy), truy cập ẩn danh vs có credential

> Guide này theo hướng **tư duy**: mỗi nhiệm vụ cho **mục tiêu + gợi ý + khung lệnh có chỗ trống `<...>`**. Bạn tự điền chỗ trống dựa trên gợi ý. Đáp án đầy đủ không có sẵn ở đây — hãy suy luận. Mức 2 nên khung lệnh gần đầy đủ.

## Bối cảnh
Công ty dùng object storage tương thích S3 (MinIO). Một bucket bị cấu hình cho **truy cập ẩn danh**. Bạn đóng vai người đánh giá: khai thác cấu hình sai để lấy flag, rồi khắc phục.

Sơ đồ: máy `client` (có terminal, `aws-cli`) ↔ `storage` (MinIO, `http://172.33.0.30:9000`), gồm bucket công khai `public-assets` và bucket riêng `secure-data` (chứa flag).

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/cloud-s3-misconfig.tar
labtainer cloud-s3-misconfig
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn).

---

## Nhiệm vụ 1 — Trinh sát truy cập ẩn danh
**Mục tiêu:** Liệt kê được toàn bộ object trong bucket công khai **mà không cần credential**.

**Gợi ý tư duy:**
- Bucket cấu hình sai thường bật `anonymous read`. `aws s3` có một cờ để **bỏ ký xác thực** (gửi request ẩn danh).
- Dùng `--endpoint-url` để trỏ tới MinIO thay vì AWS thật; dùng `--recursive` để thấy mọi object.

**Khung lệnh (điền chỗ trống):**
```bash
aws --endpoint-url <ENDPOINT_MINIO> s3 ls s3://<BUCKET_CÔNG_KHAI> --recursive --<CỜ_ẨN_DANH>
```
**Hoàn thành khi:** thấy danh sách object (có 1 file backup và vài file static).

**Câu hỏi:** Vì sao liệt kê được mà không có key? Cấu hình nào đã sai? → Trả lời: ____

---

## Nhiệm vụ 2 — Trích credential bị lộ trong backup
**Mục tiêu:** Tải file backup từ bucket công khai, giải nén, và **tìm cặp access key/secret key bị lộ** bên trong.

**Gợi ý tư duy:**
- File backup (`.tar.gz`) trong bucket public thường chứa file cấu hình (`.env`) với credential hardcode.
- Tải về bằng `aws s3 cp` (vẫn ẩn danh), giải nén bằng `tar`, rồi `grep` tìm biến chứa `KEY`/`SECRET`.

**Khung lệnh:**
```bash
mkdir -p ~/loot
aws --endpoint-url <ENDPOINT> s3 cp s3://<BUCKET_CÔNG_KHAI>/<ĐƯỜNG_DẪN_BACKUP> ~/loot/ --<CỜ_ẨN_DANH>
tar -xzf ~/loot/<FILE_BACKUP> -C ~/loot/
grep -E "<MẪU_TÌM_KEY>" ~/loot/<FILE_CẤU_HÌNH>
# Lưu lại 2 giá trị tìm được để dùng ở Nhiệm vụ 3:
echo -n "<ACCESS_KEY_TÌM_ĐƯỢC>" > ~/creds_access_key.txt
echo -n "<SECRET_KEY_TÌM_ĐƯỢC>" > ~/creds_secret_key.txt
```
**Hoàn thành khi:** `~/creds_access_key.txt` và `~/creds_secret_key.txt` chứa đúng credential lộ.

**Câu hỏi:** "Blast radius" là gì? Vì sao để credential trong backup public lại nguy hiểm? → ____

---

## Nhiệm vụ 3 — Dùng credential lộ lấy flag ở bucket riêng
**Mục tiêu:** Dùng credential vừa đào để **xác thực** và đọc flag trong bucket **private** `secure-data`.

**Gợi ý tư duy:**
- Nạp credential vào biến môi trường `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` để `aws` dùng khi xác thực (lần này **không** dùng cờ ẩn danh nữa).
- Tìm object flag trong bucket riêng rồi tải nội dung ra.

**Khung lệnh:**
```bash
export AWS_ACCESS_KEY_ID=$(cat ~/creds_access_key.txt)
export AWS_SECRET_ACCESS_KEY=$(cat ~/creds_secret_key.txt)
aws --endpoint-url <ENDPOINT> s3 ls s3://<BUCKET_RIÊNG> --recursive
aws --endpoint-url <ENDPOINT> s3 cp s3://<BUCKET_RIÊNG>/<ĐƯỜNG_DẪN_FLAG> ~/loot.txt
cat ~/loot.txt
```
**Hoàn thành khi:** `~/loot.txt` chứa flag (chuỗi hex riêng của bạn).

**Câu hỏi:** Vì sao bucket riêng vẫn bị đọc dù không public? → ____

---

## Nhiệm vụ 4 — Khắc phục (vai DevSecOps)
**Mục tiêu:** Chặn truy cập ẩn danh vào `public-assets` **và** bật versioning cho `secure-data`.

**Gợi ý tư duy:**
- Dùng credential quản trị cấp sẵn trong `~/hardening-admin.env` (không dùng credential lộ).
- Gỡ **bucket policy** công khai (đưa về private) và bật **versioning** bằng nhóm lệnh `aws s3api`.
- Sau đó kiểm chứng: liệt kê ẩn danh lại phải **bị từ chối (AccessDenied)**.

**Khung lệnh:**
```bash
export AWS_ACCESS_KEY_ID=$(grep '^AWS_ACCESS_KEY_ID=' ~/hardening-admin.env | cut -d= -f2)
export AWS_SECRET_ACCESS_KEY=$(grep '^AWS_SECRET_ACCESS_KEY=' ~/hardening-admin.env | cut -d= -f2)
aws --endpoint-url <ENDPOINT> s3api <LỆNH_GỠ_POLICY> --bucket <BUCKET_CÔNG_KHAI>
aws --endpoint-url <ENDPOINT> s3api <LỆNH_BẬT_VERSIONING> --bucket <BUCKET_RIÊNG> --versioning-configuration Status=Enabled
# Ghi lại kết quả kiểm chứng (để chấm điểm):
echo -n "<DENIED_HOẶC_ALLOWED>" > ~/harden_anon_status.txt
echo -n "<ENABLED_HOẶC_DISABLED>" > ~/harden_versioning_status.txt
```
**Hoàn thành khi:** anon = `DENIED`, versioning = `ENABLED`.

**Câu hỏi:** Versioning giúp phòng chống kiểu tấn công nào (gợi ý: ransomware/xoá dữ liệu)? → ____

---

## Chấm điểm
```bash
checkwork cloud-s3-misconfig
```
Đạt khi cả 5 mục tiêu = **Y**: `enum_anonymous`, `exfiltrate_backup`, `access_secure_bucket`, `harden_public_denied`, `harden_versioning_enabled`.

> Gợi ý cuối: nếu một mục chưa Y, đọc lại **gợi ý tư duy** của nhiệm vụ tương ứng và kiểm tra file bằng chứng bạn đã ghi (`~/creds_*.txt`, `~/loot.txt`, `~/harden_*_status.txt`).
