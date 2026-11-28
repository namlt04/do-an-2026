Học viện Công nghệ Bưu chính Viễn thông - SecLab PTIT
HƯỚNG DẪN THỰC HÀNH
Bảo mật Infrastructure as Code — Shift-Left Scanning cho Terraform (devops-iac-scan)
Mức độ: Trung bình
DevOps / Cloud Security / IaC

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `devops-iac-scan` |
| **Mức độ** | Trung bình |
| **Công cụ sử dụng** | `tfsec`, `trivy config`, `terraform` (validate/plan), `grep`, `git diff` |
| **Kiến thức yêu cầu** | Cú pháp cơ bản Terraform (block `resource`, `variable`, HCL); khái niệm cloud cơ bản (VPC, Security Group, S3, IAM, EC2); dòng lệnh Linux; đọc hiểu output JSON/bảng. Bài **độc lập**, các khái niệm cần thiết được nhắc lại ở mục 3. |

**Mục tiêu học tập**
- Hiểu triết lý **shift-left security**: phát hiện và sửa lỗi cấu hình hạ tầng ở giai đoạn viết mã, TRƯỚC khi triển khai lên cloud thật, thay vì vá lỗi khi đã chạy production.
- Nắm được các dạng **misconfiguration kinh điển** trong Infrastructure as Code (Security Group mở toàn bộ Internet, S3 public/không mã hóa, secret hardcode, IAM policy quá rộng, tắt logging).
- Biết cách sử dụng các công cụ **quét tĩnh IaC** (tfsec, trivy) để liệt kê, phân loại rủi ro theo mức độ nghiêm trọng và đọc hiểu rule ID.
- Ánh xạ được lỗi cấu hình tới nguy cơ thực tế và tới các khung tham chiếu **OWASP IaC**, **CIS Benchmarks**, **MITRE ATT&CK for Cloud**.

**Kỹ năng đạt được**
- Kỹ năng chạy pipeline quét IaC offline và diễn giải báo cáo (HIGH/CRITICAL/MEDIUM, rule ID, dòng mã vi phạm).
- Kỹ năng **khắc phục (remediation)** mã Terraform để đạt tiêu chí bảo mật: siết Security Group, bật mã hóa/chặn public S3, loại bỏ secret hardcode, áp dụng least-privilege cho IAM, bật logging.
- Kỹ năng thẩm định kết quả sửa lỗi bằng cách **quét lại** và so sánh `git diff`.
- Tư duy DevSecOps: coi cấu hình an toàn là một phần của định nghĩa "hoàn thành" (Definition of Done) của hạ tầng.

---

## 2. Kịch bản

**Tình huống:**
Sinh viên đóng vai một **DevOps engineer** vừa được giao review một bộ mã Terraform (do một đội phát triển gửi sang) mô tả hạ tầng của một ứng dụng web sắp lên cloud: một VPC, các Security Group, một S3 bucket lưu dữ liệu, một EC2 instance chạy ứng dụng và một IAM role/policy cấp quyền cho nó. Do đội dev viết vội và ưu tiên "chạy được là xong", bộ mã chứa hàng loạt lỗi cấu hình bảo mật kinh điển. Chính sách của công ty áp dụng cổng chặn (**quality gate**) trong CI/CD: **không được `terraform apply` nếu công cụ quét IaC còn báo bất kỳ lỗi mức HIGH hoặc CRITICAL nào.**

Nhiệm vụ của sinh viên là chạy các công cụ quét tĩnh để phát hiện toàn bộ misconfig, phân tích nguy cơ thực tế của từng lỗi, **sửa mã Terraform** cho đúng chuẩn an toàn, và chứng minh kết quả bằng lần quét lại đạt (0 HIGH/CRITICAL). Khi cổng chặn được vượt qua, hệ thống CI mô phỏng sẽ tiết lộ một **flag** xác nhận hạ tầng đã đủ điều kiện triển khai.

> **Lưu ý quan trọng (offline):** Đây là bài **phân tích tĩnh** — Terraform chỉ dùng để `validate`/`plan` cục bộ và để công cụ quét đọc mã. **KHÔNG** có kết nối cloud thật, **KHÔNG** chạy `terraform apply` lên AWS. Toàn bộ diễn ra offline trong các container Labtainer cô lập.

**Vai trò của sinh viên:**
- Trên container `devops` (bàn làm việc của kỹ sư), chạy tfsec/trivy để tạo báo cáo lỗi ban đầu (baseline) và phân loại theo mức độ.
- Phân tích từng nhóm lỗi (network, storage, secret, IAM, logging), ánh xạ tới nguy cơ và khung tham chiếu.
- Sửa mã Terraform trong thư mục dự án để loại bỏ toàn bộ lỗi HIGH/CRITICAL.
- Quét lại, gửi kết quả tới cổng chặn CI mô phỏng để xác nhận và thu thập flag.

