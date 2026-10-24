# Rà soát 5 bài lab — giả lập học sinh (2026-10-24)

Môi trường: VM Labtainer 192.168.17.140, chạy đúng quy trình học sinh (start → làm NV theo guide → gate/exploit → `checkwork`).
Thứ tự rà soát: dso-iac-scan, dso-secrets-git, cloud-s3-misconfig, cloud-ssrf-imds, dso-docker-escape.

Ký hiệu: ✅ chấm điểm chạy đúng · ❌ lỗi chặn/làm sai hướng dẫn · ⚠️ lỗi nhỏ/khó chịu (cosmetic hoặc gây bối rối, không chặn chấm).

---

## Lab 1 — dso-iac-scan  — ✅ checkwork 4/4 Y — 🛠️ ĐÃ FIX (2026-10-24)

**Đã sửa:**
- checkov (không cài được trên Python 3.5 của image) → thay bằng **trivy** trong guide (NV1 bước5, NV3 bước4, bảng công cụ, Câu hỏi 1, mô tả, sơ đồ) + solver (history) + gỡ dòng checkov chết trong Dockerfile. Guide còn **0** tham chiếu checkov.
- Lệnh đếm severity: `grep -o '"severity":"[A-Z]*"'` → `grep -oE '"severity":[[:space:]]*"[A-Z]+"'` ở guide (4 chỗ) + solver (2 lệnh + 2 history). Đã xác nhận bảng đếm in ra: baseline 2 CRITICAL/10 HIGH/3 MEDIUM, after 0 HIGH/CRITICAL.
- Re-test: `-r` rebuild state + solver + `checkwork` = **4/4 Y**. (Chưa regenerate .docx — làm ở cuối.)

<details><summary>Lỗi gốc (trước fix)</summary>

Giải được, gate PASSED (flag `8a1386382a1f6c86`), `checkwork` = Y cả 4 goal
(baseline_scan, fix_network_storage, fix_secret_iam, pass_gate).

Lỗi phát hiện khi làm ĐÚNG theo guide:

- ❌ **`checkov` không được cài** trong container `devsecops` (không bin, không python module, không pip).
  Guide NV1-bước5 và NV3-bước4 yêu cầu chạy `checkov -d . --compact -o cli` → học sinh gặp `checkov: command not found`.
  (Grading không vỡ vì pregrade chỉ kiểm tra `.bash_history` CÓ chữ tfsec|checkov|trivy, không bắt chạy thật.)
  → Cách sửa: cài checkov vào image (pip) HOẶC bỏ checkov khỏi guide, thay bằng tfsec+trivy.

- ❌ **Lệnh đếm severity trong guide trả về RỖNG.** tfsec xuất JSON dạng `"severity": "HIGH"` (có dấu cách sau dấu hai chấm),
  nhưng guide dùng `grep -o '"severity":"[A-Z]*"' ~/baseline.json | sort | uniq -c` (KHÔNG có dấu cách) → không khớp, in ra trống.
  Xuất hiện ở NV1-bước4, NV4-bước2 và bước3. Học sinh tưởng quét lỗi.
  → Cách sửa guide: `grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/baseline.json | sort | uniq -c`
  (pregrade.sh đã dùng regex có `[[:space:]]*` nên chấm vẫn đúng — chỉ guide sai).

- ⚠️ `trivy` in notice "Version 0.76.1 is now available" mỗi lần chạy (cosmetic, offline vẫn quét tốt từ cache). Có thể thêm `--skip-version-check` vào guide cho sạch.
- ✅ `terraform init/validate`, `tfsec`, `trivy config` (offline, đọc cache) đều chạy đúng.
</details>

---

## Lab 2 — dso-secrets-git  — ✅ checkwork 9/9 Y — 🛠️ ĐÃ FIX (2026-10-24)

**Đã sửa:**
- **trufflehog** (panic OOM) → gỡ hoàn toàn khỏi guide (công cụ, mục tiêu, sơ đồ, bảng, NV2). NV2-bước3 thay trufflehog bằng **git pickaxe** (`git log -S 'AKIA'/'password' --oneline --all`). gitleaks là scanner tự động duy nhất + `git log -p`.
- **Ngưỡng gitleaks** đồng bộ **≥2**: solver (`-ge 2`, text), guide ("tối thiểu 2 finding"), và #SUM trên VM.
- Re-test: `-r` + solver (tất cả **[OK]**, hết [FAIL]) + `checkwork` = **9/9 Y**. (trufflehog vẫn còn trong image nhưng guide không nhắc → SV không chạm; .docx regenerate ở cuối.)

