# HƯỚNG DẪN THỰC HÀNH — Lab 2: Bảo mật Docker Image (layer, secret, CVE)

- **Mã lab:** `dso-image-scan`
- **Mức độ:** 1/4 (Cơ bản)
- **Công cụ:** `docker` (history/save/build), `tar`, `trivy`, `curl`, `jq`
- **Kiến thức cần:** image Docker gồm nhiều layer bất biến, `Dockerfile` (FROM/COPY/RUN/USER), khái niệm CVE và secret bị lộ

> Guide này theo hướng **tư duy**: mỗi nhiệm vụ cho **mục tiêu + gợi ý + khung lệnh có chỗ trống `<...>`**. Mức 1 nên khung lệnh gần như đầy đủ, bạn chỉ cần điền **một chỗ nhỏ** dựa trên gợi ý. Đáp án đầy đủ không có sẵn ở đây.

## Bối cảnh
Bạn là DevSecOps engineer nhận image `internal-app:1.0`. Nhà phát triển từng COPY file credential vào image rồi xoá nó ở layer sau, tưởng rằng đã an toàn. Bạn sẽ kiểm tra lại, lấy secret, dùng nó gọi dịch vụ nội bộ, rồi vá image.

Sơ đồ: máy `workstation` (có terminal, `docker`, `trivy`) ↔ `vault-svc` (`http://vault-svc:8080`, dịch vụ nội bộ giữ flag, yêu cầu Bearer token).

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-image-scan.tar
labtainer dso-image-scan
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn).

---

## Nhiệm vụ 1 — Soi lịch sử layer của image
**Mục tiêu:** Xem từng bước build của `internal-app:1.0` và nhận ra layer **COPY credential** cùng layer **xoá file**.

**Gợi ý tư duy:**
- `docker history` liệt kê các lệnh đã tạo nên từng layer. Mặc định lệnh bị cắt ngắn; có một cờ để hiện **đầy đủ**.
- Tìm dòng có `COPY`/`ADD` liên quan `secrets` hoặc `.env`, và dòng `rm` ngay sau đó.

**Khung lệnh (điền chỗ trống):**
```bash
docker history --<CỜ_KHÔNG_CẮT_NGẮN> internal-app:1.0 | tee ~/findings.txt
```
**Hoàn thành khi:** `~/findings.txt` có nội dung và bạn chỉ ra được hai dấu vết (copy + xoá).

**Câu hỏi:** Vì sao `RUN rm` không loại bỏ được secret khỏi image? → Trả lời: ____

---

## Nhiệm vụ 2 — Lấy lại secret từ layer cũ
**Mục tiêu:** Xuất image ra file, giải nén các layer, tìm layer còn chứa `app/secrets/aws-credentials.txt`, đọc `aws_access_key_id` và lưu vào `~/secret.txt` (một dòng, đúng giá trị key).

**Gợi ý tư duy:**
- `docker save` đóng gói toàn bộ layer vào một file tar; mỗi layer là một tar nằm trong `blobs/sha256/`.
- Layer chứa file credential là layer cũ (trước khi bị xoá). Layer có tên `.wh.` chỉ là dấu "đã xoá".
- Key AWS dạng truy cập thường bắt đầu bằng `AKIA`.

**Khung lệnh:**
```bash
docker save internal-app:1.0 -o ~/image.tar
mkdir -p ~/layers && tar -xf ~/image.tar -C ~/layers
cd ~/layers
for l in blobs/sha256/*; do tar -tf "$l" 2>/dev/null | grep -q 'app/secrets/aws-credentials.txt' && echo "co trong: $l"; done
tar -xf blobs/sha256/<LAYER_TÌM_ĐƯỢC> app/secrets/aws-credentials.txt
cat app/secrets/aws-credentials.txt
echo -n "<ACCESS_KEY_TÌM_ĐƯỢC>" > ~/secret.txt
```
**Hoàn thành khi:** `~/secret.txt` chứa đúng một dòng key bắt đầu bằng `AKIA`.

**Câu hỏi:** Nêu hai cách đưa secret vào build/runtime mà không lưu trong image. → ____

---

## Nhiệm vụ 3 — Quét CVE bằng Trivy
**Mục tiêu:** Quét `internal-app:1.0` và ghi lại các lỗ hổng mức HIGH/CRITICAL.

