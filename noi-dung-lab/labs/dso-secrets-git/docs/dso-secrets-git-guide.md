# Học viện Công nghệ Bưu chính Viễn thông - SecLab PTIT
## HƯỚNG DẪN THỰC HÀNH
# dso-secrets-git — Phát hiện, khai thác và khắc phục Secret bị lộ trong lịch sử Git

**Mức độ:** Trung bình  **·**  **Phân loại:** DevSecOps / Secrets Management  **·**  **Ánh xạ:** OWASP DevSecOps (Secrets Management) · MITRE ATT&CK T1552 (Unsecured Credentials) · CWE-798 (Use of Hard-coded Credentials)

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `dso-secrets-git` |
| **Mức độ** | Trung bình |
| **Công cụ sử dụng** | `git`, `gitleaks`, `grep`, `curl`, `jq`, `mc` (MinIO Client) |
| **Kiến thức yêu cầu** | Sử dụng dòng lệnh Linux cơ bản; hiểu khái niệm commit/lịch sử của Git ở mức tối thiểu (không cần kinh nghiệm chuyên sâu — lab sẽ nhắc lại ở mục Kiến thức bổ trợ) |

**Mục tiêu học tập**
- Hiểu vì sao xóa một secret ở HEAD **không** loại bỏ được nó khỏi kho lưu trữ — secret vẫn tồn tại vĩnh viễn trong lịch sử commit và có thể bị truy xuất lại.
- Nắm được cách kẻ tấn công (T1552 — Unsecured Credentials) đào bới toàn bộ lịch sử Git để tìm khóa AWS, mật khẩu CSDL, API token bị hard-code (CWE-798).
- Biết dùng công cụ quét secret tự động (gitleaks) và đối chiếu với quét thủ công bằng `git log -p` / `git rev-list`.
- Hiểu quy trình khắc phục đúng chuẩn DevSecOps: xoay vòng (rotate) secret, loại secret khỏi history, đưa secret ra biến môi trường/secret manager, chặn secret ngay từ commit bằng pre-commit hook.
- Ánh xạ được rủi ro thực tế vào các khung tham chiếu OWASP DevSecOps, MITRE ATT&CK, CWE.

**Kỹ năng đạt được**
- Kỹ năng duyệt và truy vấn lịch sử Git để phát hiện dữ liệu nhạy cảm đã bị "xóa" ở commit sau nhưng còn trong history.
- Kỹ năng vận hành gitleaks ở chế độ offline để quét toàn bộ history và đọc báo cáo (rule, commit, file, dòng).
- Kỹ năng dùng credential thu được để xác thực vào một dịch vụ mục tiêu (HTTP API / MinIO object storage) và trích xuất dữ liệu.
- Kỹ năng khắc phục: viết `.gitignore`, tách secret ra biến môi trường, cấu hình pre-commit hook quét secret trước khi commit, và trình bày quy trình rotate + purge history.
- Tư duy đánh giá rủi ro: phân biệt "che giấu" (xóa ở HEAD) với "khắc phục thực sự" (rotate + loại khỏi history).

---

## 2. Kịch bản

**Tình huống:**
Một nhóm phát triển nội bộ của công ty đã đẩy mã nguồn dịch vụ backend lên một Git repository dùng chung. Trong quá trình phát triển, lập trình viên vô tình commit cả file cấu hình chứa khóa AWS, mật khẩu CSDL và API token. Vài ngày sau, họ nhận ra sai sót và tạo một commit mới để "xóa" file này khỏi HEAD, tưởng rằng sự cố đã được xử lý. Trên thực tế, toàn bộ credential vẫn nằm nguyên trong **lịch sử commit** và bất kỳ ai clone được repo đều có thể lấy lại.

Sinh viên đóng vai một **security engineer / attacker** đã có quyền đọc repository nội bộ này (đã được dựng sẵn về máy `dev`). Nhiệm vụ là chứng minh rủi ro: đào toàn bộ history để moi ra các secret bị lộ, dùng chính credential đó để truy cập dịch vụ mục tiêu (một API HTTP nội bộ và một MinIO object store) nhằm lấy **flag**, sau đó chuyển sang vai DevSecOps engineer để **khắc phục** đúng cách.

