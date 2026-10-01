# BUILD-NOTES — dso-secrets-git

Ghi chú build/test, quyết định thiết kế, và rủi ro. **Không build/SSH đã được thực hiện trong lượt này** — mọi nội dung dưới đây là thiết kế nguồn cần được xác nhận trên VM (`student@192.168.17.139`) theo quy trình §7 của `LAB-BUILD-RULES.md` trước khi coi lab là "xong" theo §0.

## 1. Sơ đồ container / mạng

`172.32.0.0/24`, gateway `172.32.0.101`, mạng `LAB_NET`.

| Container | IP | Port | TERMINALS | Vai trò |
|---|---|---|---|---|
| `dev` | 172.32.0.10 | – | 1 (GRADE_CONTAINER) | Máy sinh viên: git/gitleaks/trufflehog/curl/jq/mc, `~/repo`, `~/rotate_secrets.sh` |
| `app` | 172.32.0.20 | 8080 | -1 | Flask API: `/flag`, `/admin/rotate` |
| `storage` | 172.32.0.30 | 9000 (console 9001) | -1 | MinIO object store: bucket `corp-backups` private |

`app` có `WAIT_FOR storage` (cần alias `mc` tới MinIO admin để điều phối rotate).

## 2. Cơ chế flag + chấm điểm

3 flag `HASH_REPLACE` (đã có sẵn trong `config/parameter.config`, không sửa):

| Flag | Container:file (chứa TOKEN) | Token | Ý nghĩa |
|---|---|---|---|
| `storageflag` | `storage:/home/ubuntu/flag_object.txt` | `RUNFLAGSTORAGE` | Object `corp-backups/flags/flag.txt` trên MinIO |
| `apiflag` | `app:/home/ubuntu/flag_api.txt` | `RUNFLAGAPI` | Trường `flag` trong JSON trả về từ `GET /flag` khi xác thực đúng |
| `rotateflag` | `app:/home/ubuntu/flag_rotate.txt` | `RUNFLAGROTATE` | Trường `rotate_flag` trả về từ `POST /admin/rotate` khi chứng minh đúng credential gốc |

Cả 3 file token nằm trên `app`/`storage` — hai container `TERMINALS -1`, sinh viên **không có shell**. Framework thay `<TOKEN>` bằng hash per-student **trước khi** `fixlocal.sh` của từng container chạy (đúng thứ tự "parameterize rồi mới fixlocal" theo template), nên khi `app.py`/MinIO seed đọc các file này, nội dung đã là flag cuối cùng.

Sinh viên lưu 3 giá trị lấy được vào `~/loot_storage.txt`, `~/loot_api.txt`, `~/loot_rotate.txt` (mỗi file **chỉ chứa đúng 1 dòng = giá trị flag**, không có tiền tố) — tách 3 file riêng thay vì gộp vào một `~/loot.txt` nhiều dòng để tránh phải đoán cú pháp "trích field theo dòng" chưa xác nhận được của `results.config`.

`instr_config/goals.config` so `string_equal` các file trên với `parameter.storageflag` / `parameter.apiflag` / `parameter.rotateflag`. Không thể lấy đúng giá trị nếu không xác thực thật vào `app`/`storage` bằng credential đào từ Git history → không thể `echo` giả.

Ngoài 3 flag, `instr_config/pregrade.sh` (chạy phía chấm điểm, **không** ship cho sinh viên) đối chiếu **bằng chứng khai thác thật**, không chỉ tin file sinh viên tự khai:
- Nhiệm vụ 1: so khớp `ADD_COMMIT`/`REMOVE_COMMIT` sinh viên ghi trong `~/recon_answers.txt` với `git show --stat` thật trên `~/repo`.
- Nhiệm vụ 2: đếm số finding trong `~/gitleaks.json` (≥3) **và** so khớp chính xác 4 giá trị trong `~/secrets_found.txt` với hằng số credential gốc (hardcode trong `pregrade.sh`, hợp lệ vì đây là file instructor-side).
- Nhiệm vụ 4: kiểm tra `~/repo/.git/hooks/pre-commit` tồn tại + có quyền thực thi + nội dung có gọi `gitleaks`.

Kết quả tổng hợp ghi vào `~/.local/result/pregrade_summary.txt` (`RECON=OK|FAIL`, `GITLEAKS=OK|FAIL`, `CREDS=OK|FAIL`, `HOOK=OK|FAIL`) để `results.config`/`goals.config` tham chiếu.

