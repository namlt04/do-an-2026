# HƯỚNG DẪN THỰC HÀNH — Lab 3: Secret bị lộ trong lịch sử Git

- **Mã lab:** `dso-secrets-git`
- **Mức độ:** 2/4 (Trung bình)
- **Công cụ:** `git`, `gitleaks`, `jq`, `curl`, `mc` (MinIO Client)
- **Kiến thức cần:** commit/history của Git ở mức cơ bản, HTTP header `Authorization`, khái niệm S3/MinIO, secret rotation

> Guide này theo hướng **tư duy**: mỗi nhiệm vụ cho **mục tiêu + gợi ý + khung lệnh có chỗ trống `<...>`**. Bạn tự điền chỗ trống dựa trên gợi ý. Đáp án đầy đủ không có sẵn ở đây — hãy suy luận. Mức 2 nên khung lệnh gần đầy đủ.

## Bối cảnh
Một lập trình viên lỡ commit file cấu hình chứa khóa AWS, mật khẩu CSDL và API token, vài ngày sau "xóa" file đó bằng một commit mới và tưởng đã xong. Bạn đóng vai người có quyền đọc repo: đào lịch sử để moi secret, dùng chúng lấy flag, rồi chuyển sang vai DevSecOps để khắc phục đúng cách.

Sơ đồ: máy `dev` (terminal, repo tại `~/repo`, có `gitleaks`, `curl`, `jq`, `mc`, script `~/rotate_secrets.sh`) ↔ `app` (HTTP API, `http://app:8080`) và `storage` (MinIO, `http://storage:9000`, bucket private `corp-backups`).

```
dev (~/repo) --HTTP + token--> app:8080
             --S3 + AWS key--> storage:9000 (corp-backups)
```

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-secrets-git.tar
labtainer dso-secrets-git
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn).

---

## Nhiệm vụ 1 — Trinh sát lịch sử Git
**Mục tiêu:** Xác nhận HEAD đã "sạch" nhưng trong quá khứ file `deploy/credentials.yaml` từng được **thêm** rồi **xóa**; ghi lại hash hai commit đó.

**Gợi ý tư duy:**
- `git log` có tùy chọn xem toàn bộ nhánh và có bộ lọc theo **loại thay đổi của file** (Added / Deleted) cho một đường dẫn cụ thể.
- Dùng `--format=%H` để chỉ in hash. Nếu có nhiều dòng, nhớ thứ tự `git log` in từ mới đến cũ.
- Kiểm tra HEAD bằng `git show HEAD:<đường dẫn>` — kỳ vọng báo lỗi.

**Khung lệnh (điền chỗ trống):**
```bash
cd ~/repo
git log --oneline --all
git log --all --diff-filter=<A_HOẶC_D> --format=%H -- deploy/credentials.yaml   # chạy 2 lần: thêm / xóa
git show HEAD:deploy/credentials.yaml      # kỳ vọng: không tồn tại ở HEAD
cat > ~/recon_answers.txt <<EOF
ADD_COMMIT=<HASH_COMMIT_THÊM>
REMOVE_COMMIT=<HASH_COMMIT_XÓA>
EOF
```
**Hoàn thành khi:** `~/recon_answers.txt` chứa đúng 2 hash (thêm và xóa).

**Câu hỏi:** Vì sao file không còn ở HEAD mà secret vẫn lấy lại được? → ____

---

## Nhiệm vụ 2 — Quét history và trích xuất secret
**Mục tiêu:** Tạo báo cáo gitleaks (tối thiểu 2 finding) và trích đủ **4 giá trị**: AWS access key, AWS secret key, mật khẩu DB, API token.

**Gợi ý tư duy:**
- `gitleaks detect` quét **toàn bộ history** (khác `grep` chỉ nhìn thư mục hiện tại); cần chỉ nguồn repo và đường dẫn xuất báo cáo JSON.
- Báo cáo cho biết commit + file; từ đó đọc lại nội dung gốc bằng `git show <commit>:<file>` (dùng commit **thêm** file ở Nhiệm vụ 1).
- File là dạng YAML `khóa: giá trị`; hãy tìm tên các trường (`access_key_id`, `secret_access_key`, `password`, `token`).

**Khung lệnh:**
```bash
gitleaks detect --source ~/repo -v --report-path <FILE_BÁO_CÁO_JSON>
jq -r '.[] | "\(.RuleID)\t\(.Commit)\t\(.File)\t\(.Secret)"' ~/gitleaks.json
git -C ~/repo show <ADD_COMMIT>:deploy/credentials.yaml
cat > ~/secrets_found.txt <<EOF
AWS_ACCESS_KEY_ID=<GIÁ_TRỊ>
AWS_SECRET_ACCESS_KEY=<GIÁ_TRỊ>
DB_PASSWORD=<GIÁ_TRỊ>
API_TOKEN=<GIÁ_TRỊ>
EOF
```
**Hoàn thành khi:** `~/gitleaks.json` tồn tại (>= 2 finding) và `~/secrets_found.txt` đủ 4 dòng có giá trị.

**Câu hỏi:** Vì sao chỉ `grep` ở HEAD sẽ bỏ sót? gitleaks dựa vào đặc trưng nào để phát hiện secret? → ____

---

## Nhiệm vụ 3 — Dùng secret lộ để lấy flag
**Mục tiêu:** Chứng minh tác động thực tế: lấy flag qua ít nhất một hướng (khuyến nghị cả hai).

