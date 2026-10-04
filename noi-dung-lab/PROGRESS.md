# PROGRESS — Xây 5 bài lab Labtainer (đồ án 2026)

> File resume: đọc để tiếp tục nhanh. Cập nhật lần cuối: 2026-09-28.
> Rule: [LAB-BUILD-RULES.md](LAB-BUILD-RULES.md). Kết nối VM: memory `lab-vm-connection`.

## ✅ HOÀN THÀNH 5/5 (2026-10-04): build + solver + checkwork PASS, có .docx, đã push
- ✅ **cloud-s3-misconfig** — PASS 5/5 goal (MinIO thật).
- ✅ **dso-iac-scan** — PASS 4/4 goal (tfsec gate + CI service giữ flag).
- ✅ **dso-secrets-git** — PASS 9/9 goal (MinIO thật + Flask network2).
- ✅ **cloud-ssrf-imds** — PASS 4/4 goal (SSRF→IMDS→MinIO; unset session token).
- ✅ **dso-docker-escape** — PASS 6/6 goal (dind host-sim; khai thác qua Docker daemon TCP 2375).
Mỗi bài: flag per-student (HASH_REPLACE) chống bypass; `docs/<lab>.docx` (pandoc). Repo đã push origin/master.

### Bài học grading Labtainer (ÁP DỤNG MỌI BÀI) — đã kiểm chứng:
1. **results.config grammar**: `name = container:file : <tokenidx> : <LINE_TYPE> : <match>`. Dùng **`REGEX : .+`** để lấy token1 dòng bất kỳ. **KHÔNG dùng `LINE`** (bug `lineno` undefined trong ResultParser). Boolean "file chứa chuỗi": `container:file : CONTAINS : <str>`. KHÔNG có field `content`.
2. **goals.config**: literal so sánh phải `answer=<val>` (vd `string_equal : r : answer=OK`); so parameter: `string_equal : r : parameter.X`.
3. **Flag/cred phải BARE** (= đúng giá trị HASH_REPLACE, KHÔNG bọc `FLAG{}`/`AKIA`/`PTIT{}`) để khớp `parameter.*`.
4. **Tên network RIÊNG từng bài** (S3_NET/IAC_NET/SECGIT_NET/SSRF_NET/ESCAPE_NET) — dùng chung `LAB_NET` gây "Invalid address ... network's subnet" khi chuyển bài.
5. **ADD-HOST**: cú pháp `ADD-HOST host:ip` (KHÔNG `-- NET`, gây lỗi "image lab_net"). Thêm full-mesh để app dùng tên host.
6. **Grader container KHÔNG có `git`**; artifact **không giữ bit +x**; `.git` CÓ được thu (grep hash commit được). Tránh phụ thuộc git/exec-perm trong pregrade.
7. **MinIO**: build-from-source (`_shared/bin/{minio,mc}`) inject qua `<container>/sys_tar/sys.tar`; bỏ `dl.min.io`; base `network2` cho Flask/aws-cli.
8. **Quy trình/bài**: deploy (tar/scp) → inject binary → `rebuild <lab>` (Xvfb, DISPLAY=:99) → `docker cp solver.sh` + chạy → `checkwork` → đọc grades: `docker exec <lab>-igrader ... python3 instructor.py` rồi `cat /home/instructor/<lab>.grades.txt`.

## Trạng thái tổng quan
- ✅ **AUTHOR xong 5/5 bài** (file nguồn trong `labs/<lab>/`): dso-iac-scan, dso-secrets-git, cloud-s3-misconfig, cloud-ssrf-imds, dso-docker-escape. Mỗi bài có config, dockerfiles, service, grading (results/goals/pregrade), `docs/<lab>-guide.md`, `solver.sh`, `BUILD-NOTES.md`.
- 🔄 **BUILD/TEST**: đang làm, tuần tự. Chưa bài nào PASS đủ (build+solver+chấm).
- Deliverable còn thiếu: convert `docs/<lab>-guide.md` → `.docx` (bằng pandoc trên VM), làm sau khi mỗi lab chạy được.

## VM
`student@192.168.17.139`, khóa `~/.ssh/lab_student`, sudo `password123`. Labtainer `~/labtainer/trunk` (`$LABTAINER_DIR`). Đã cài designer kit + pandoc. Build headless từ `$LABTAINER_DIR/scripts/labtainer-student`: `LABTAINER_DIR=... ./bin/rebuild -b <lab>` (`-b`=chỉ build, không mở terminal). Test full cần **Xvfb** (VM chưa cài X) → cài: `sudo apt-get install -y xvfb`, rồi `Xvfb :99 & export DISPLAY=:99` trước `rebuild <lab>` (không `-b`).