**Sơ đồ mạng / kiến trúc (mô tả text):**

Bài lab mô phỏng một pipeline CI/CD tối giản, gồm 2 container trên cùng một mạng cô lập `172.31.0.0/24` (không ra Internet khi chạy):

```
┌─────────────────────────────────┐        ┌───────────────────────────────┐
│ Container: devops                │        │ Container: ci                  │
│ 172.31.0.10 - CO terminal        │  HTTP  │ 172.31.0.20 - KHONG co terminal│
│ (ban lam viec cua ky su)         │ ─────► │ (dich vu quality gate CI)      │
│                                   │ :8000  │                                 │
│  ~/iac-project/  (ma Terraform   │  /gate │  Tu quet lai ma Terraform nhan  │
│    can review, chua misconfig)   │        │  duoc bang tfsec, dem so loi    │
│  ~/gate.sh  (goi cong chan CI)   │        │  HIGH/CRITICAL. Chi tiet lo     │
│                                   │        │  flag khi tong = 0.             │
│  Cong cu (offline): tfsec,       │        │                                 │
│  trivy, terraform,               │        │                                 │
│  grep, git, jq                   │        │                                 │
└─────────────────────────────────┘        └───────────────────────────────┘

Kien truc ma ma Terraform DINH mo ta (muc tieu trien khai, KHONG thuc su
duoc tao ra vi bai chi phan tich tinh offline):

   Internet ──► [Security Group] ──► EC2 (web app) ──► S3 bucket (du lieu)
                                        │
                                        └── IAM role/policy (quyen truy cap S3)
```

Sinh viên chỉ thao tác trên container `devops`. Container `ci` đóng vai trò hệ thống CI/CD nội bộ của công ty: sinh viên **không có quyền truy cập trực tiếp** vào đó — mọi tương tác đi qua script `~/gate.sh`, đúng như một kỹ sư thật chỉ tương tác với pipeline CI qua giao diện quy định, không được "vào thẳng" server CI để sửa kết quả.

---

## 3. Kiến thức bổ trợ

**Kiến thức nền tảng**

- **Infrastructure as Code (IaC):** phương pháp khai báo hạ tầng (máy chủ, mạng, quyền...) dưới dạng mã nguồn (ở đây là Terraform/HCL) thay vì bấm tay trên giao diện cloud. Ưu điểm: tái lập được, review được, versioning được — và cũng có nghĩa là **lỗi cấu hình cũng được nhân bản** ở mọi lần triển khai nếu không phát hiện sớm.
- **Shift-left security:** dịch chuyển hoạt động kiểm tra bảo mật về "phía trái" của vòng đời phát triển (lúc viết mã, lúc commit, lúc CI) thay vì để đến khi vận hành. Quét IaC tĩnh là ví dụ điển hình: lỗi được bắt trước khi hạ tầng tồn tại, chi phí sửa gần như bằng 0.
- **Static analysis (SAST cho hạ tầng):** công cụ đọc mã Terraform, đối chiếu với một tập **rule** (mỗi rule ứng với một best practice) và báo cáo vi phạm kèm mức độ nghiêm trọng và vị trí dòng. Không cần triển khai thật nên chạy được hoàn toàn offline.
- **Các dạng misconfig kinh điển gặp trong bài:**
  - *Security Group mở 0.0.0.0/0:* mở cổng nhạy cảm (22-SSH, 3389-RDP, 3306-DB...) cho toàn bộ Internet → bề mặt tấn công khổng lồ, dễ bị brute-force/khai thác.
  - *S3 public + không mã hóa:* bucket cho phép truy cập công khai và/hoặc không bật mã hóa at-rest → lộ lọt dữ liệu (một trong những nguyên nhân rò rỉ dữ liệu cloud phổ biến nhất).
  - *Secret hardcode:* mật khẩu/access key ghi thẳng trong `variables.tf` hoặc default value → lộ secret ngay trong Git history.
  - *IAM policy quá rộng:* `Action:"*"` trên `Resource:"*"` → vi phạm nguyên tắc **least privilege**, một credential bị lộ có thể chiếm toàn bộ tài khoản cloud.
  - *Logging tắt:* không bật access log/flow log → mất khả năng điều tra khi có sự cố.

**Thành phần cần quan sát trong bài lab**