<details><summary>Lỗi gốc (trước fix)</summary>

Giải được toàn bộ: recon git history, gitleaks, trích 4 credential, lấy flag MinIO
(`mc`) + flag API (`curl` Bearer), rotate (key cũ bị DENIED), .gitignore + pre-commit hook chặn commit.
`checkwork` = Y cả 9 goal.

Lỗi/điểm cần lưu ý:

- ❌ **`trufflehog` panic** `unable to mmap memory: cannot allocate memory` — crash ngay cả khi chạy `trufflehog --version`.
  Guide (bảng công cụ, NV2) nêu trufflehog song song gitleaks và cho lệnh `trufflehog git file://<repo> --json`.
  Học sinh chọn trufflehog sẽ gặp crash. (gitleaks chạy tốt nên vẫn có đường hoàn thành.)
  → Nguyên nhân nhiều khả năng: trufflehog ngốn RAM, VM ~3GB + 3 container đang chạy → OOM/mmap fail.
  → Cách sửa: hoặc giới hạn/ghim phiên bản trufflehog nhẹ hơn + tăng overcommit, hoặc bỏ trufflehog khỏi guide (chỉ dùng gitleaks + `git log -p`).

- ⚠️ **Không nhất quán ngưỡng gitleaks:** `solver.sh` tự kiểm tra `>=3` finding và mô tả goal (`g_scan_secrets`) ghi "≥3 finding",
  nhưng `pregrade.sh` thực tế chỉ cần `N -ge 2`, và gitleaks (bản cài) chỉ phát hiện **2** finding (AWS key id + secret; DB password & API token không khớp rule mặc định).
  → Hệ quả: solver in `[FAIL]` gây hiểu nhầm, nhưng `checkwork` vẫn Y. Nên sửa solver + mô tả goal về "≥2" cho khớp pregrade.

- ⚠️ `aws` CLI không có trong container — nhưng guide dùng `mc` cho MinIO, KHÔNG dùng aws → không ảnh hưởng.
- ✅ git, gitleaks, mc, curl, jq đều chạy đúng; rotate + hook + gitignore đúng kỳ vọng.
</details>

## Lab 3 — cloud-s3-misconfig  — ✅ checkwork 5/5 Y — 🛠️ ĐÃ FIX (2026-10-24)

**Đã sửa (hướng b — guide khớp thực tế S3):**
- NV1-bước3: bỏ `s3api get-bucket-policy --no-sign-request` (ẩn danh → AccessDenied). Thay bằng **xác nhận quyền đọc ẩn danh** (tải object tĩnh + list) → ghi `recon_policy_status=PUBLICREAD`, kèm lưu ý "S3/MinIO không cho đọc policy khi ẩn danh".
- NV1 "điều kiện hoàn thành": đổi `PUBLICPOLICY` → `PUBLICREAD` (khả thi).
- NV4-bước2: thêm đọc policy **bằng credential quản trị** (`get-bucket-policy` có quyền) trước khi `delete-bucket-policy` → SV vẫn thấy `"Principal":"*"` đúng tinh thần bài. Câu hỏi 1 trỏ sang NV4.
- Solver cập nhật tương ứng.
- Re-test: solver (recon_policy=PUBLICREAD, NV4 đọc được policy, flag OK, harden DENIED+versioning ENABLED) + `checkwork` = **5/5 Y**.

<details><summary>Lỗi gốc (trước fix)</summary>

Giải được: list ẩn danh `public-assets` (LISTED), tải backup + trích AWS key lộ, dùng key lấy flag
bucket `secure-data` (`7b33c5352abc9af2447800c6`), hardening: xóa public policy (anon → DENIED) + bật versioning (ENABLED).
`checkwork` = Y cả 5 goal. Công cụ đủ (aws-cli 1.38.38, jq, tar, curl).

Lỗi phát hiện:

- ❌ **NV1-bước3 đọc bucket policy ẩn danh bị `AccessDenied`.** Guide bắt chạy
  `aws ... s3api get-bucket-policy --bucket public-assets --no-sign-request | jq ...` và ghi rõ
  "Điều kiện hoàn thành": phải đọc được policy chứa `"Principal": "*"` và `recon_policy_status.txt` = `PUBLICPOLICY`.
  Thực tế MinIO **từ chối GetBucketPolicy ẩn danh** → lệnh báo `AccessDenied`, file ghi `NOPOLICY` → điều kiện hoàn thành như guide mô tả là **bất khả thi khi ẩn danh**.
  (Chấm điểm KHÔNG vỡ: goal `enum_anonymous` chỉ kiểm tra `recon_list_status = LISTED`; không có goal nào chấm `recon_policy_status`.)
  → Cách sửa: hoặc (a) thêm `s3:GetBucketPolicy` cho `Principal:*` trong policy của `public-assets` để học sinh đọc được;
  hoặc (b) sửa NV1-bước3: bỏ yêu cầu đọc policy ẩn danh, suy luận misconfig từ việc list/get ẩn danh thành công (và đọc policy SAU khi có credential ở NV3).