## ⚠️ 3 vấn đề hệ thống ĐÃ CHẨN ĐOÁN + cách sửa (áp cho mọi bài)
1. **URL binary 404**: audit trước khi build. Đã biết: trivy phải `v0.74.0` (không phải 0.53.0; naming `trivy_<v>_Linux-64bit.tar.gz`). OK sẵn: tfsec v1.28.13, gitleaks v8.18.4, trufflehog v3.75.0, terraform 1.9.8, awscli.
2. **MinIO gỡ binary công khai** (dl.min.io 410; Docker Hub `minio/minio`+`minio/mc` = **404 đã xóa**, chỉ còn operator/warp; quay/bitnami/login đều không được). → **GIẢI PHÁP CHỐT: build MinIO+mc TỪ NGUỒN** (mã vẫn mở GitHub). Đã build xong, binary THẬT tại **`$LABTAINER_DIR/labs/_shared/bin/{minio,mc}`** (minio 145MB, mc 43MB, static). Smoke-test OK (health 200, mc mb/cp/ls, anonymous GET bucket private = 403 → chống bypass đạt). `s3lite.py` giữ làm fallback.
   - **Cách build (nếu cần build lại)**: build THẲNG TRÊN HOST (không trong docker — docker 20.10.7 seccomp chặn toolchain mới): tải Go 1.24 (`https://go.dev/dl/go1.24.0.linux-amd64.tar.gz`) giải nén /tmp/goroot; `PATH=/tmp/goroot/bin:$PATH GOBIN=/tmp/mout CGO_ENABLED=0 go install github.com/minio/mc@latest` và `.../minio@latest`.
   - **Cách nhét vào lab (INJECT)**: KHÔNG tải trong Dockerfile. Bỏ dòng `curl dl.min.io`. Nhét binary vào image qua `<container>/sys_tar/sys.tar` (chứa `usr/local/bin/{minio,mc}`) — hàm `mk_systar` tạo sau khi deploy, TRƯỚC rebuild (binary KHÔNG commit vào repo vì to; inject trên VM). Client cần mc; storage cần minio+mc.
   - Client/aws-cli: đổi base container đó sang **network2** (aws-cli v1 pip cần python3.8; network chỉ có py2). storage (chỉ chạy minio/mc static) giữ network cũng được.
3. **`labtainer.network` KHÔNG có python3** (chỉ python2 + pip 8.1.1 → Flask/pip modern HỎNG). → Container chạy Python (Flask/s3lite/imds/gate) phải đổi base sang **`labtainer.network2`** (Python 3.8.5 + pip 21) hoặc `base2`. Dùng `pip3`. Container chỉ cần binary (tfsec/trivy/gitleaks) giữ base nào cũng được (devsecops đã build OK trên `network`).

## Tiến độ từng bài
| Bài | MinIO? | Build image | Ghi chú |
|---|---|---|---|
| dso-iac-scan | không | `devsecops` ✅ (1.27GB, trivy fixed); `ci` build xong (851MB) nhưng **Flask KHÔNG import được** (Python 3.5, base=network) | Fix: đổi FROM `ci`→`labtainer.network2` (py3.8) HOẶC viết lại gate bằng stdlib http.server (như s3lite). Rebuild `ci` rồi test+chấm. |
| dso-docker-escape | không | chưa build | dind trên host-sim; NO_PRIVILEGE cho app. Base app cần python? nếu socat only thì network ok. |
| dso-secrets-git | CÓ | chưa build | Retrofit MinIO→s3lite; app(Flask)→network2; bỏ mc; git-history builder ở `_bin/`. |
| cloud-s3-misconfig | CÓ | chưa build | Retrofit MinIO→s3lite (public+private bucket); client aws-cli/curl. |
| cloud-ssrf-imds | CÓ | chưa build | web+imds Flask→network2; storage→s3lite; giữ khớp cred imds↔storage. |

## NEXT STEPS (thứ tự)
1. **dso-iac-scan**: sửa base `ci`→`labtainer.network2` trong `dockerfiles/Dockerfile.dso-iac-scan.ci.student` (đảm bảo Flask cài bằng pip3); nếu muốn né Flask hẳn có thể chuyển gate sang stdlib http.server. Redeploy iac-scan → `rebuild -b dso-iac-scan` → cài Xvfb → `rebuild dso-iac-scan` (full, cần email SV: dùng `-p` hoặc email lưu sẵn) → chạy `solver.sh` trong `devsecops` → `stoplab` → chấm 2 chiều.
2. **dso-docker-escape**: `rebuild -b` → sửa lỗi → full test (dind là rủi ro chính).
3. **Retrofit 3 bài storage** MinIO→s3lite (có thể giao subagent Sonnet mỗi bài, KÈM `labs/_shared/s3lite.py` + hướng dẫn base network2). Rồi build/test từng bài.
4. Với mỗi bài PASS: convert guide→docx: `pandoc docs/<lab>-guide.md -o docs/<lab>.docx` (trên VM), scp về repo.
5. Rà checklist §8 RULE cho từng bài.

## Lệnh hay dùng (từ máy này)
```bash
SSH="ssh -i /c/Users/namlt/.ssh/lab_student -o BatchMode=yes -o LogLevel=ERROR student@192.168.17.139"
# deploy 1 lab: tar repo → scp → giải nén đè trên VM (xem lịch sử: dùng --force-local cho path Windows)
# build headless: $SSH 'cd $LT/scripts/labtainer-student && LABTAINER_DIR=$LT ./bin/rebuild -b <lab>'
# log build: $SSH 'tail -40 $LT/logs/docker_build.log'
```

## Lưu ý background task
Task build iac-scan trước (`bowrian7u`) đã dừng nửa chừng (devsecops xong, ci fail Flask). Không cần khôi phục task đó — chỉ cần sửa base ci rồi rebuild lại.