| Thành phần | Vai trò |
|---|---|
| Thư mục `~/iac-project/` | Bộ mã Terraform chứa lỗi cần review và sửa. |
| Security Group (`network.tf`) | Nơi khai báo luật vào/ra; chứa lỗi mở 0.0.0.0/0 tới cổng nhạy cảm. |
| S3 bucket (`storage.tf`) | Nơi lưu dữ liệu; chứa lỗi public access + thiếu mã hóa + versioning. |
| Biến/`variables.tf` | Chứa secret hardcode (mật khẩu/khóa) cần loại bỏ. |
| IAM policy (`iam.tf`) | Chứa quyền `Action:*`/`Resource:*` cần siết về least-privilege. |
| Cấu hình logging (`logging.tf`) | Đang tắt/thiếu; cần bật để phục vụ giám sát. |
| Báo cáo quét (`baseline.json`, `after.json`) | Bằng chứng đo lường số lỗi trước/sau khi sửa. |
| `~/gate.sh` | Script gọi cổng chặn CI mô phỏng; nhận flag khi đạt 0 HIGH/CRITICAL. |

**Bảng tùy chọn và cú pháp công cụ sử dụng trong bài**

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `tfsec` | `tfsec <dir>` | Quét nhanh thư mục Terraform, hiển thị lỗi kèm rule ID (ví dụ `aws-ec2-no-public-ingress-sgr`) và mức độ. |
| `tfsec` | `tfsec <dir> --format json --out <file>` | Xuất báo cáo dạng JSON để đếm/lọc lỗi tự động. |
| `tfsec` | `tfsec <dir> --minimum-severity HIGH` | Chỉ hiển thị lỗi từ mức HIGH trở lên (phục vụ quality gate). |
| `trivy` | `trivy config <dir>` | Quét cấu hình sai IaC (Terraform/Dockerfile/K8s) bằng engine của Trivy (bộ rule khác tfsec, bổ sung góc nhìn), gom theo mức độ. |
| `trivy` | `trivy config -f json -o <file> <dir>` | Xuất kết quả JSON để đối chiếu/đếm. |
| `trivy` | `trivy config --severity HIGH,CRITICAL <dir>` | Chỉ báo lỗi HIGH/CRITICAL. |
| `terraform` | `terraform init -backend=false` | Khởi tạo cục bộ không cần backend từ xa (offline). |
| `terraform` | `terraform validate` | Kiểm tra cú pháp/hợp lệ của mã sau khi sửa (không kết nối cloud). |
| `terraform` | `terraform fmt -check` | Kiểm tra định dạng chuẩn của mã. |
| `grep` | `grep -rniE "password\|secret\|access_key\|0.0.0.0/0" <dir>` | Tìm nhanh secret hardcode và CIDR mở toàn Internet. |
| `git` | `git diff` / `git diff --stat` | Xem chính xác các thay đổi đã thực hiện khi remediation. |