- ✅ Các bước còn lại (list, cp backup, lấy flag, delete-bucket-policy, put-bucket-versioning) chạy đúng.
</details>

## Lab 4 — cloud-ssrf-imds  — ✅ checkwork 4/4 Y — 🛠️ ĐÃ FIX (2026-10-24, reboot-resilient)

**Đã sửa (chuyển 3 service sang systemd enabled — sống sót restart/reboot):**
- **web app** (Flask :8080): thêm `web/_system/.../webapp.service` + `web/_bin/fixlocal.sh` `systemctl enable --now webapp` (thay `nohup`).
- **imds app** (Flask :80): thêm `imds/_system/.../imdsapp.service` (User=root, ExecStartPre thêm IP 169.254.169.254) + `imds/_bin/fixlocal.sh` enable.
- **storage MinIO**: thêm `storage/_system/.../minio.service` + wrapper `minio-start.sh` (source minio_env.sh đã parameterize) + `storage/_bin/fixlocal.sh` enable (thay `nohup`); data `~/miniodata` + bucket/flag persist.
- Rebuild image web/imds/storage.
- **Re-test quyết định — PLAIN restart (stoplab + labtainer, KHÔNG -r):** web/imds/minio đều `active` tự động; solver lấy đủ creds + flag (`a263982ceda1189b`); `checkwork` = **4/4 Y**. (Trước fix: web/imds/minio chết sau restart → lab hỏng.)

<details><summary>Lỗi gốc (trước fix)</summary>

Giải được trên state sạch: SSRF discover → steal IAM creds qua IMDS (AKIAIMDS...) → lấy flag `fin-reports`
(`a263982ceda1189b`) → hardening (IMDSv2 bật → GET tràn 401; allowlist SSRF → 403). `checkwork` = Y cả 4 goal.

Lỗi phát hiện:

- ❌ **App web & imds (Flask) KHÔNG tự chạy lại sau khi stoplab + `labtainer` thường, hoặc sau khi VM reboot.**
  Hai app chỉ được khởi chạy trong `_bin/fixlocal.sh` (`nohup python3 app.py &`), mà fixlocal chỉ chạy lúc **parameterize lần đầu**.
  Khi start lại (home đã persist → parameterize bị bỏ qua) → app KHÔNG chạy → `curl http://web:8080/...` trả **HTTP 000**, toàn bộ NV1–NV3 bất khả thi.
  Kiểm chứng: start lần đầu OK (web=200); sau `stoplab`+`labtainer` → web không có cổng 8080, `/etc/xinetd.d/` rỗng, không process python;
  chỉ `labtainer -r cloud-ssrf-imds` (redo sạch) mới làm app chạy lại (web=200, config.yaml reset về `ssrf_protection:false`).
  So sánh: Lab 3 (MinIO) chạy bằng **systemd service** nên sống sót qua restart/reboot — lab 4 thì không.
  → **Tác động học sinh:** VM đồ án reboot thường xuyên (IP đổi theo DHCP). Sau reboot, học sinh gõ `labtainer cloud-ssrf-imds` để làm tiếp sẽ thấy web app chết, không khai thác được, dễ tưởng mình làm sai.
  → **Cách sửa (khuyến nghị):** chạy web/imds app bằng systemd service enabled (giống minio.service của lab 3), hoặc thêm unit/rc.local khởi chạy mỗi lần boot — KHÔNG chỉ dựa vào fixlocal.sh.

- ⚠️ `~/loot.txt` rỗng nếu chạy lệnh `aws s3 cp ... ./flag.txt` khi thư mục làm việc không ghi được (vd `/`).
  Solver dùng đường dẫn tương đối `./flag.txt`; học sinh trong terminal lab (ở `~`) thì OK. Có thể đổi solver/guide sang đường dẫn tuyệt đối `~/flag.txt` cho chắc.
- ✅ aws-cli, jq, curl đủ; chuỗi SSRF→IMDS→S3 và hardening endpoints hoạt động đúng khi app chạy.
</details>

