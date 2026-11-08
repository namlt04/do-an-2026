# QUY TẮC XÂY DỰNG BÀI LAB (Labtainer) — SecLab PTIT / Đồ án 2026

> Tài liệu "rule" chuẩn hoá cách biến một **spec nội dung** (`0X-*.md`) thành một **bài lab Labtainer chạy thật** + **file hướng dẫn `.docx` chuẩn**. Mọi subagent/người xây lab PHẢI tuân thủ. Mục tiêu kép: (1) lab chạy được, chấm điểm tự động; (2) **chống bypass** (không cat/`.bash_history` ra flag, không copy giữa sinh viên).

Máy build/test: `student@192.168.17.139` (Ubuntu 18.04), Labtainer tại `~/labtainer/trunk` (`$LABTAINER_DIR`). Khóa SSH: `~/.ssh/lab_student`. sudo: `password123`.

---

## 0. Định nghĩa "HOÀN THÀNH" (Definition of Done) cho mỗi bài

Một bài lab được coi là xong khi:
1. `rebuild <lab>` build thành công, các container khởi động, sinh viên có terminal đúng như sơ đồ.
2. Chạy `solver.sh` (lời giải mẫu) → thực hiện trọn chuỗi khai thác + hardening → lấy được flag.
3. `stoplab <lab>` rồi chấm (`checkwork` / gradelab) → **tất cả goals PASS** khi đã giải đúng, và **FAIL khi chưa giải** (kiểm chứng bằng cách chấm một lần "không làm gì").
4. Flag là **per‑student hash** (không tĩnh) và **không thể lấy bằng `cat`/`.bash_history`** nếu không thực sự khai thác (xem §4).
5. Có `docs/<lab>.docx` theo đúng format PTIT (§6).

---

## 1. Cấu trúc thư mục một bài lab

```
labs/<lab>/
├── config/
│   ├── start.config          # container, mạng, GRADE_CONTAINER, LAB_MASTER_SEED
│   ├── parameter.config      # tham số hoá + FLAG HASH_REPLACE (bắt buộc)
│   ├── about.txt             # 1–2 dòng mô tả (hiện khi `labtainer -l`)
│   └── keywords.txt          # từ khoá phân loại
├── instr_config/
│   ├── goals.config          # định nghĩa goal (điều kiện PASS)
│   ├── results.config        # parse artifact (stdout/stdin/file/log)
│   └── pregrade.sh           # (khuyến nghị) kiểm tra end-state khi chấm
├── dockerfiles/
│   └── Dockerfile.<lab>.<container>.student   # 1 file/ container
├── <container>/              # = HOME của sinh viên trong container đó
│   ├── <file bài>            # file sẽ xuất hiện ở ~ của sinh viên
│   ├── _bin/
│   │   ├── fixlocal.sh       # chạy khi container khởi động (bật service, seed data)
│   │   └── student_startup.sh# (tuỳ chọn) chạy mỗi khi mở terminal
│   └── _system/             # file map vào / (vd _system/etc/... -> /etc/...)
├── docs/
│   ├── <lab>.docx            # HƯỚNG DẪN CHUẨN PTIT (deliverable chính)
│   ├── read_first.txt        # hiện trước khi mở terminal (trỏ tới LAB_MANUAL)
│   └── (tuỳ chọn) <lab>.pdf
├── solver.sh                 # LỜI GIẢI MẪU (dùng để tự test đạt goal) — KHÔNG phát cho SV
└── BUILD-NOTES.md            # ghi chú build/test, quyết định thiết kế, rủi ro
```

Scaffold bằng `new_lab_setup.py` (designer kit) để có sẵn build‑glue đúng, rồi mới sửa. (Xem §7.)

---

## 2. `start.config` — mạng & container

- Mỗi bài dùng **1 dải mạng riêng** để tránh đụng nhau. Bảng phân bổ (đã chốt):

  | Lab | Dải mạng | Container (IP) | GRADE_CONTAINER |
  |---|---|---|---|
  | `dso-iac-scan` | `172.31.0.0/24` (gw .101) | `devsecops` .10 · `ci` .20 | `devsecops` |
  | `dso-secrets-git` | `172.32.0.0/24` (gw .101) | `dev` .10 · `app` .20 · `storage` .30 | `dev` |
  | `cloud-s3-misconfig` | `172.33.0.0/24` (gw .101) | `client` .10 · `storage` .30 | `client` |
  | `cloud-ssrf-imds` | `172.34.0.0/24` (gw .101) | `client` .10 · `web` .20 · `imds` .40 · `storage` .30 | `client` |
  | `dso-docker-escape` | `172.35.0.0/24` (gw .101) | `app` .10 · `host-sim` .5 | `app` |