> **Ghi chú về rule:** Mỗi công cụ có bộ rule riêng và cách phân loại mức độ hơi khác nhau. Trong bài, sinh viên nên chạy ít nhất 2 công cụ để hiểu vì sao "phòng thủ theo nhiều lớp" (defense in depth) áp dụng cả cho khâu quét.

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/devops-iac-scan.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer devops-iac-scan
```

(chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm)

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho bàn làm việc của kỹ sư: container `devops`. Bộ mã Terraform cần review nằm ở `~/iac-project/`.

---

### Nhiệm vụ 1 — `baseline_scan`: Quét baseline và phân loại rủi ro

**Mục tiêu:** Chạy công cụ quét IaC để lập danh sách toàn bộ lỗi cấu hình hiện có và phân loại theo mức độ nghiêm trọng, tạo mốc so sánh (baseline) trước khi sửa.

**Bước 1:** Vào thư mục dự án và xem cấu trúc:
```bash
cd ~/iac-project
ls -la
terraform init -backend=false
terraform validate
```

**Bước 2:** Quét nhanh bằng `tfsec` để có cái nhìn tổng thể:
```bash
tfsec .
```

**Bước 3:** Xuất báo cáo baseline dạng JSON để đếm lỗi:
```bash
tfsec . --format json --out ~/baseline.json
```

**Bước 4:** Đếm số lỗi theo mức độ (dùng để so sánh về sau):
```bash
grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/baseline.json | sort | uniq -c
```

**Bước 5:** Chạy chéo bằng `trivy` (bộ rule khác tfsec) để bổ sung góc nhìn:
```bash
trivy config .
trivy config --severity HIGH,CRITICAL .
```

**Bước 6:** Lập bảng phân loại (ghi ra file `~/trieu-chung.txt`) theo mẫu: mỗi dòng gồm *file — rule ID — mức độ — mô tả ngắn nguy cơ*.

**Điều kiện hoàn thành nhiệm vụ:** Đã tạo được file `~/baseline.json` chứa kết quả quét, và trong lịch sử lệnh có bản đếm số lỗi HIGH/CRITICAL của baseline (baseline phải có ít nhất một số lỗi HIGH/CRITICAL > 0). `terraform validate` trả về hợp lệ.

**Câu hỏi 1:** Cùng một bộ mã, tfsec và trivy có thể báo số lượng và loại lỗi khác nhau (mỗi công cụ có bộ rule riêng). Theo em, vì sao trong một pipeline DevSecOps người ta thường chạy nhiều hơn một công cụ quét thay vì tin tưởng tuyệt đối vào một công cụ duy nhất?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `fix_network_storage`: Khắc phục lỗi mạng và lưu trữ

**Mục tiêu:** Sửa hai nhóm lỗi bề mặt tấn công lớn nhất: Security Group mở toàn Internet và S3 bucket public/không mã hóa.

**Bước 1:** Định vị các lỗi liên quan:
```bash
grep -rniE "0.0.0.0/0" ~/iac-project
grep -rniE "acl|public|encryption|versioning" ~/iac-project/storage.tf
```

**Bước 2:** Trong `network.tf`, siết Security Group. Thay `cidr_blocks = ["0.0.0.0/0"]` trên các cổng nhạy cảm (22/3389/3306...) bằng dải nội bộ tối thiểu cần thiết, ví dụ:
```hcl
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/16"]   # chỉ cho phép dải quản trị nội bộ
}
```
(Sinh viên tự xác định cổng nào đang mở sai và chọn dải hợp lý; nguyên tắc: KHÔNG để cổng quản trị/DB mở ra 0.0.0.0/0.)

**Bước 3:** Trong `storage.tf`, khắc phục S3 bucket:
- Chặn public access (thêm resource `aws_s3_bucket_public_access_block` với cả 4 cờ `= true`).
- Bật mã hóa at-rest (`aws_s3_bucket_server_side_encryption_configuration`).
- Bật versioning.
- Loại bỏ `acl = "public-read"` nếu có.

**Bước 4:** Kiểm tra cú pháp và quét lại riêng hai file vừa sửa:
```bash
terraform validate
tfsec . --minimum-severity HIGH
```

**Bước 5:** Xem lại chính xác thay đổi đã làm:
```bash
git diff network.tf storage.tf
```

**Điều kiện hoàn thành nhiệm vụ:** Không còn lỗi HIGH/CRITICAL thuộc nhóm network (ingress 0.0.0.0/0 tới cổng nhạy cảm) và nhóm storage (S3 public / thiếu mã hóa) khi quét lại; `terraform validate` vẫn hợp lệ; `git diff` cho thấy các thay đổi tương ứng đã được áp dụng.

**Câu hỏi 2:** Một đồng nghiệp nói "cứ để Security Group mở 0.0.0.0/0 cho tiện, đằng nào ứng dụng cũng có mật khẩu rồi". Hãy phản biện quan điểm này bằng ít nhất hai lý do bảo mật cụ thể (gợi ý: bề mặt tấn công, defense in depth, brute-force, 0-day).
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `fix_secret_iam`: Loại bỏ secret hardcode và siết quyền IAM

**Mục tiêu:** Xử lý hai lỗi nghiêm trọng về quản lý bí mật và phân quyền: secret hardcode trong biến và IAM policy quá rộng.

**Bước 1:** Truy tìm secret hardcode:
```bash
grep -rniE "password|secret|access_key|private_key|token" ~/iac-project
```

**Bước 2:** Trong `variables.tf` (và nơi liên quan), loại bỏ giá trị bí mật ghi cứng:
- Xóa `default` chứa mật khẩu/khóa thật.
- Đánh dấu biến nhạy cảm bằng `sensitive = true` và để giá trị được truyền lúc chạy (biến môi trường `TF_VAR_...` hoặc file `*.tfvars` không commit), thay vì nhúng trong mã:
```hcl
variable "db_password" {
  type      = string
  sensitive = true
  # KHÔNG đặt default là mật khẩu thật
}
```

**Bước 3:** Trong `iam.tf`, siết policy về least-privilege. Thay:
```hcl
# TRƯỚC (sai)
Action   = "*"
Resource = "*"
```
bằng danh sách hành động và tài nguyên tối thiểu cần thiết, ví dụ chỉ cho phép đọc/ghi đúng bucket của ứng dụng:
```hcl
Action   = ["s3:GetObject", "s3:PutObject"]
Resource = ["arn:aws:s3:::${var.app_bucket_name}/*"]
```

**Bước 4:** Quét lại và xác nhận nhóm secret/IAM đã sạch:
```bash
tfsec . --minimum-severity HIGH
trivy config --severity HIGH,CRITICAL . | grep -iE "secret|iam|policy|key"
git diff variables.tf iam.tf
```

**Điều kiện hoàn thành nhiệm vụ:** Lệnh `grep` không còn tìm thấy secret/khóa ghi cứng dạng giá trị thật trong mã; không còn lỗi HIGH/CRITICAL thuộc nhóm secret và IAM (không còn `Action:*`/`Resource:*`); biến nhạy cảm được đánh dấu `sensitive = true`.

**Câu hỏi 3:** Giả sử access key bị hardcode đã từng được commit rồi mới bị xóa ở commit sau. Vì sao chỉ xóa dòng đó khỏi file hiện tại là CHƯA đủ để coi là an toàn, và cần làm thêm gì? Ánh xạ nguy cơ IAM policy `Action:*/Resource:*` tới một kỹ thuật trong MITRE ATT&CK for Cloud.
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `pass_gate`: Bật logging, quét lại toàn diện và vượt cổng chặn

**Mục tiêu:** Hoàn tất khắc phục (bật logging còn thiếu), chạy lại toàn bộ pipeline quét đạt 0 HIGH/CRITICAL, vượt quality gate và lấy flag.

**Bước 1:** Xử lý nhóm logging trong `logging.tf` (và các resource liên quan): bật access logging cho S3, bật VPC flow log / hoặc bật các cờ logging mà công cụ báo thiếu (theo rule ID trong báo cáo).

**Bước 2:** Chạy lại toàn bộ và xuất báo cáo "after":
```bash
cd ~/iac-project
terraform validate
tfsec . --format json --out ~/after.json
grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/after.json | sort | uniq -c
trivy config --severity HIGH,CRITICAL .
```

**Bước 3:** So sánh baseline và after để định lượng cải thiện:
```bash
echo "== BASELINE =="; grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/baseline.json | sort | uniq -c
echo "== AFTER    =="; grep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/after.json | sort | uniq -c
```

**Bước 4:** Gửi kết quả tới cổng chặn CI mô phỏng. Script này đóng gói mã Terraform hiện tại và gửi tới dịch vụ CI; dịch vụ đó **tự quét lại độc lập** và chỉ trả về flag khi số lỗi HIGH/CRITICAL = 0:
```bash
~/gate.sh
```

**Bước 5:** Ghi lại flag lấy được (được `~/gate.sh` tự động lưu) vào file kết quả:
```bash
cat ~/flag.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Báo cáo `~/after.json` cho thấy **0 lỗi HIGH và 0 lỗi CRITICAL**; `terraform validate` hợp lệ; `~/gate.sh` báo GATE PASSED và flag được lưu vào `~/flag.txt`.

