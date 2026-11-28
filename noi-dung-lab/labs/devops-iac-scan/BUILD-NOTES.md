# BUILD-NOTES.md — dso-iac-scan

Ghi chú xây dựng cho subagent/engineer sẽ `rebuild`/test bài này trên VM
(`student@192.168.17.139`). Bài này **chưa được build/test** ở phiên làm việc
tạo ra các file này — chỉ mới viết file nguồn theo `LAB-BUILD-RULES.md` +
`09-dso-iac-scan.md`. Toàn bộ nhận định dưới đây là thiết kế/suy luận, cần
xác nhận lại bằng `rebuild` + `solver.sh` + `checkwork` thật trên VM.

## 1. Kiến trúc & cơ chế flag

- 2 container trên mạng `172.31.0.0/24` (gateway `.101`, tên network
  `LAB_NET`): `devsecops` (172.31.0.10, `TERMINALS 1`, `GRADE_CONTAINER`) và
  `ci` (172.31.0.20, `TERMINALS -1`).
- `devsecops` có `~/iac-project/` (7 file `.tf` chứa misconfig kinh điển đã
  cắm sẵn: network 0.0.0.0/0 x2, storage public/no-enc/no-version/no-log,
  IAM `Action:*`/`Resource:*`, secret hardcode trong `variables.tf`, compute
  thiếu IMDSv2 + EBS không mã hóa, logging trống/comment) và `~/gate.sh` gọi
  sang `ci`.
- `ci` chạy dịch vụ Flask `gate_server.py` (systemd unit `iacgate.service`,
  cổng 8000, endpoint `POST /gate`). Sinh viên gọi `~/gate.sh` trên
  `devsecops` → script đó tar hoá toàn bộ `*.tf` hiện tại và POST multipart
  lên `http://172.31.0.20:8000/gate`. Server **tự chạy `tfsec`** (binary cài
  sẵn trong image `ci`, không cần mạng) trên đúng bộ mã nhận được, đếm
  HIGH/CRITICAL, và chỉ khi tổng = 0 mới đọc `/opt/gate/flag.env` và trả về
  dòng `FLAG=<gia_tri>`.
- **Flag per-student:** `config/parameter.config` dùng `HASH_REPLACE`:
  ```
  iacflag : HASH_REPLACE : ci:/opt/gate/flag.env : IACGATEFLAG : dso_iac_scan_flag_seed : 16
  ```
  File `ci/_system/opt/gate/flag.env` chỉ chứa đúng 1 dòng là token literal
  `IACGATEFLAG` — **không có ký tự bao ngoài** (không phải `FLAG{...}`) để
  giá trị hash sau khi thay thế khớp CHÍNH XÁC với `parameter.iacflag` khi
  `goals.config` so sánh bằng `string_equal`. Nếu sau này muốn flag đẹp hơn
  dạng `FLAG{...}`, phải đổi cả `flag.env` lẫn cách `goals.config` so sánh
  cho khớp nhau — đừng sửa một bên.

## 2. Vì sao không thể bypass

- Sinh viên **không có shell** trên `ci` (`TERMINALS -1`) → không thể `cat
  /opt/gate/flag.env`, không thể sửa `gate_server.py` để bỏ qua kiểm tra.
- `gate_server.py` **tự chạy tfsec trên server**, không tin bất kỳ "kết quả
  quét" nào sinh viên tự gửi lên → không thể giả `baseline.json`/`after.json`
  để lừa gate.
- Dù sinh viên có `sudo` trên `devsecops` và có thể tự `echo` một chuỗi bất
  kỳ vào `~/flag.txt`, giá trị đó sẽ không khớp `parameter.iacflag` (hash
  per-student chỉ `ci` biết) nên goal `_flag_ok` (string_equal) sẽ FAIL.