- Container **sinh viên thao tác**: `TERMINALS 1`. Container **dịch vụ** (không cho SV shell): `TERMINALS -1`.
- `GRADE_CONTAINER` = nơi chạy pregrade và gom artifact chính (thường là máy client của SV).
- `LAB_MASTER_SEED <lab>_ptit_seed` — chuỗi seed riêng mỗi bài (kết hợp email SV → seed cá nhân hoá).
- Mẫu tối thiểu (2 container):
```
GLOBAL_SETTINGS
    GRADE_CONTAINER client
    HOST_HOME_XFER seed_dir/
    LAB_MASTER_SEED <lab>_ptit_seed
NETWORK LAB_NET
    MASK 172.33.0.0/24
    GATEWAY 172.33.0.101
CONTAINER client
    USER ubuntu
    TERMINALS 1
    LAB_NET 172.33.0.10
CONTAINER storage
    USER ubuntu
    TERMINALS -1
    LAB_NET 172.33.0.30
```
- Cho service cần đợi nhau: dùng `WAIT_FOR <container>`. Cho DNS name nội bộ: dùng `ADD-HOST host:ip -- LAB_NET` (mọi container trên mạng có entry /etc/hosts).

---

## 3. Dockerfile & cài công cụ (offline‑first)

- Base image có sẵn cục bộ (ưu tiên, không cần pull): `labtainers/labtainer.base`, `.network`, `.network.ssh`, `.lamp`, `.centos`, `.java`, `.firefox`, `.wireshark`. Dùng `.network` cho máy có công cụ mạng; `.base` cho máy tối giản.
- Template Dockerfile (ĐÃ KIỂM CHỨNG — `new_lab_setup.py` sinh sẵn tại `dockerfiles/Dockerfile.<lab>.<container>.student`). **GIỮ NGUYÊN mọi dòng `ARG`/`ADD`/`USER`/`CMD` build‑glue.** Chỉ sửa 2 chỗ:
  1. Dòng `FROM $registry/labtainer.base2` → đổi base nếu cần: dùng `$registry/labtainer.network` cho container cần `curl/wget/openssh/tcpdump/net-tools` (client, web, app, ci, dev…); giữ `.base2` cho container tối giản.
  2. Chèn lệnh cài gói vào vùng "put package installation here" — **PHẢI đặt trước dòng `USER $user_name`** (mọi thao tác root ở trên). Ví dụ:
     `RUN apt-get update && apt-get install -y --no-install-recommends jq git && rm -rf /var/lib/apt/lists/*`
     `ADD https://.../tfsec /usr/local/bin/tfsec` rồi `RUN chmod +x /usr/local/bin/tfsec` (hoặc `RUN wget -qO ...`).
  - Khung template (rút gọn, phần in đậm là bất biến):
    ```dockerfile
    ARG registry
    FROM $registry/labtainer.network        # đổi base tại đây
    ARG lab
    ARG labdir
    ARG imagedir
    ARG user_name
    ARG password
    ARG apt_source
    ARG version
    LABEL version=$version
    ENV APT_SOURCE $apt_source
    RUN /usr/bin/apt-source.sh
    # >>> CHÈN RUN cài gói Ở ĐÂY (còn quyền root) <<<
    ADD $labdir/$imagedir/sys_tar/sys.tar /
    ADD $labdir/sys_$lab.tar.gz /
    RUN useradd -ms /bin/bash $user_name
    RUN echo "$user_name:$password" | chpasswd
    RUN adduser $user_name sudo
    USER $user_name
    ENV HOME /home/$user_name
    ADD $labdir/$imagedir/home_tar/home.tar $HOME
    RUN rm -f $HOME/home.tar
    ADD $labdir/$lab.tar.gz $HOME
    USER root
    CMD ["/bin/bash", "-c", "exec /sbin/init --log-target=journal 3>&1"]
    ```