**Gợi ý tư duy:**
- **Hướng A (MinIO):** `mc alias set` nhận alias, URL, access key, secret key. Flag nằm trong bucket private `corp-backups`, đường dẫn con `flags/flag.txt`. `mc ls --recursive` giúp bạn khám phá cấu trúc.
- **Hướng B (API):** endpoint `/flag` trên `app` yêu cầu header `Authorization` kiểu **Bearer** mang API token. Phản hồi là JSON; dùng `jq -r` để lấy đúng trường chứa flag.

**Khung lệnh:**
```bash
# Hướng A
mc alias set leak http://storage:9000 <ACCESS_KEY> <SECRET_KEY>
mc ls --recursive leak
mc cat leak/<BUCKET>/<ĐƯỜNG_DẪN_FLAG> | tee ~/loot_storage.txt

# Hướng B
curl -s -H "Authorization: Bearer <API_TOKEN>" http://app:8080/flag | jq .
curl -s -H "Authorization: Bearer <API_TOKEN>" http://app:8080/flag | jq -r '.<TRƯỜNG_FLAG>' | tee ~/loot_api.txt
```
**Hoàn thành khi:** `~/loot_storage.txt` và/hoặc `~/loot_api.txt` chứa flag (chuỗi riêng của bạn).

**Câu hỏi:** Root cause nằm ở đâu? Ánh xạ với CWE-798 và MITRE T1552 thế nào? → ____

---

## Nhiệm vụ 4 — Khắc phục (vai DevSecOps)
**Mục tiêu:** (1) Rotate secret đã lộ và chứng minh key cũ bị từ chối; (2) `.gitignore` chặn file secret; (3) pre-commit hook chặn commit chứa secret.

**Gợi ý tư duy:**
- Secret đã lộ phải coi là **đã bị xâm phạm**: rotate là bước đầu tiên. Script lab cung cấp `~/rotate_secrets.sh` (cần quyền thực thi) sẽ tạo `~/loot_rotate.txt`.
- Sau rotate, thử lại **key cũ** với `mc ls`: kỳ vọng thất bại (exit code khác 0) -> ghi `RESULT=DENIED` vào cuối log.
- `.gitignore` phải chứa `.env`; kiểm tra bằng `git status`.
- Hook `.git/hooks/pre-commit` gọi `gitleaks protect --staged`; nếu phát hiện secret thì `exit 1`. Nhớ cấp quyền thực thi cho hook.
- Kiểm chứng hook: commit thử file chứa chuỗi giống AWS key; commit phải **thất bại** -> ghi `RESULT=COMMIT_BLOCKED`.

**Khung lệnh:**
```bash
# 1. Rotate + kiểm chứng key cũ
~/rotate_secrets.sh
mc alias set leak http://storage:9000 <ACCESS_KEY_CŨ> <SECRET_KEY_CŨ>
mc ls leak > ~/rotate_verify.log 2>&1
if [ $? -eq <MÃ_THÀNH_CÔNG> ]; then echo "RESULT=ALLOWED" >> ~/rotate_verify.log; else echo "RESULT=<KẾT_QUẢ_MONG_ĐỢI>" >> ~/rotate_verify.log; fi

# 2. .env + .gitignore
echo 'APP_API_TOKEN=<TOKEN_MỚI_TỰ_CHỌN>' > ~/repo/.env
cd ~/repo && printf '%s\n' '<MẪU_1>' '*.env' 'config/secrets.*' 'deploy/credentials.yaml' >> .gitignore
git status   # .env không được xuất hiện

# 3. pre-commit hook
cat > ~/repo/.git/hooks/pre-commit <<'HOOK'
#!/bin/sh
gitleaks protect --staged -v || { echo "[BLOCKED] Phat hien secret."; exit 1; }
HOOK
chmod <QUYỀN> ~/repo/.git/hooks/pre-commit

# 4. Kiểm chứng hook
echo 'aws_secret = "AKIAFAKE1234567890EX"' > test_leak.txt
git add test_leak.txt
git commit -m "test" > ~/precommit_test.log 2>&1
if [ $? -ne 0 ]; then echo "RESULT=<KẾT_QUẢ_MONG_ĐỢI>" >> ~/precommit_test.log; else echo "RESULT=COMMIT_SUCCEEDED" >> ~/precommit_test.log; fi
git reset -q HEAD test_leak.txt; rm -f test_leak.txt
```
**Hoàn thành khi:** `rotate_verify.log` có `RESULT=DENIED`, `~/loot_rotate.txt` tồn tại, `.gitignore` chứa `.env`, hook có quyền thực thi và `precommit_test.log` có `RESULT=COMMIT_BLOCKED`.

**Câu hỏi:** Vì sao purge history (`git filter-repo`/BFG) không thay thế được rotate? Sắp xếp thứ tự ưu tiên: rotate, purge history, `.gitignore`, pre-commit hook. → ____

---

## Chấm điểm
```bash
checkwork dso-secrets-git
```
Đạt khi cả 4 mục tiêu = **Y**: `recon_history`, `scan_secrets`, `exploit_get_flag`, `remediation_harden`.

**File bằng chứng cần có (ở `~`):**
- `~/recon_answers.txt` — hash commit thêm/xóa.
- `~/gitleaks.json`, `~/secrets_found.txt` — báo cáo quét và 4 credential.
- `~/loot_storage.txt` / `~/loot_api.txt` — flag (ít nhất một).
- `~/loot_rotate.txt`, `~/rotate_verify.log` (`RESULT=DENIED`) — bằng chứng rotate.
- `~/repo/.gitignore` (chứa `.env`), `~/precommit_test.log` (`RESULT=COMMIT_BLOCKED`) — shift-left.

> Gợi ý cuối: nếu một mục chưa Y, đọc lại **gợi ý tư duy** của nhiệm vụ đó và kiểm tra file bằng chứng; lưu ý các mục sau phụ thuộc kết quả mục trước (hash commit, 4 credential).