## 3. Khớp credential xuyên suốt (điểm sống còn — không được lệch nhau)

Giá trị **tĩnh**, giống nhau cho mọi sinh viên (không phải flag), phải khớp **chính xác ở cả 4 nơi**:

```
AWS_ACCESS_KEY_ID     = AKIAZ7Q2X8VNK4RPDLW3          (20 ky tu, dang AKIA...)
AWS_SECRET_ACCESS_KEY = wWw0kQfZ9pL3xR7bN2sV6yH1tG4mD8cU5aJ0eKqP   (40 ky tu)
DB_USER               = appuser
DB_PASSWORD           = S3cr3t-DB-Pw-2024!
API_TOKEN              = app_tok_5f4e3d2c1b0a9988776655443322110f
```

Xuất hiện tại 4 file: `dev/_bin/fixlocal.sh` (sinh Git history), `app/app.py` (hằng số `LEAKED_*` để xác thực `/flag` và kiểm tra `/admin/rotate`), `storage/_bin/fixlocal.sh` (tạo MinIO user), `instr_config/pregrade.sh` (đối chiếu bài làm sinh viên). **Nếu sửa 1 giá trị, phải sửa đồng bộ cả 4 file** — đây là rủi ro bảo trì lớn nhất của thiết kế, đã ghi chú bằng comment "PHẢI KHỚP..." ở đầu mỗi file liên quan.

Tài khoản admin nội bộ MinIO (`miniolabadmin` / `Lab-Adm1n-R00t-2024-DoNotShare`) là secret **thứ hai, tách biệt**, chỉ tồn tại trong `app/app.py`, `app/_bin/fixlocal.sh`, `storage/_bin/fixlocal.sh` — không liên quan Git history, sinh viên không thể chạm tới vì không có shell trên `app`/`storage`.

## 4. Vì sao `build_repo.sh` được gộp vào `_bin/fixlocal.sh` thay vì để ở `dev/`

Bản scaffold ban đầu có `dev/build_repo.sh` (nằm trực tiếp dưới `dev/`, tức nằm trong phần cây thư mục "sẽ xuất hiện ở `~` của sinh viên"). Theo tài liệu `_ref-labtainer-designer.txt` §4.3: *"All files and directories in the lab container directory will be copied to the student's HOME directory **except for the bin and system directories**."* — nghĩa là mọi thứ nằm trực tiếp dưới `dev/` (không phải `_bin/`/`_system/`) sẽ bị copy thẳng vào `$HOME` của sinh viên. File `build_repo.sh` cũ chứa cả 5 giá trị secret dạng plaintext ⇒ nếu giữ nguyên vị trí, sinh viên chỉ cần `cat ~/build_repo.sh` là có toàn bộ credential, **phá hỏng hoàn toàn Nhiệm vụ 1–3 và vi phạm trực tiếp §4.1.2 của LAB-BUILD-RULES.md**.

Đã sửa: xoá `dev/build_repo.sh`, gộp logic dựng repo vào `dev/_bin/fixlocal.sh` (không được copy vào `$HOME`, chỉ thực thi). `~/rotate_secrets.sh` thì **vẫn cố ý đặt trực tiếp dưới `dev/`** (được copy vào `$HOME`, đúng như đề bài yêu cầu `~/rotate_secrets.sh` phải hiện diện) — nhưng script này tự đào lại credential gốc từ `~/repo` lúc chạy (`git log --diff-filter=A` + `git show`) thay vì hardcode, nên `cat ~/rotate_secrets.sh` không lộ giá trị secret nào.

**Rủi ro cần xác nhận khi build lần đầu:** đây là suy luận từ tài liệu thiết kế Labtainer, chưa test thật. Nếu khi `rebuild` phát hiện `_bin/` vẫn bị copy vào `$HOME` (khác tài liệu), phải bổ sung một bước dọn dẹp tường minh cuối `fixlocal.sh` (ví dụ tự xoá `$HOME/build_repo.sh` nếu framework có copy) — nhưng theo thiết kế hiện tại, logic dựng repo đã nằm hẳn trong `_bin/fixlocal.sh`, không tồn tại dưới dạng file `build_repo.sh` độc lập nữa nên rủi ro này đã được loại bỏ, chỉ còn phải xác nhận `_bin/` quả thực không lộ ra `$HOME`.

## 5. Rủi ro #1 — cú pháp chính xác của `results.config` / `goals.config`