**Vai trò của sinh viên:**
- Trên máy `dev`: duyệt lịch sử Git bằng `git log`, `git rev-list`, `git log -p` để phát hiện các commit đã từng chứa secret.
- Chạy công cụ quét secret offline (gitleaks) trên toàn bộ history để tự động hóa việc phát hiện và xác định loại secret.
- Dùng credential thu được (AWS key giả / mật khẩu DB / API token) để truy cập dịch vụ mục tiêu (`app` — HTTP API và `storage` — MinIO) và lấy flag.
- Thực hiện **remediation**: rotate secret, đưa secret ra biến môi trường, cấu hình `.gitignore` + pre-commit hook chặn secret, và trình bày quy trình loại secret khỏi history.

**Sơ đồ mạng**

```
                         Mang ao Labtainer (172.32.0.0/24)
+------------------------+           +--------------------------------+
|  dev (client)          |           |  app  (HTTP API - target)      |
|  172.32.0.10           |  HTTP/API |  172.32.0.20 : 8080            |
|  - git repo ~/repo     |---------->|  Xac thuc bang API token / DB  |
|  - gitleaks |           |  password; tra flag khi hop le |
|  - curl / jq / mc      |           +--------------------------------+
|  - ~/rotate_secrets.sh |
|  (noi sinh vien go     |  S3/API   +--------------------------------+
|   lenh)                |---------->|  storage (MinIO - target)      |
+------------------------+           |  172.32.0.30 : 9000            |
                                      |  Access/Secret key = AWS key   |
                                      |  gia lo trong history; bucket  |
                                      |  private chua object flag      |
                                      +--------------------------------+

Luong: dev dao secret trong history -> dung token/DB password truy cap app
       (HTTP) va dung AWS key gia truy cap storage (MinIO) -> lay flag
       -> remediation (rotate + shift-left) tren repo tai dev.
```

---

## 3. Kiến thức bổ trợ

**Kiến thức nền tảng**

- **Secrets management (quản lý bí mật):** secret là mọi thông tin cần giữ kín để hệ thống hoạt động an toàn — mật khẩu, API token, khóa truy cập cloud (AWS access key/secret key), private key, connection string CSDL. Nguyên tắc cốt lõi của DevSecOps: **không bao giờ hard-code secret trong mã nguồn hay commit vào Git**; thay vào đó dùng biến môi trường, file cấu hình được `.gitignore`, hoặc secret manager (Vault, AWS Secrets Manager, Docker/K8s secrets).

- **Git lưu lịch sử bất biến:** mỗi commit là một ảnh chụp (snapshot) của toàn bộ cây thư mục tại thời điểm đó, được liên kết thành chuỗi qua các con trỏ cha. Khi bạn xóa một file và commit lại, bạn chỉ tạo **một commit mới** không còn file đó ở HEAD; các commit cũ (và blob dữ liệu bên trong) vẫn nằm nguyên trong `.git`. Vì thế **`git rm` + commit KHÔNG xóa secret khỏi repo** — bất kỳ ai cũng có thể `git checkout` hoặc `git log -p` để lấy lại. Đây là gốc rễ của cả bài lab.

- **CWE-798 — Hard-coded Credentials:** lỗ hổng khi credential được nhúng trực tiếp trong mã/cấu hình. Kể cả khi "xóa" đi, credential đã lộ phải được coi là **đã bị xâm phạm (compromised)** và bắt buộc phải rotate.

- **MITRE ATT&CK T1552 — Unsecured Credentials:** kỹ thuật attacker tìm credential lộ lọt trong file, lịch sử shell, biến môi trường, hoặc — như bài này — **lịch sử kho mã nguồn (T1552.001 Credentials In Files)**.

- **Quét secret (secret scanning):** công cụ như **gitleaks** duyệt qua toàn bộ commit, dùng tập luật regex/entropy để phát hiện chuỗi giống secret (ví dụ pattern `AKIA...` của AWS access key). Điểm mạnh so với quét thủ công: quét được **mọi commit trong history**, không chỉ HEAD.

- **git filter-repo / BFG Repo-Cleaner:** công cụ để **viết lại lịch sử** nhằm loại bỏ hẳn một file/chuỗi secret khỏi mọi commit. Đây là bước "purge history" — nhưng phải nhớ: purge history **không thay thế** cho rotate, vì secret có thể đã bị sao chép/lộ ở nơi khác.