**Gợi ý tư duy:**
- Lab không có Internet: dùng chế độ quét **offline** (CSDL lỗ hổng đã nạp sẵn).
- Lọc mức nghiêm trọng bằng `--severity`, liệt kê các mức cần xem, cách nhau dấu phẩy.

**Khung lệnh:**
```bash
trivy image --offline-scan --severity <CÁC_MỨC_CẦN_LỌC> internal-app:1.0 | tee ~/cve-report.txt
```
**Hoàn thành khi:** `~/cve-report.txt` có báo cáo với các lỗ hổng HIGH/CRITICAL.

**Câu hỏi:** Vì sao CVE của base image phải được xử lý cùng với secret bị lộ? → ____

---

## Nhiệm vụ 4 — Dùng key lộ để lấy flag
**Mục tiêu:** Dùng key ở Nhiệm vụ 2 làm Bearer token gọi `vault-svc` và lấy flag.

**Gợi ý tư duy:**
- Gửi header `Authorization: Bearer <token>` bằng `curl -H`; token lấy từ `~/secret.txt`.
- Endpoint trả JSON; dùng `jq` để rút đúng trường chứa flag.

**Khung lệnh:**
```bash
curl -s -H "Authorization: Bearer $(cat ~/secret.txt)" http://vault-svc:8080/<ĐƯỜNG_DẪN_FLAG> | jq -r .<TRƯỜNG_JSON> | tee ~/flag_result.txt
```
**Hoàn thành khi:** `~/flag_result.txt` chứa flag (chuỗi riêng của bạn, không phải thông báo lỗi).

**Câu hỏi:** Chuỗi tấn công từ image đến dữ liệu của dịch vụ là gì? → ____

---

## Nhiệm vụ 5 — Hardening image
**Mục tiêu:** Tạo `~/Dockerfile.secure` (multi-stage, ít nhất hai `FROM`, chạy non-root, không COPY `.env`/`secrets`) và `~/.dockerignore` loại `.env` và `secrets/`; build thành `internal-app:secure`.

**Gợi ý tư duy:**
- Mã nguồn sạch nằm ở `~/app-src/`. Stage 1 copy mã nguồn; stage 2 chỉ copy file cần chạy.
- Tạo user hệ thống không đặc quyền rồi chuyển sang nó bằng một chỉ thị Dockerfile (gợi ý: `USER`).
- `.dockerignore` kiểu allow-list: chặn tất cả (`*`), chỉ cho phép `app-src/`, và chặn rõ `.env`, `secrets/`.

**Khung lệnh:**
```bash
cat > ~/Dockerfile.secure <<'EOF'
FROM python:3.8.0-slim AS build
WORKDIR /src
COPY app-src/ /src/

FROM python:3.8.0-slim
WORKDIR /app
COPY --from=build /src/app.py /src/requirements.txt /app/
RUN useradd -r -u 10001 appuser && chown -R appuser /app
<CHỈ_THỊ_CHẠY_NON_ROOT> appuser
EXPOSE 5000
CMD ["python", "app.py"]
EOF
cat > ~/.dockerignore <<'EOF'
*
!app-src/
.env
secrets/
EOF
cd ~ && docker build --network none -f Dockerfile.secure -t internal-app:secure .
docker history internal-app:secure
trivy image --offline-scan --severity HIGH,CRITICAL internal-app:secure | tail -5
```
**Hoàn thành khi:** build thành công và `docker history internal-app:secure` không còn dấu vết credential.

**Câu hỏi:** Ba biện pháp (multi-stage, `.dockerignore`, non-root) chặn các bước tấn công thế nào? → ____

---

## Chấm điểm
```bash
checkwork dso-image-scan
```
Đạt khi cả 5 mục tiêu = **Y**: `inspect_layers`, `extract_secret`, `scan_cves`, `get_flag`, `harden_image`.

File bằng chứng: `~/findings.txt`, `~/secret.txt`, `~/cve-report.txt`, `~/flag_result.txt` (Nhiệm vụ 5 được kiểm tra qua `~/Dockerfile.secure` và `~/.dockerignore`).

> Gợi ý cuối: nếu một mục chưa Y, đọc lại **gợi ý tư duy** của nhiệm vụ tương ứng và kiểm tra file bằng chứng bạn đã ghi.