- Ngoài lớp flag, `instr_config/pregrade.sh` là lớp phòng thủ thứ hai: nó
  **tự phân tích lại** `~/iac-project/*.tf` thu được (không tin nội dung
  `baseline.json`/`after.json` do sinh viên có thể sửa tay) bằng grep có cấu
  trúc, ghi ra các file đánh dấu `~/.local/result/chk_*` (OK/FAIL) — các
  file này bị **ghi đè mỗi lần chấm điểm**, nên echo giả vào đó vô nghĩa.
  `goals.config` chỉ so sánh các file đánh dấu này.

## 3. Bố cục file đã tạo/hoàn thiện trong phiên này

- `instr_config/results.config`, `instr_config/goals.config` — điền đầy đủ
  (trước đó trống). 4 goal chính: `baseline_scan`, `fix_network_storage`
  (hardening), `fix_secret_iam` (hardening), `pass_gate` (boolean của 3 điều
  kiện con `_after_zero_ok`, `_logging_ok`, `_flag_ok`).
- `instr_config/pregrade.sh` — viết lại phần logic (giữ nguyên header bản
  quyền NPS/C3O theo template). Chạy `grep -E` có cấu trúc trên các file
  `.tf` thật để xác định trạng thái đã sửa hay chưa; guard bằng
  `[ -d iac-project ]` để không chạy nhầm khi được gọi cho artifact của
  container khác.
- `ci/_system/opt/gate/gate_server.py` (mới) — dịch vụ Flask, xem mục 1.
- `ci/_system/opt/gate/flag.env` (mới) — chứa token `IACGATEFLAG`.
- `ci/_system/etc/systemd/system/iacgate.service` (mới) — unit khởi động
  `gate_server.py` bằng `python3`, `Restart=on-failure`.
- `ci/_bin/fixlocal.sh` — điền: siết quyền file (`chmod 600 flag.env`),
  `systemctl daemon-reload && enable && restart iacgate.service`.
- `devsecops/_bin/fixlocal.sh` — điền: `chmod +x ~/gate.sh`, `git init -q` +
  1 commit baseline trong `~/iac-project` (chỉ khi `.git` chưa tồn tại, để
  idempotent) để `git diff` hoạt động được ngay từ đầu.
- `docs/dso-iac-scan-guide.md` (mới) — hướng dẫn PTIT mục 1–5, dịch/giữ gần
  như nguyên nội dung từ `09-dso-iac-scan.md` nhưng **đã cắt bỏ mục "6. Ghi
  chú triển khai"** và không lộ giá trị/flag/cơ chế `HASH_REPLACE`. Mục 2
  (sơ đồ mạng) được viết lại cho khớp kiến trúc 2-container thật (spec gốc
  mô tả 1 container, đã được RULE §2/§4.3 ghi đè bằng thiết kế 2-container
  chống bypass — xem đối chiếu bên dưới).
- `solver.sh` (mới, ở root lab) — lời giải mẫu, tự động: quét baseline →
  ghi đè cả 5 file `.tf` lỗi (network/storage/logging/variables/iam) bằng
  nội dung đã fix hoàn chỉnh → sửa luôn `compute.tf` (lỗi phụ) vì `gate.sh`
  đóng gói TẤT CẢ `*.tf` gửi lên `ci`, nếu compute.tf còn lỗi HIGH thì gate
  thật sẽ KHÔNG pass dù các nhiệm vụ 2/3 theo rubric bài đã coi là xong →
  quét after → gọi `~/gate.sh` → kiểm tra `~/flag.txt`. Script cũng append
  các lệnh "chuẩn" vào `~/.bash_history` để goal `baseline_scan` (dựa một
  phần vào bằng chứng lịch sử lệnh) không bị false-negative khi test tự
  động (khi sinh viên gõ tay ở terminal thật thì bash tự ghi history, không
  cần đoạn này).
- `BUILD-NOTES.md` (file này).

**Đã có sẵn từ trước (không sửa, chỉ đọc/kiểm tra):**
`config/start.config`, `config/parameter.config`, `config/about.txt`,
`config/keywords.txt`, `dockerfiles/Dockerfile.dso-iac-scan.devsecops.student`,
`dockerfiles/Dockerfile.dso-iac-scan.ci.student`, `devsecops/gate.sh`,
`devsecops/iac-project/*.tf` (7 file), `docs/read_first.txt`.