- **Pre-commit hook:** script chạy tự động **trước khi** một commit được tạo (trong `.git/hooks/pre-commit`). Có thể gọi gitleaks để chặn commit chứa secret ngay từ đầu — "shift-left" đúng tinh thần DevSecOps.

**Thành phần cần quan sát trong bài lab**

| Thành phần | Vai trò |
|---|---|
| Repo git tại `~/repo` trên máy `dev` | Kho mã nguồn đã dựng sẵn, có lịch sử commit trong đó secret từng được thêm rồi bị "xóa" ở commit sau. Đối tượng chính để đào bới. |
| File cấu hình bị lộ (`deploy/credentials.yaml`) | File từng chứa AWS key giả, DB password, API token; ở HEAD hiện tại đã bị gỡ nhưng còn trong history. |
| Báo cáo gitleaks | Kết quả quét, cho biết rule khớp, commit hash, đường dẫn file và giá trị secret bị lộ. |
| Dịch vụ `app` (HTTP API, `172.32.0.20:8080`) | Nhận xác thực bằng API token / mật khẩu DB tìm được; trả flag khi credential hợp lệ. Cũng là nơi tiếp nhận yêu cầu rotate. |
| Dịch vụ `storage` (MinIO, `172.32.0.30:9000`) | Object storage tương thích S3; access key/secret key chính là cặp AWS key giả lộ trong history; bucket `corp-backups` (private) chứa object flag tại `flags/flag.txt`. |
| `~/rotate_secrets.sh` | Script do lab cung cấp, mô phỏng bước rotate credential (Nhiệm vụ 4). |
| `flag` | Chuỗi mục tiêu, lấy được sau khi dùng credential lộ để truy cập dịch vụ. |

**Bảng tùy chọn và cú pháp công cụ sử dụng trong bài**

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `git` | `git log --oneline --all` | Liệt kê tóm tắt toàn bộ commit trên mọi nhánh để nắm dòng thời gian. |
| `git` | `git log --oneline --stat --all` | Xem commit kèm danh sách file thay đổi — phát hiện commit nào thêm/xóa file cấu hình nhạy cảm. |
| `git` | `git rev-list --all` | Liệt kê tất cả commit hash trên mọi ref — làm đầu vào để rà từng commit. |
| `git` | `git log -p [-- <path>]` | Hiển thị diff đầy đủ của từng commit (có thể giới hạn theo file); nội dung secret bị thêm/xóa sẽ hiện ra trong diff. |
| `git` | `git log -S '<chuỗi>' --oneline --all` | "Pickaxe": tìm các commit làm thay đổi số lần xuất hiện của một chuỗi (vd `AKIA`, `password`). |
| `git` | `git show <commit>:<path>` | In nội dung một file đúng như nó tồn tại tại một commit cụ thể trong quá khứ. |
| `gitleaks` | `gitleaks detect --source <repo> -v --report-path <out.json>` | Quét toàn bộ lịch sử Git tìm secret theo tập luật, in chi tiết và xuất báo cáo JSON. |
| `grep` | `grep -RniE 'AKIA\|password\|secret\|token' <dir>` | Lọc nhanh chuỗi nghi là secret trong output hoặc file. |
| `curl` | `curl -s -H 'Authorization: Bearer <token>' http://app:8080/flag` | Gửi request HTTP kèm API token để truy cập dịch vụ `app`. |
| `jq` | `... \| jq -r '.flag'` | Định dạng và trích trường từ phản hồi JSON. |
| `mc` (MinIO Client) | `mc alias set <name> http://storage:9000 <ACCESS_KEY> <SECRET_KEY>` | Cấu hình kết nối tới MinIO bằng cặp key lộ lọt. |
| `mc` | `mc ls <name>` / `mc cat <name>/<bucket>/<obj>` | Liệt kê bucket/object và đọc nội dung object (chứa flag). |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-secrets-git.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer dso-secrets-git
```

(chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm)

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy làm việc: `dev`. Repository đã được dựng sẵn tại `~/repo`.

---

### Nhiệm vụ 1 — `recon_history`: Trinh sát lịch sử Git và xác định commit nghi vấn

**Mục tiêu:** Nắm toàn cảnh lịch sử commit, xác nhận rằng ở HEAD hiện tại không còn file cấu hình nhạy cảm, nhưng trong quá khứ đã từng có file như vậy được thêm rồi xóa.

**Bước 1:** Vào thư mục repo và xem cây lịch sử tóm tắt:
```bash
cd ~/repo
git log --oneline --all
```

**Bước 2:** Xem lịch sử kèm thống kê file để tìm commit thêm/xóa file cấu hình:
```bash
git log --oneline --stat --all
```

**Bước 3:** Xác nhận HEAD hiện tại đã "sạch" (file cấu hình không còn):
```bash
ls -la
git show HEAD:deploy/credentials.yaml   # ky vong: bao loi "does not exist in HEAD"
```

**Bước 4:** Dùng pickaxe để khoanh vùng commit từng đụng tới secret:
```bash
git log -S 'password' --oneline --all
git log -S 'AKIA' --oneline --all
```

**Bước 5 (ghi lại kết quả):** Xác định đúng commit **thêm** và commit **xóa** file `deploy/credentials.yaml`, rồi lưu hash của chúng vào một file worksheet:
```bash
cat > ~/recon_answers.txt <<EOF
ADD_COMMIT=<hash_commit_them_deploy_credentials.yaml>
REMOVE_COMMIT=<hash_commit_xoa_deploy_credentials.yaml>
EOF
cat ~/recon_answers.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Sinh viên liệt kê được toàn bộ commit, chỉ ra được đúng **một commit thêm** file cấu hình nhạy cảm và đúng **một commit xóa** file đó (ghi trong `~/recon_answers.txt`), đồng thời xác nhận HEAD hiện tại không còn file này.