`LAB-BUILD-RULES.md` §5 mô tả cú pháp tổng quát (`name = <container>:<file> : <field> : <OP> : <value>`, `g = matchany : string_equal : ...`, `g = boolean : (_a and _b)`, `g = value : <result>`) nhưng **không có sẵn trong repo này một `results.config`/`goals.config` thật đã điền** để đối chiếu 1:1 (các lab anh em `dso-iac-scan`, `cloud-s3-misconfig`, `cloud-ssrf-imds`, `dso-docker-escape` đều còn là file mẫu rỗng). Tài liệu gợi ý tham chiếu `labs/telnetlab`, `labs/nmap-ssh`, `labs/capabilities` thật trên VM — các file này **không có mặt trong môi trường viết file (offline, không SSH) của lượt này**.

Đã viết `instr_config/results.config` và `instr_config/goals.config` bám sát cú pháp tài liệu mô tả, dùng `content` làm giá trị `<field>` mặc định cho kiểm tra `CONTAINS` trên toàn bộ nội dung file. **Trước khi `rebuild` lần đầu trên VM**, cần:
1. Mở một `results.config`/`goals.config` thật (`labs/telnetlab/instr_config/*.config` hoặc `labs/capabilities/instr_config/*.config`).
2. Đối chiếu đúng tên field/OP token (`content` có thể cần đổi thành tên khác, hoặc `<field>` có thể không bắt buộc với OP `CONTAINS`/whole-file).
3. Logic/ý định (file nào, tìm chuỗi gì, so khớp flag nào) đã đúng theo thiết kế ở mục 2 — nhiều khả năng chỉ cần đổi tên token, không cần đổi cấu trúc.

## 6. Rủi ro #2 — tài nguyên MinIO

- `dockerfiles/Dockerfile.dso-secrets-git.storage.student` tải `minio`/`mc` từ `dl.min.io` bằng URL "latest" (không pin version cụ thể, vì MinIO không phát hành tarball theo semver cố định dễ pin như `gitleaks`). Rebuild ở thời điểm khác nhau có thể lấy phiên bản `mc`/`minio` khác nhau, tiềm ẩn thay đổi cú pháp CLI.
- Cụ thể nguy cơ nhất: `mc admin policy attach ... --user ...` (cú pháp `mc` mới) vs `mc admin policy set ... user=...` (cú pháp cũ). `storage/_bin/fixlocal.sh` đã viết fallback thử cả hai, nhưng **cần xác nhận thật trên VM** — nếu cả hai đều sai cú pháp với phiên bản `mc` tải về, user leak vẫn tạo được (nên `mc ls`/`mc cat` vẫn hoạt động) nhưng có thể thiếu chặt policy readonly (không ảnh hưởng luồng chính, chỉ ảnh hưởng độ "đúng thực tế" của quyền hạn).
- MinIO server (dù chỉ dùng filesystem backend, 1 node) tốn thêm RAM/CPU so với các lab không cần storage — cân nhắc theo cảnh báo §3 "VM ~3GB, không chạy 5 lab cùng lúc". Nếu quá tải khi test, phương án dự phòng đã nêu trong spec gốc (`05-dso-secrets-git.md` mục Ghi chú triển khai) là thay MinIO bằng một HTTP server giả đóng vai S3-lite; **chưa áp dụng** trong lượt build này vì MinIO mang lại tính chân thực cao hơn (đúng `mc`/S3 API thật) và đã có sẵn trong Dockerfile scaffold — chỉ nên đổi nếu đo được MinIO thực sự làm treo VM khi test.
- `nohup minio server ... &` / `nohup python3 app.py ... &` chạy trực tiếp trong `fixlocal.sh` (không qua systemd unit) theo đúng phương án được `LAB-BUILD-RULES.md` §3 cho phép ("chạy nền trực tiếp trong `fixlocal.sh`"). Rủi ro: nếu `/sbin/init` của container thu hồi tiến trình con mồ côi sau khi `fixlocal.sh` (chạy qua một service tạm) kết thúc, dịch vụ có thể bị dừng theo. Nếu khi test thấy `app`/`storage` "chết" sau vài chục giây, cần chuyển sang systemd unit (đặt `.service` trong `_system/etc/systemd/system/`, `systemctl enable` trong `fixlocal.sh`) — mẫu cách làm có ở `_ref-labtainer-designer.txt` §4.5.

## 7. Rủi ro #3 — gitleaks/trufflehog offline