## Lab 5 — dso-docker-escape  — ✅ checkwork 6/6 Y — 🛠️ ĐÃ FIX (2026-10-24, đúng premise + reboot-resilient)

**Đã sửa (docker.sock THẬT trong app, chạy mọi lần boot):**
- **Nguyên nhân sâu:** app container có `NO_PRIVILEGE YES` → **systemd PID1 chạy nhưng KHÔNG activate unit nào** (không journald/dbus/service). Vì vậy `docker-sock-forward.service` (thiết kế gốc) không bao giờ chạy → `/var/run/docker.sock` luôn vắng (dù ở lần start đầu).
- **Cách sửa:** khởi động socat **ngay trong CMD** của app container (không qua systemd): `rm -f /var/run/docker.sock; (while true; do socat UNIX-LISTEN:/var/run/docker.sock,fork,reuseaddr,mode=666 TCP:172.35.0.5:2375; sleep 2; done) & exec /sbin/init`. CMD chạy mỗi lần container start/restart/reboot → socket luôn tồn tại và forward tới dockerd host-sim. app fixlocal rút gọn (chỉ chờ socket sẵn sàng).
- Rebuild image app.
- **Re-test (fresh + PLAIN restart):** `/var/run/docker.sock` tồn tại (mode 666) → `docker -H unix:///var/run/docker.sock` kết nối host-sim (18.09.7), thấy escimg; escape đọc `.hostmarker`+flag qua socket; recon.txt chứa dòng socket THẬT; `checkwork` = **6/6 Y**. host-sim dockerd (systemd enabled) + escimg persist qua restart.
- Guide NV1/NV2 (đường `unix:///var/run/docker.sock`) giờ chạy đúng như dạy → đúng tên bài "docker socket escape".
- **Cải tiến ở vòng validate:** socat forward **mất luồng stdout của `docker run` foreground** (attach bị cắt — đo được 0/8), trong khi `docker run -d` + **`docker cp`** ổn định 8/8. Đã đổi solver + guide (NV2/NV3) sang mẫu `docker run -d -v /:/host esc ... sleep` rồi `docker cp esc:/host/root/<file>` — vẫn đúng bản chất "mount host / qua docker.sock", nhưng lấy bằng chứng tin cậy 100% (khớp pregrade regex `-v /:`). Kết quả: fresh + plain restart đều **6/6 Y ngay lần đầu**, hết hiện tượng ra rỗng.

> Ghi chú còn lại (không chặn): (1) đã khắc phục hiện tượng "ra rỗng" bằng `docker cp` (xem trên); (2) chấm `recon_ok` của pregrade match chuỗi `docker.sock` — nay khớp dòng socket THẬT nên không còn "ăn may"; (3) goal `escape_via_privileged` vẫn dùng lại `recon_ok` (luôn Y) — có thể siết sau nếu muốn.

<details><summary>Lỗi gốc (trước fix)</summary>

Lấy được hostmarker (`54980d23fab44eaf54bc`) + flag host (`87697196c4c17728`) và `checkwork` = Y cả 6 goal.
NHƯNG kết quả này đạt được KHÔNG theo cách lab định dạy, do các lỗi dưới đây.

Lỗi phát hiện (nghiêm trọng — lab không minh hoạ đúng điều nó tuyên bố):

- ❌ **`/var/run/docker.sock` KHÔNG được mount vào container `app`** — trong khi toàn bộ premise, tên lab và guide (NV1 bước3, NV2) xoay quanh "Docker socket bị lộ".
  Thực tế trong `app`: `ls -la /var/run/docker.sock` → *No such file or directory*; `docker -H unix:///var/run/docker.sock ...` → *Cannot connect to the Docker daemon*.
  Đường DUY NHẤT chạy được là Docker qua **TCP `tcp://172.35.0.5:2375`** (daemon của host-sim) — guide chỉ nhắc thoáng như "đường dự phòng" ở NV2 bước1.
  → Học sinh làm theo đường chính của guide (unix socket) sẽ thất bại hoàn toàn.
  → Đây là 2 misconfig KHÁC NHAU: *mount docker.sock* vs *expose Docker daemon qua TCP 2375 không TLS*. Lab đang dạy cái đầu nhưng triển khai cái sau.

- ❌ **Không có dấu hiệu recon nào mà guide liệt kê.** `app` có `CapEff: 0000000000000000` (KHÔNG capability nào), không docker.sock, không `/dev/sd*`.
  "Điều kiện hoàn thành" NV1 yêu cầu recon.txt chứa ≥1 trong: (a) docker.sock tồn tại, (b) `cap_sys_admin`, (c) `/dev/sda*` — **cả ba đều VẮNG**.
  Học sinh trinh sát trung thực sẽ KHÔNG tìm thấy dấu hiệu nào, và vector thật (TCP 2375) thì guide/recon không hề hướng tới.