**Câu hỏi 1:** Vì sao việc file cấu hình "không còn thấy ở HEAD" hoàn toàn không có nghĩa là secret đã được loại khỏi repository? Điều gì trong cơ chế lưu trữ của Git khiến secret vẫn có thể lấy lại được?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `scan_secrets`: Quét toàn bộ history và trích xuất secret

**Mục tiêu:** Dùng công cụ quét secret offline (gitleaks) kết hợp với `git log -p` để moi ra chính xác các credential (AWS key giả, DB password, API token) đã lộ trong history.

**Bước 1:** Chạy gitleaks trên toàn bộ lịch sử của repo và xuất báo cáo:
```bash
gitleaks detect --source ~/repo -v --report-path ~/gitleaks.json
```

**Bước 2:** Đọc báo cáo, xem các rule đã khớp, commit và file liên quan:
```bash
jq -r '.[] | "\(.RuleID)\t\(.Commit)\t\(.File)\t\(.Secret)"' ~/gitleaks.json
```

**Bước 3 (đối chiếu / dự phòng):** Dùng "pickaxe" của Git để truy ngược các commit từng thêm/xóa chuỗi nhạy cảm (đối chiếu với báo cáo gitleaks):
```bash
git -C ~/repo log -S 'AKIA' --oneline --all
git -C ~/repo log -S 'password' --oneline --all
```

**Bước 4 (xác minh thủ công):** Với commit và file mà công cụ chỉ ra, đọc lại nội dung gốc để lấy đúng giá trị secret:
```bash
git log -p -- deploy/credentials.yaml
git show <commit_hash>:deploy/credentials.yaml
```