- **Container chạy systemd (`/sbin/init`)**: khởi động dịch vụ bằng systemd unit (đặt file `.service` trong `<container>/_system/etc/systemd/system/` rồi `systemctl enable` trong `fixlocal.sh`), HOẶC chạy nền trực tiếp trong `fixlocal.sh`. `fixlocal.sh` chạy SAU parameterization; `$1`=password, `$2`=uid; dùng `echo $1 | sudo -S <cmd>` khi cần root.
- Tải công cụ khi BUILD (VM có internet); đóng gói vào image để runtime OFFLINE. Đặt binary vào `/usr/local/bin` trong phần RUN root.
- Cài công cụ **cố định phiên bản**, tải 1 lần lúc build (VM có internet), để **runtime offline**:
  - Binary Go tĩnh (nhẹ, ưu tiên): `tfsec`, `trivy`, `gitleaks`, `mc` (MinIO client), `syft` — tải bản release `linux_amd64` vào `/usr/local/bin`.
  - `terraform`: tải zip release, chỉ dùng `init -backend=false`/`validate`.
  - `checkov`: `pip3 install checkov==<ver>` (nặng — cân nhắc bỏ nếu image quá lớn, giữ tfsec+trivy).
  - `trivy`: **đóng gói sẵn DB** khi build (`trivy --download-db-only`) để `trivy config`/`image` chạy offline.
  - **Object storage S3: KHÔNG dùng MinIO nữa** (MinIO đã gỡ toàn bộ kênh phân phối binary công khai: dl.min.io → 410 Gone, Docker Hub/quay.io → yêu cầu đăng nhập, không có binary trên GitHub). Thay bằng **`labs/_shared/s3lite.py`** — máy chủ S3 tối giản viết bằng Python thư viện chuẩn (không cần pip), chạy offline, **bắt buộc AccessKeyId đúng cho bucket private** (đọc từ SigV4 `Credential=<AKID>/...`), cho ẩn danh trên bucket public. Copy `s3lite.py` vào `storage/` của lab, cấu hình qua env (`S3LITE_ROOT`, `S3LITE_PUBLIC_BUCKETS`, `S3LITE_AKID_FILE`, `S3LITE_PORT=9000`), chạy nền trong `fixlocal.sh` hoặc systemd unit. Client dùng `aws-cli` (path-style, `--endpoint-url http://storage:9000`) hoặc `curl` — **KHÔNG dùng `mc`** (mc là công cụ MinIO, bỏ). HASH_REPLACE bơm flag vào file object dưới `S3LITE_ROOT/<bucket-private>/...` và bơm AccessKeyId per-student vào file `S3LITE_AKID_FILE` + vào credential lộ (backup/history) để hai bên khớp.
  - App web giả (Flask): `pip3 install flask` trên base `.network`.
  - `docker` CLI + `host-sim` dùng image `docker:dind` (bài escape).
- Tối ưu RAM (VM ~3GB): base nhỏ, gộp `RUN`, xoá cache apt/pip; **không** chạy 5 lab cùng lúc.

---

## 4. FLAG & CHỐNG BYPASS (phần quan trọng nhất)

### 4.1 Nguyên tắc bất biến
1. **Flag KHÔNG BAO GIỜ là chuỗi tĩnh.** Luôn dùng `HASH_REPLACE` trong `parameter.config` → mỗi sinh viên một flag khác nhau, sinh từ `LAB_MASTER_SEED` + email SV. Không đoán được, không copy được của nhau.
2. **Flag KHÔNG được đọc bằng `cat`/`grep`/`.bash_history` trên máy sinh viên.** Flag phải nằm ở **container mà sinh viên KHÔNG có shell** (`TERMINALS -1`) và chỉ lấy được qua **đúng đường khai thác** (auth bằng credential lộ, SSRF, escape, vượt quality‑gate…). Vì SV có thể có `sudo` trên máy của họ, **không đặt flag ở bất kỳ file nào trên máy client** — kể cả file của root.
3. **Chấm bằng bằng chứng khai thác, KHÔNG bằng "file có tồn tại" hay "history có chuỗi".** Sinh viên có thể `echo` giả một chuỗi vào history/file; do đó goal phải so **giá trị flag hash** (chỉ lấy được từ dịch vụ) và/hoặc `pregrade.sh` kiểm tra end‑state thật.