- ⚠️ **Chấm recon quá yếu (ăn may):** `pregrade.sh` đặt `recon_ok=OK` nếu recon.txt chứa chuỗi `docker.sock|cap_sys_admin|/dev/sd[a-z]`.
  Vì `solver.sh` (và gợi ý recon trong guide) GHI NHÃN `=== docker.sock ===` vào recon.txt, `grep docker.sock` khớp **tiêu đề**, nên recon_ok=OK dù không có socket thật → checkwork vẫn Y.
- ⚠️ Goal `escape_via_privileged` định nghĩa `matchany : recon_ok : answer=OK` (dùng lại recon_ok) → luôn Y, không thực sự kiểm tra đường privileged.

→ **Cách sửa (khuyến nghị):** chọn 1 trong 2 hướng và làm cho nhất quán:
  (A) Thực sự mount socket host-sim vào app (`-v /var/run/docker.sock:/var/run/docker.sock`) để đúng tên lab + guide; hoặc
  (B) Viết lại guide dạy vector "Docker daemon lộ qua TCP 2375 không xác thực" làm đường chính, sửa recon (vd `curl http://172.35.0.5:2375/version` / quét cổng) + sửa pregrade để chấm theo bằng chứng thật (không khớp theo nhãn tiêu đề), và cập nhật "điều kiện hoàn thành" NV1.
  → **Đã chọn (A), triển khai bằng socat trong CMD** (vì systemd không chạy trong app NO_PRIVILEGE) — xem phần ĐÃ FIX ở trên.
</details>

---

# TỔNG KẾT (giả lập học sinh, chạy checkwork đầy đủ)

| Lab | checkwork (sau fix) | Lỗi gốc | Trạng thái |
|---|---|---|---|
| 1 dso-iac-scan | ✅ 4/4 Y | checkov thiếu; lệnh đếm severity sai khoảng trắng | 🛠️ ĐÃ FIX |
| 2 dso-secrets-git | ✅ 9/9 Y | trufflehog panic OOM; ngưỡng gitleaks không nhất quán | 🛠️ ĐÃ FIX |
| 3 cloud-s3-misconfig | ✅ 5/5 Y | NV1 đọc bucket policy ẩn danh bị AccessDenied | 🛠️ ĐÃ FIX |
| 4 cloud-ssrf-imds | ✅ 4/4 Y (plain restart) | app web/imds/minio không tự chạy lại sau restart/reboot | 🛠️ ĐÃ FIX (reboot-resilient) |
| 5 dso-docker-escape | ✅ 6/6 Y (plain restart) | docker.sock không mount (sai premise); systemd chết trong NO_PRIVILEGE | 🛠️ ĐÃ FIX (reboot-resilient) |

**Kết quả vòng fix (2026-10-24):** ✅ **Cả 5 lab: checkwork FULL, đã validate lại sau khi sửa.** Lab 4 & 5 còn được kiểm tra **sống sót qua plain restart** (mô phỏng reboot VM).

**Điểm chung:**
- Grader (`checkwork`) cả 5 lab chạy tốt, không crash (bug Unicode/boolean cũ đã sạch từ trước).
- Lỗi chủ yếu là **sai lệch giữa hướng dẫn/bản chất bài và môi trường thực tế** + **thiếu khả năng tự chạy lại sau reboot** (service khởi động bằng `nohup` trong fixlocal, không chạy lại khi restart).
- Bài học hạ tầng: service của lab nên chạy bằng **systemd enabled** (container thường) hoặc **trong CMD** (container NO_PRIVILEGE như app của lab 5), KHÔNG dựa vào fixlocal chạy-một-lần.

## ⚠️ Lưu ý quan trọng: repo ↔ VM lệch nhau
- VM đang chạy bản CŨ (còn comment #SUM/#DOC đầy đủ) trong khi **repo đã dọn comment** (commit "Don comment toan bo 5 bai lab"). Khác biệt chủ yếu là comment → KHÔNG ảnh hưởng hành vi chấm điểm.
- Các bản vá vòng này đã sửa trong **repo** (nguồn chuẩn) và **deploy xuống VM** để test. Lab 4 & 5 đã **rebuild image** trên VM.
- **Việc còn lại:** regenerate `.docx` guide cho lab 1/2/3 (đã sửa `.md`) bằng pandoc; commit toàn bộ thay đổi vào repo.