**Bước 5 (ghi lại kết quả):** Ghi lại chính xác 4 giá trị credential thu được vào worksheet:
```bash
cat > ~/secrets_found.txt <<EOF
AWS_ACCESS_KEY_ID=<gia_tri_dao_duoc>
AWS_SECRET_ACCESS_KEY=<gia_tri_dao_duoc>
DB_PASSWORD=<gia_tri_dao_duoc>
API_TOKEN=<gia_tri_dao_duoc>
EOF
cat ~/secrets_found.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Sinh viên tạo được báo cáo quét (`~/gitleaks.json`, tối thiểu 2 finding) và trích xuất chính xác cả 4 giá trị credential vào `~/secrets_found.txt`. Các giá trị này dùng tiếp ở Nhiệm vụ 3.

**Câu hỏi 2:** So sánh việc quét bằng công cụ tự động (gitleaks quét toàn history) với việc chỉ dùng `grep` trên thư mục làm việc hiện tại. Vì sao chỉ `grep` ở HEAD sẽ bỏ sót secret trong bài này, và công cụ quét dựa vào những đặc trưng nào (pattern, entropy) để phát hiện?
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `exploit_get_flag`: Dùng credential lộ để truy cập dịch vụ mục tiêu và lấy flag

**Mục tiêu:** Chứng minh tác động thực tế của secret bị lộ — dùng credential thu được để xác thực vào dịch vụ mục tiêu và lấy flag. Có hai đường khai thác (thực hiện ít nhất một, khuyến nghị cả hai).

**Hướng A — Object storage (MinIO / AWS key giả), dịch vụ `storage` (172.32.0.30:9000):**

**Bước A1:** Cấu hình client MinIO bằng cặp AWS key giả tìm được:
```bash
mc alias set leak http://storage:9000 <ACCESS_KEY> <SECRET_KEY>
```

**Bước A2:** Liệt kê bucket và object:
```bash
mc ls leak
mc ls --recursive leak
```

**Bước A3:** Đọc object chứa flag và lưu lại:
```bash
mc cat leak/corp-backups/flags/flag.txt | tee ~/loot_storage.txt
```

**Hướng B — HTTP API (API token / DB password), dịch vụ `app` (172.32.0.20:8080):**

**Bước B1:** Thử gọi endpoint yêu cầu xác thực bằng API token tìm được:
```bash
curl -s -H "Authorization: Bearer <API_TOKEN>" http://app:8080/flag | jq .
```

**Bước B2:** Nếu muốn xác thực bằng mật khẩu DB / Basic Auth (thay cho Bước B1):
```bash
curl -s -u appuser:<db_password> http://app:8080/flag | jq .
```

**Bước B3:** Trích flag từ phản hồi JSON và lưu lại:
```bash
curl -s -H "Authorization: Bearer <API_TOKEN>" http://app:8080/flag | jq -r '.flag' | tee ~/loot_api.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Sinh viên truy cập thành công vào ít nhất một dịch vụ mục tiêu bằng credential lộ trong history, và lưu đúng giá trị flag vào `~/loot_storage.txt` (hướng A) và/hoặc `~/loot_api.txt` (hướng B). Khuyến nghị hoàn thành cả hai hướng để đối chiếu.

**Câu hỏi 3:** Trình bày lại toàn bộ chuỗi tấn công: từ lúc phát hiện repo tưởng như "sạch" đến khi lấy được flag. Theo bạn, nguyên nhân gốc rễ (root cause) của sự cố nằm ở đâu, và nó ánh xạ với CWE-798 cũng như MITRE ATT&CK T1552 như thế nào?
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `remediation_harden`: Khắc phục và ngăn ngừa tái diễn (DevSecOps)

**Mục tiêu:** Chuyển sang vai DevSecOps engineer, xử lý sự cố đúng chuẩn: coi secret đã lộ là đã bị xâm phạm, rotate, tách secret ra khỏi mã, và chặn secret ngay từ commit trong tương lai.

**Bước 1 — Rotate (xoay vòng) secret đã lộ:** Chạy script mô phỏng rotate do lab cung cấp (script này sẽ tự đào lại credential gốc từ `~/repo` và gọi API rotate trên `app`):
```bash
~/rotate_secrets.sh
```
Script sẽ báo kết quả và lưu "rotate proof" vào `~/loot_rotate.txt` nếu thành công. Sau đó, tự kiểm chứng credential CŨ không còn truy cập được, đồng thời ghi lại kết quả chuẩn hóa:
```bash
mc alias set leak http://storage:9000 <ACCESS_KEY_CU> <SECRET_KEY_CU>
mc ls leak > ~/rotate_verify.log 2>&1
if [ $? -eq 0 ]; then
  echo "RESULT=ALLOWED" >> ~/rotate_verify.log
else
  echo "RESULT=DENIED" >> ~/rotate_verify.log
fi
cat ~/rotate_verify.log   # ky vong: RESULT=DENIED
```

