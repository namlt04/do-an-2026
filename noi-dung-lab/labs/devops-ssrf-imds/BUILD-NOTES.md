# BUILD-NOTES — cloud-ssrf-imds

> Ghi chú cho người build/test (khâu §7 LAB-BUILD-RULES.md). Bài này do subagent author; file này viết bổ sung sau khi rà soát (agent bị dừng nhầm trước khi kịp viết). Đã đối chiếu `config/*`, `instr_config/*`.

## 1. Kiến trúc & luồng
- 4 container trên `LAB_NET 172.34.0.0/24`:
  - `client` .10 — máy sinh viên (TERMINALS 1, GRADE_CONTAINER): curl, jq, aws-cli.
  - `web` .20 — Flask "imgproxy-portal" DÍNH SSRF (chức năng fetch URL), cổng 8080 (TERMINALS -1, SCRIPT NONE/systemd).
  - `imds` .40 — Flask giả lập Instance Metadata Service, cổng 80 (TERMINALS -1).
  - `storage` .30 — MinIO S3, cổng 9000 (TERMINALS -1).
- Luồng: SSRF trên `web` → ép web gọi `imds` đọc `/latest/meta-data/iam/security-credentials/<role>` → lấy credential tạm → dùng aws-cli (SigV4) truy cập bucket private `fin-reports` trên `storage` → tải `flag.txt`.

## 2. Cơ chế flag & chống bypass (đã kiểm chứng qua config)
- `parameter.config` dùng `HASH_REPLACE` bơm **CÙNG một hash** cho AccessKeyId (`imds_access_key`) và SecretAccessKey (`imds_secret_key`) vào ĐỒNG THỜI `imds:/…/creds_template.json` và `storage:/…/minio_env.sh` (cú pháp đa-đích `a:f;b:f`) → credential "tạm thời" imds trả về LUÔN khớp root cred MinIO chấp nhận. SessionToken (`imds_session_token`) chỉ hình thức trên imds. Flag (`ctf_flag`) bơm vào `storage:/home/ubuntu/flag_seed.txt`.
- Flag/credential đặt trên `imds`/`storage` (TERMINALS -1 → sinh viên KHÔNG có shell) → không cat/echo được.
- MinIO từ chối request unsigned/ký sai → BẮT BUỘC có đúng key lấy từ imds qua SSRF. `web` chỉ "fetch hộ" (không tự ký S3) → không thể SSRF thẳng vào storage để lấy object có nghĩa, buộc đi qua imds.
- Grading: `g_access_storage_get_flag = string_equal(loot.txt, parameter.ctf_flag)`; các nhiệm vụ khác dùng file `.ok` do `pregrade.sh` suy ra từ artifact THẬT (`web:fetch.log`, `imds:imds_access.log`) chứ không tin file sinh viên tự khai → chống echo giả.

## 3. Quyết định địa chỉ IMDS
- IMDS thật là link-local `169.254.169.254` — không thể gán làm IP chính của container ngoài subnet `172.34.0.0/24` trong Labtainer.
- Giải pháp: dùng **DNS name nội bộ `imds` (172.34.0.40)** qua `ADD-HOST` làm đường CHẮC CHẮN chạy; `imds/_bin/fixlocal.sh` thử gán thêm alias `169.254.169.254` lên chính nó (best-effort, không ảnh hưởng chấm nếu thất bại). Đề/guide nêu rõ đây là mô phỏng.

## 4. CHECKLIST RỦI RO cần kiểm khi build (§7)
1. **Cú pháp `results.config`/`goals.config`**: dạng "toàn nội dung" (`name = container:file`) + `value:` + `boolean : (_a and _b)` + `matchany : string_equal : r : parameter.x` — đối chiếu lại với lab mẫu thật trên VM (`telnetlab`, `capabilities`, `nmap-ssh`) khi `rebuild`; sửa nếu framework đòi field khác.
2. **string_equal flag**: object flag phải chứa ĐÚNG giá trị hash (không bọc `FLAG{}`, không newline thừa); solver lưu `loot.txt` phải không có trailing newline. Kiểm bằng `xxd`/so sánh với `parameter.ctf_flag` khi chấm.
3. **Khởi động service**: `web`/`imds` Flask + `storage` MinIO chạy qua systemd unit (SCRIPT NONE) hoặc `fixlocal.sh` — xác nhận đã `enable`/start và tạo `PERMLOCKDIR` nếu dùng waitparam. Kiểm cổng 8080/80/9000 nghe được.
4. **aws-cli trên client**: cần cấu hình endpoint MinIO (`--endpoint-url http://storage:9000`) + region giả; xác nhận SigV4 với key hash hoạt động (độ dài key/secret 12/28 ký tự có hợp lệ với MinIO không — nếu MinIO đòi độ dài tối thiểu, tăng `len` trong parameter.config).
5. **Gói apt/binary**: flask (pip), minio+mc (binary), aws-cli — tải lúc build (có internet), chạy offline. Kiểm image không quá nặng (VM ~3GB).
6. **ADD-HOST + WAIT_FOR**: xác nhận client resolve được `web/imds/storage`; web resolve `imds`.
7. **Chấm 2 chiều**: solver.sh → tất cả goal PASS; chấm khi "không làm gì" → tất cả FAIL.

## 5. Lệnh test nhanh (trên VM, sau khi deploy)
```
cd $LABTAINER_DIR/scripts/labtainer-student && rebuild cloud-ssrf-imds
# chạy solver trong client (qua terminal hoặc docker exec) → kiểm loot.txt
stoplab cloud-ssrf-imds   # rồi chấm bằng checkwork/gradelab
```