**Câu hỏi 4:** Bài lab đặt cổng chặn ở ngưỡng "0 HIGH/CRITICAL" chứ không phải "0 lỗi ở mọi mức". Theo em, đánh đổi giữa mức độ nghiêm ngặt của quality gate và tốc độ giao hàng (velocity) của đội phát triển nên được cân nhắc thế nào? Nêu một rủi ro nếu đặt gate quá lỏng và một rủi ro nếu đặt quá chặt.
Trả lời: _______________________________________

---

## 5. Ánh xạ khung tham chiếu

| Nhóm lỗi trong bài | OWASP IaC / DevSecOps | CIS Benchmark (AWS) | MITRE ATT&CK for Cloud |
|---|---|---|---|
| SG mở 0.0.0.0/0 cổng nhạy cảm | Insecure network config | CIS AWS 5.x (SG/NACL) | T1190 Exploit Public-Facing App; T1110 Brute Force |
| S3 public / không mã hóa | Sensitive data exposure | CIS AWS 2.1.x (S3) | T1530 Data from Cloud Storage Object |
| Secret hardcode | Hardcoded secrets | — | T1552 Unsecured Credentials |
| IAM policy `Action:*/Resource:*` | Excessive privileges | CIS AWS 1.x (IAM) | T1078 Valid Accounts; T1098 Account Manipulation |
| Logging tắt | Insufficient logging/monitoring | CIS AWS 3.x (Logging) | T1562.008 Impair Defenses: Disable Cloud Logs |