- `gitleaks` v8.18.4 (pin cứng trong Dockerfile) — không cần mạng lúc chạy, chỉ cần mạng lúc build image để tải tarball. Đúng yêu cầu "tắt verify online" (gitleaks mặc định không xác thực online, chỉ trufflehog mới có bước verify).
- `trufflehog` v3.75.0 (pin cứng) chỉ dùng đối chiếu tuỳ chọn (Bước 3, Nhiệm vụ 2) — **không** truyền `--json` kèm verify online trong hướng dẫn; hướng dẫn hiện tại (`trufflehog git file://$HOME/repo --json`) mặc định trufflehog v3 **có bật verify** nếu phát hiện loại secret hỗ trợ xác thực (ví dụ AWS key) và có mạng — trong lab runtime OFFLINE nên các lượt verify sẽ tự thất bại/timeout êm (không chặn output phát hiện), nhưng nên cân nhắc thêm `--no-verification` để tránh trufflehog treo/chờ timeout mạng không cần thiết. **Đề xuất sửa nhỏ khi test:** đổi lệnh trong `docs/dso-secrets-git-guide.md` (Nhiệm vụ 2, Bước 3) thành `trufflehog git file://$HOME/repo --no-verification --json | jq -r '.Raw // .Redacted'` nếu quan sát thấy độ trễ do verify khi build/test trên VM.
- Số lượng finding gitleaks (ngưỡng ≥3, lấy nguyên từ `05-dso-secrets-git.md` mục Ghi chú triển khai) là ước tính hợp lý (AWS access key + AWS secret key + ít nhất 1 trong DB password/API token khớp rule generic) nhưng **chưa chạy gitleaks thật để đếm chính xác** — cần xác nhận số finding thật khi `rebuild` + chạy `solver.sh`, hạ ngưỡng nếu cần.

## 8. Lệnh test dự kiến (trên VM, theo §7 LAB-BUILD-RULES.md)

```bash
cd $LABTAINER_DIR/labs/dso-secrets-git
# (sau khi copy toan bo thu muc lab nay vao $LABTAINER_DIR/labs/)
rebuild dso-secrets-git
# mo terminal dev, hoac:
docker cp solver.sh <container_dev>:/home/ubuntu/solver.sh
docker exec -u ubuntu <container_dev> bash /home/ubuntu/solver.sh
stoplab dso-secrets-git
# cham bang checkwork / gradelab -> ky vong TAT CA goal PASS
# chay lai chu trinh "khong lam gi" (khong solver) -> ky vong TAT CA goal FAIL
```

## 9. Checklist rủi ro build (tóm tắt để review nhanh)

- [ ] Xác nhận `_bin/`/`_system/` thực sự không bị copy vào `$HOME` sinh viên (mục 4) — nếu sai, `dev/_bin/fixlocal.sh` phải tự dọn dẹp thêm.
- [ ] Đối chiếu cú pháp thật của `results.config`/`goals.config` với `labs/telnetlab`/`labs/capabilities` (mục 5) — khả năng cao cần đổi tên token `content`, không đổi logic.
- [ ] Chạy thử `mc admin policy attach`/`mc admin policy set` với phiên bản `mc` thực tế tải về, xác nhận 1 trong 2 chạy được (mục 6).
- [ ] Theo dõi RAM/CPU khi cả `dev`+`app`+`storage` chạy cùng lúc; có phương án S3-lite thay MinIO nếu quá tải (mục 6).
- [ ] Xác nhận tiến trình `minio`/`python3 app.py` chạy nền qua `nohup ... &` trong `fixlocal.sh` không bị kill sau khi container ổn định; chuyển sang systemd unit nếu cần (mục 6).
- [ ] Đếm số finding gitleaks thật, chỉnh ngưỡng `pregrade.sh`/hướng dẫn nếu <3 (mục 7).
- [ ] Cân nhắc thêm `--no-verification` cho lệnh trufflehog trong tài liệu hướng dẫn (mục 7).
- [ ] Chạy `solver.sh` → tất cả goal PASS; chạy lại không làm gì → tất cả goal FAIL (Definition of Done §0).
- [ ] Sau khi xác nhận build thật, tạo `docs/dso-secrets-git.docx` từ `docs/dso-secrets-git-guide.md` bằng skill `docx` (yêu cầu hiện tại chỉ cần `.md`, `.docx` là bước tiếp theo ngoài phạm vi lượt này).