**Bước 2 — Tách secret ra biến môi trường:** Sửa mã/cấu hình để đọc secret từ biến môi trường thay vì hard-code, và tạo file `.env` (KHÔNG commit):
```bash
# ví dụ trong mã: đọc os.environ["APP_API_TOKEN"] thay vì gán chuỗi cứng
echo 'APP_API_TOKEN=<token_moi_tu_chon>' > ~/repo/.env
echo 'AWS_ACCESS_KEY_ID=<key_moi_tu_chon>' >> ~/repo/.env
```

**Bước 3 — Thêm `.gitignore` để không commit file secret:**
```bash
cd ~/repo
printf '%s\n' '.env' '*.env' 'config/secrets.*' 'deploy/credentials.yaml' >> .gitignore
git status   # ky vong: .env KHONG xuat hien trong danh sach duoc theo doi
```

**Bước 4 — Cài pre-commit hook quét secret (shift-left):** Tạo hook chạy gitleaks trước mỗi commit để chặn secret ngay từ đầu:
```bash
cat > ~/repo/.git/hooks/pre-commit <<'HOOK'
#!/bin/sh
gitleaks protect --staged -v || {
  echo "[BLOCKED] Phat hien secret trong thay doi duoc staged. Commit bi huy."
  exit 1
}
HOOK
chmod +x ~/repo/.git/hooks/pre-commit
```

**Bước 5 — Kiểm chứng hook hoạt động:** Thử tạo một thay đổi có chứa secret giả và commit; hook phải chặn. Ghi lại kết quả chuẩn hóa:
```bash
cd ~/repo
echo 'aws_secret = "AKIAFAKE1234567890EX"' > test_leak.txt
git add test_leak.txt
git commit -m "test" > ~/precommit_test.log 2>&1
if [ $? -ne 0 ]; then
  echo "RESULT=COMMIT_BLOCKED" >> ~/precommit_test.log
else
  echo "RESULT=COMMIT_SUCCEEDED" >> ~/precommit_test.log
fi
cat ~/precommit_test.log   # ky vong: RESULT=COMMIT_BLOCKED
git reset -q HEAD test_leak.txt 2>/dev/null; rm -f test_leak.txt   # don dep (tuy chon)
```

**Bước 6 — Ghi chú quy trình purge history (khái niệm):** Trình bày (bằng văn bản, có thể kèm lệnh) cách loại secret khỏi toàn bộ history bằng `git filter-repo` hoặc **BFG Repo-Cleaner**, ví dụ:
```bash
# git filter-repo --path deploy/credentials.yaml --invert-paths
# hoac: java -jar bfg.jar --delete-files credentials.yaml
```
và giải thích vì sao bước này vẫn **không thay thế** cho việc rotate ở Bước 1.

**Điều kiện hoàn thành nhiệm vụ:** (1) Credential cũ đã bị vô hiệu sau rotate (kiểm chứng qua `~/rotate_verify.log`, và `~/loot_rotate.txt` chứa đúng rotate-proof lấy từ `app`); (2) `.gitignore` ngăn `.env`/file secret khỏi bị theo dõi; (3) pre-commit hook (`~/repo/.git/hooks/pre-commit`, có quyền thực thi) chặn thành công một commit thử chứa secret (`~/precommit_test.log` ghi nhận `RESULT=COMMIT_BLOCKED`). Sinh viên nêu được lý do purge history không thay thế rotate.

**Câu hỏi 4:** Sắp xếp các biện pháp sau theo thứ tự ưu tiên khi xử lý một secret vừa bị lộ trong Git và giải thích ngắn gọn: (a) rotate secret, (b) xóa secret khỏi history bằng filter-repo/BFG, (c) thêm `.gitignore`, (d) cài pre-commit hook. Vì sao "rotate" gần như luôn là việc phải làm đầu tiên và không thể bỏ qua?
Trả lời: _______________________________________

---

## 5. Ánh xạ khung tham chiếu

| Khung | Mục/kỹ thuật liên quan |
|---|---|
| OWASP DevSecOps Guideline | Secrets Management |
| MITRE ATT&CK | T1552 / T1552.001 — Unsecured Credentials: Credentials In Files |
| CWE | CWE-798 — Use of Hard-coded Credentials |