### 4.2 Cú pháp `HASH_REPLACE`
```
<param> : HASH_REPLACE : <container>:<file>[;<container>:<file>] : <TOKEN> : <seed_string> [: <len>]
```
- Đặt literal `<TOKEN>` (vd `RUNFLAG`) vào file **trên container dịch vụ**; lúc parameterize, framework thay `<TOKEN>` bằng hash per‑student.
- Grading tham chiếu `parameter.<param>` = đúng giá trị hash đó.
- Ví dụ (bài s3): flag nằm trong object của bucket private trên `storage`:
  `s3flag : HASH_REPLACE : storage:/data/private/flag.txt : RUNFLAG : ptit_s3_seed : 12`

### 4.3 Vị trí flag theo từng bài (đảm bảo không cat được)
- `dso-iac-scan`: flag do **service `ci`** giữ. SV không có shell trên `ci`. `ci` chạy 1 endpoint: nhận thư mục terraform đã sửa (hoặc SV `curl http://ci/gate`), `ci` **tự quét** tfsec/trivy; chỉ trả flag khi 0 HIGH/CRITICAL. → không thể cat, không thể giả kết quả quét.
- `dso-secrets-git`: flag nằm trong **MinIO bucket** (`storage`) và/hoặc sau **auth API** (`app`); chỉ lấy được bằng credential đào từ history.
- `cloud-s3-misconfig`: flag trong **bucket private** trên `storage`; cần chuỗi misconfig→credential lộ→bucket private.
- `cloud-ssrf-imds`: flag trong **cloud storage** (`storage`), chỉ truy cập bằng credential tạm thời **lấy từ `imds`** qua SSRF trên `web`.
- `dso-docker-escape`: flag `/root/flag.txt` trên **`host-sim`**; SV chỉ có shell trên `app` → phải escape mới đọc được.

### 4.4 Bắt artifact để chấm (khuyến nghị)
- SV lưu flag lấy được vào 1 file quy ước ở HOME máy client (vd `~/loot.txt`) → framework thu như artifact.
- `results.config` trích giá trị; `goals.config` so `string_equal`/`string_start` với `parameter.<flag>`.
- Bổ sung `pregrade.sh` kiểm tra **end‑state** đúng bản chất (vd: bài escape kiểm tra SV đã đọc được canary `/root/.hostmarker` chỉ có trên host‑sim; bài iac kiểm tra `after.json` có 0 HIGH/CRIT). Điều này chặn việc `echo` giả flag.

---

## 5. Chấm điểm — `results.config` + `goals.config`

- `results.config`: mỗi dòng biến một artifact thành "result".
  - Dạng file/field: `name = <container>:<file> : <field> : <OP> : <value>` (OP: `STARTSWITH`, `CONTAINS`, `HAVESTRING`, `TOKEN`…).
  - Đếm lệnh: `name = <container>:.bash_history : COMMAND_COUNT : <cmd>`.
  - Toàn nội dung: `name = <container>:<file>` (rồi so ở goals).
- `goals.config`: điều kiện PASS.
  - So giá trị: `g = matchany : string_equal : <result> : parameter.<flag>`
  - So mở đầu: `g = matchany : string_start : <result> : answer=<prefix>`
  - Kết hợp: `g = boolean : (_a and _b)`
  - Giá trị: `g = value : <result>`
- **Mỗi Nhiệm vụ trong đề PHẢI có ≥1 goal đo được.** Tên goal đặt theo tên nhiệm vụ (`recon_*`, `exploit_*`, `get_flag`, `harden_*`). Bài phải có **≥1 goal hardening** (tỷ lệ bảo mật 60/40).
- Tài liệu hoá goal: dùng dòng `#DOC:`/`#SUM:` trong goals.config.
- Tham chiếu file mẫu THẬT trên VM để copy cú pháp: `labs/telnetlab`, `labs/nmap-ssh`, `labs/capabilities` (có `pregrade.sh`).

---

## 6. File hướng dẫn `.docx` chuẩn PTIT (deliverable)

Bám đúng bài mẫu `_ref-sample-lab-t1057.txt`. Tiếng Việt, xưng "sinh viên". Bố cục:

1. **Header:** "Học viện Công nghệ Bưu chính Viễn thông – SecLab PTIT" · "HƯỚNG DẪN THỰC HÀNH" · Tên bài · Mức độ · nhãn phân loại · (ánh xạ khung nếu có).
2. **1. Giới thiệu lab** — bảng: Tên Lab (mã), Mức độ, Công cụ sử dụng, Kiến thức yêu cầu; rồi **Mục tiêu học tập** (3–5 gạch), **Kỹ năng đạt được** (3–5 gạch, thiên bảo mật).
3. **2. Kịch bản** — Tình huống · Vai trò của sinh viên · **Sơ đồ mạng** (mô tả text container/IP/dịch vụ/luồng).
4. **3. Kiến thức bổ trợ** — Kiến thức nền tảng · bảng "Thành phần cần quan sát" · **bảng "Công cụ & cú pháp"**.
5. **4. Các nhiệm vụ** — mở đầu bằng `imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/<lab>.tar` + `labtainer <lab>` + ghi chú nhập mã sinh viên; rồi **Nhiệm vụ 1..N**, mỗi nhiệm vụ: Mục tiêu · các **Bước** kèm lệnh (dùng `<...>` cho chỗ SV tự điền) · **Điều kiện hoàn thành nhiệm vụ** (đo được) · **Câu hỏi** + dòng "Trả lời: ____".
6. (tuỳ chọn) **5. Ánh xạ khung tham chiếu.**

- **KHÔNG** đưa mục "Ghi chú triển khai (cho người xây lab)" và **không** lộ giá trị flag/lời giải vào file `.docx` phát cho sinh viên.
- Sinh `.docx`: dùng skill `docx` (python-docx). Nội dung lấy từ file spec `0X-*.md` tương ứng, cắt bỏ phần "Ghi chú triển khai".
- `docs/read_first.txt` mẫu:
  ```
  Tài liệu hướng dẫn: file://LAB_DOCS/<lab>.docx
  Mở bằng cách chuột phải → Open Link.
  ```

---

## 7. Quy trình build & test (tuần tự trên VM — tránh OOM)

1. **Cài designer kit 1 lần:** trích `scripts/designer` + `scripts/designer/base_dockerfiles` từ tarball master vào `$LABTAINER_DIR`; thêm `scripts/designer/bin` vào PATH.
2. **Scaffold:** `cd $LABTAINER_DIR/labs/<lab> && new_lab_setup.py` (thêm container: `new_lab_setup.py -a <name>`). Lấy template Dockerfile chuẩn từ đây.
3. **Điền nội dung** theo §1–§6.
4. **Build/chạy:** từ `scripts/labtainer-student`: `rebuild <lab>` (dùng `-f` nếu có xoá file). Xem log: `tail -f labtainer.log`.
5. **Test bằng solver:** chạy `solver.sh` trong container client (qua terminal hoặc `docker exec`) → phải lấy được flag.
6. **Chấm:** `stoplab <lab>` → chấm bằng `checkwork`/gradelab. Kiểm cả 2 chiều: giải đúng ⇒ PASS hết; không làm gì ⇒ FAIL.
7. **Sửa** tới khi đạt §0. Ghi lại vào `BUILD-NOTES.md`.
8. **Đóng gói phát hành:** tạo `<lab>.tar` (imodule) khi cần.

> **Chỉ build 1 lab tại một thời điểm.** Nhiều `docker build`/nhiều lab chạy song song sẽ làm treo VM.

---

## 8. Checklist rà soát cuối (mỗi bài)

- [ ] `rebuild` OK, container/terminal đúng sơ đồ, offline chạy được.
- [ ] Flag = `HASH_REPLACE` (per‑student), đặt trên container dịch vụ (SV không có shell).
- [ ] Không thể `cat`/`.bash_history` ra flag nếu chưa khai thác; đã thử "bypass ngây thơ" và thất bại.
- [ ] Mỗi nhiệm vụ có ≥1 goal đo được; có ≥1 goal hardening.
- [ ] `solver.sh` đạt toàn bộ goal; chấm "không làm gì" ⇒ FAIL.
- [ ] `docs/<lab>.docx` đúng format PTIT, không lộ lời giải/flag, không có mục "ghi chú triển khai".
- [ ] `BUILD-NOTES.md` ghi quyết định thiết kế + rủi ro tài nguyên.
