# HƯỚNG DẪN THỰC HÀNH — Bảo mật Docker Image

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| Tên lab | `dso-image-scan` |
| Mức độ | Trung bình |
| Công cụ | Docker, Trivy, tar, jq, curl |

Mục tiêu: phân tích layer Docker image, phát hiện secret/CVE, lấy flag qua dịch vụ nội bộ và hardening image bằng multi-stage build, `.dockerignore` và non-root user.

## 2. Kịch bản

Sinh viên là DevSecOps engineer nhận image `internal-app:1.0`. Image từng COPY credential rồi xoá nó ở layer sau. Secret còn lại cho phép gọi `vault-svc`; chỉ `workstation` có terminal trên mạng Labtainer `172.36.0.0/24`.

## 3. Kiến thức bổ trợ

Layer Docker là bất biến: `RUN rm` chỉ che file ở layer mới, còn dữ liệu cũ vẫn có thể lấy qua `docker save`. Trivy quét CVE/secret trước production. Không đưa secret vào Dockerfile, build context hoặc ENV image; dùng secret manager hoặc BuildKit secret. Ánh xạ: MITRE T1552 và CIS Docker Benchmark.

## 4. Các nhiệm vụ của bài thực hành

Khởi động bằng `imodule https://github.com/ptit2026/pen_lab_2026/raw/refs/heads/main/dso-image-scan.tar`, sau đó `labtainer dso-image-scan`.

### Nhiệm vụ 1 — `inspect_layers`

Chạy `docker history --no-trunc internal-app:1.0 | tee ~/findings.txt`; xác định layer COPY/ADD credential và layer xoá file. Điều kiện: file có cả hai dấu vết. Câu hỏi: vì sao `RUN rm` không loại secret khỏi image?

### Nhiệm vụ 2 — `extract_secret`

Xuất image và giải nén từng layer:

```bash
docker save internal-app:1.0 -o ~/image.tar
mkdir -p ~/layers && tar -xf ~/image.tar -C ~/layers
cd ~/layers && for l in blobs/sha256/*; do tar -tf $l 2>/dev/null | grep -E '\.env|secrets' && echo "  <- $l"; done
```

Giải nén layer chứa credential (`cd ~/layers && tar -xf blobs/sha256/<layer> app/secrets/aws-credentials.txt`; layer có `.wh.` là layer xoá file), đọc `aws_access_key_id` và lưu đúng key vào `~/secret.txt` (một dòng). Điều kiện: key bắt đầu `AKIA`. Câu hỏi: nêu hai cách đưa secret vào build/runtime mà không lưu trong image.

### Nhiệm vụ 3 — `scan_cves`

Chạy `trivy image --offline-scan --severity HIGH,CRITICAL internal-app:1.0 | tee ~/cve-report.txt` (CSDL lỗ hổng đã được nạp sẵn, chạy offline). Điều kiện: báo cáo có HIGH/CRITICAL. Câu hỏi: vì sao CVE base image phải được xử lý cùng secret?

### Nhiệm vụ 4 — `get_flag`

Chạy `curl -s -H "Authorization: Bearer $(cat ~/secret.txt)" http://vault-svc:8080/flag | jq -r .flag | tee ~/flag_result.txt`. Điều kiện: flag đúng giá trị cá thể hoá. Câu hỏi: chuỗi tấn công từ image đến dữ liệu dịch vụ là gì?

### Nhiệm vụ 5 — `harden_image`

Mã nguồn sạch nằm ở `~/app-src/`. Tạo `~/Dockerfile.secure` (multi-stage, ít nhất hai `FROM`, chạy non-root, không COPY `.env`/`secrets`) và `~/.dockerignore` loại `.env` và `secrets/`, ví dụ:

```
*
!app-src/
.env
secrets/
```

Build và quét đối chiếu:

```bash
cd ~ && docker build --network none -f Dockerfile.secure -t internal-app:secure .
docker history internal-app:secure
trivy image --offline-scan --severity HIGH,CRITICAL internal-app:secure | tail -5
```

Điều kiện: Dockerfile và `.dockerignore` thỏa các tiêu chí. Câu hỏi: ba biện pháp này chặn các bước tấn công thế nào?

Sau khi hoàn thành, chạy `checkwork` để kiểm tra kết quả.

## 5. Ánh xạ khung tham chiếu

MITRE ATT&CK T1552; CIS Docker Benchmark; DevSecOps shift-left scanning.