## 4. Đối chiếu với spec gốc (09-dso-iac-scan.md)

Spec gốc mô tả **1 container duy nhất** và gợi ý 2 cách đặt flag ("nhúng
flag trong comment của 1 file Terraform, chỉ gate.sh giải mã" hoặc tương
đương). Cách đó **vi phạm nguyên tắc chống bypass** của `LAB-BUILD-RULES.md`
§4.1: nếu flag/logic gate nằm trên máy sinh viên (có sudo), sinh viên luôn
có thể đọc/giả mạo được. `LAB-BUILD-RULES.md` §2 và §4.3 đã chốt kiến trúc
2-container (`devsecops` .10 + `ci` .20, `ci` giữ flag) chính là để sửa lỗi
thiết kế này — đây là bản đã triển khai. Tài liệu hướng dẫn sinh viên
(`docs/dso-iac-scan-guide.md`) đã được viết khớp theo kiến trúc 2-container
thật, KHÔNG theo mô tả 1-container lỗi thời trong spec gốc.

## 5. Rủi ro cần kiểm tra khi build/test trên VM

1. **checkov có thể không cài được.** Dockerfile devsecops dùng
   `pip3 install checkov==3.2.257 || pip3 install checkov==3.2.0 || true` —
   dấu `|| true` khiến build KHÔNG fail dù cả 2 lần cài đều lỗi, nghĩa là
   `checkov` có thể **vắng mặt lúc runtime** trong khi hướng dẫn/spec yêu
   cầu sinh viên chạy `checkov -d .`. → Sau khi `rebuild`, PHẢI kiểm tra
   `docker exec <devsecops> checkov --version`; nếu thiếu, cân nhắc bỏ
   `|| true`, pin version nhẹ hơn, hoặc bỏ hẳn checkov khỏi Dockerfile +
   cập nhật guide/goals (rule §3 đã lường trước rủi ro này: "cân nhắc bỏ nếu
   image quá lớn, giữ tfsec+trivy").
2. **Flask/Python version trên `ci`.** `gate_server.py` dùng
   `subprocess.run(..., stdout=PIPE, stderr=PIPE, timeout=...)` (tương thích
   Python ≥3.3) thay vì `capture_output=True` (chỉ có từ Python 3.7) để an
   toàn hơn nếu base image dùng Python cũ. Tương tự Dockerfile `ci` có
   `pip3 install flask==3.0.3 || pip3 install flask || true` — dấu `|| true`
   nghĩa là nếu CẢ HAI lần cài Flask đều lỗi, build vẫn "thành công" nhưng
   `gate_server.py` sẽ crash lúc chạy (`ModuleNotFoundError`) và
   `iacgate.service` sẽ crash-loop (do `Restart=on-failure`) → toàn bộ
   `pass_gate` sẽ không bao giờ đạt được cho bất kỳ sinh viên nào. Sau khi
   `rebuild`, PHẢI kiểm tra `docker exec <ten_container_ci> systemctl status
   iacgate.service` và `curl http://172.31.0.20:8000/healthz` từ
   `devsecops`.
3. **Terraform provider mirror offline.** Dockerfile devsecops chạy
   `terraform providers mirror` lúc build để tạo `/opt/tf-mirror` và trỏ
   `TF_CLI_CONFIG_FILE` vào đó — cần xác nhận `terraform init -backend=false`
   thực sự không gọi mạng lúc runtime (test bằng cách rút mạng container
   hoặc kiểm tra log).
4. **trivy DB/checks offline.** Dockerfile warm-cache `trivy config` lúc
   build vào `/opt/trivy-cache` + set `TRIVY_SKIP_*_UPDATE=true`. Cần xác
   nhận `trivy config --severity HIGH,CRITICAL .` chạy được khi container
   không có mạng (biến `TRIVY_CACHE_DIR` phải khớp giữa lúc build và
   runtime — đã set qua `ENV` nên OK, nhưng vẫn nên test tay).
5. **tfsec version khớp giữa `devsecops` và `ci`.** Cả 2 Dockerfile đều pin
   `v1.28.13` — nếu sau này đổi version ở 1 bên mà quên bên kia, số lượng
   rule/severity có thể lệch giữa lúc sinh viên tự quét và lúc `ci` quét
   thật, gây khó hiểu (dù không ảnh hưởng tính đúng đắn của gate, vì gate
   luôn dùng kết quả CỦA CHÍNH NÓ).
6. **Cổng 8000 nội bộ.** `gate.sh` gọi thẳng `172.31.0.20:8000` (đã
   `ADD-HOST ci:172.31.0.20` trong `start.config` nên tên `ci` cũng dùng
   được). Không cần `PUBLISH` ra host. Sau khi lab start, kiểm tra nhanh từ
   `devsecops`: `curl -s http://172.31.0.20:8000/healthz` phải trả `ok`.
7. **Cú pháp `goals.config`/`results.config`.** Được viết đúng theo cú pháp
   tối giản mô tả trong `LAB-BUILD-RULES.md` §5 (`name = matchany :
   string_equal : <result> : answer=<value>`, `boolean : (_a and _b)`).
   Tài liệu đó khuyến nghị đối chiếu cú pháp thật với `labs/telnetlab`,
   `labs/nmap-ssh`, `labs/capabilities` trên VM — **chưa đối chiếu được**
   trong phiên này (không có quyền truy cập VM). Nếu framework thực tế đòi
   cú pháp khác (ví dụ `GOAL`/`CONDITION` theo khối thay vì `name = ...`),
   cần sửa lại 2 file này cho khớp — phần logic nặng đã nằm hết trong
   `pregrade.sh` (thuần bash, không phụ thuộc cú pháp goals.config) nên rủi
   ro sửa lại tương đối thấp.
8. **Heuristic grep trong `pregrade.sh` khá chặt theo định dạng HCL hiện có**
   (ví dụ tên attribute + `=` + giá trị trên cùng 1 dòng, không multi-line
   nối tiếp lạ). Nếu sinh viên chạy `terraform fmt` triệt để hoặc viết lại
   theo phong cách khác thường (ví dụ gộp nhiều thuộc tính trên 1 dòng bằng
   dấu `;`), các pattern có thể không khớp và gây false-negative (goal FAIL
   dù đã sửa đúng). Khi test bằng `solver.sh` (giữ format chuẩn) sẽ PASS;
   nếu muốn chặt chẽ hơn nữa nên bổ sung test với vài biến thể format khi
   có VM.
9. **Tài nguyên VM (~3GB RAM).** Bài không dựng cụm cloud/K8s nên nhẹ; rủi
   ro chính là `checkov` (Python, mục 1) và cache `trivy`/mirror Terraform
   làm image `devsecops` khá nặng (nhiều lớp RUN tải binary). Chỉ build/1
   lab tại 1 thời điểm theo đúng khuyến nghị RULE §7.

## 6. Lệnh test đề xuất (trên VM, theo RULE §7 — CHƯA chạy trong phiên này)

```bash
cd $LABTAINER_DIR/labs/dso-iac-scan
rebuild dso-iac-scan
# ... container/terminal len dung so do (1 terminal devsecops) ...
docker exec -it <ten_container_devsecops> bash -lc 'curl -s http://172.31.0.20:8000/healthz'
docker cp solver.sh <ten_container_devsecops>:/home/ubuntu/solver.sh
docker exec -it <ten_container_devsecops> bash -lc 'bash ~/solver.sh'
stoplab dso-iac-scan
checkwork dso-iac-scan   # hoac gradelab tuong duong
# Kiem tra ca chieu nguoc: rebuild lai, KHONG lam gi, stoplab, cham -> phai FAIL het
```
