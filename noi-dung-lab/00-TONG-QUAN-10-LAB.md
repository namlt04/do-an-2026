
> **Định hướng:** Cloud – DevOps – DevSecOps, trọng tâm **bảo mật ~60% / thiết lập môi trường ~40%**.
---

## Bảng so sánh nhanh

| # | Mã lab | Chủ đề | Mức độ | Vai trò SV | Kết quả (flag/goal) |
|---|--------|--------|--------|-----------|---------------------|
| 1 | `dso-docker-escape` | Thoát container chiếm host | Nâng cao | Attacker → DevSecOps | Đọc flag trên host sau escape + hardening |
| 2 | `dso-image-scan` | Bảo mật image container | Trung bình | DevSecOps/Attacker | Moi secret trong layer + quét CVE, lấy flag |
| 3 | `dso-cicd-jenkins` | Bảo mật CI/CD (Jenkins) | Nâng cao | Attacker → DevSecOps | RCE + pivot registry (flag_ci, flag_pivot) |
| 4 | `dso-supplychain-sca` | SCA & SBOM (chuỗi cung ứng) | Trung bình | DevSecOps | Khai thác CVE phụ thuộc + dựng security gate |
| 5 | `dso-secrets-git` | Quản lý bí mật (Git history) | Trung bình | Attacker → DevSecOps | Dùng secret lộ lấy flag + rotate/khắc phục |
| 6 | `cloud-s3-misconfig` | Object storage cấu hình sai | Trung bình | Attacker → DevSecOps | Exfiltrate + lấy flag bucket private + hardening |
| 7 | `cloud-ssrf-imds` | SSRF → cloud metadata | Nâng cao | Attacker → DevSecOps | Đánh cắp credential cloud (kiểu Capital One) |
| 8 | `cloud-k8s-rbac` | Bảo mật Kubernetes (RBAC) | Nâng cao | Attacker → DevSecOps | RBAC abuse + pod escape ra node |
| 9 | `dso-iac-scan` | Bảo mật IaC (shift-left) | Trung bình | DevSecOps | Quét & sửa Terraform, vượt quality gate |
| 10 | `dso-waf-crs` | WAF runtime (ModSecurity+CRS) | Nâng cao | DevSecOps | Chặn tấn công + DAST + khử false positive |

**Phân bố chủ đề:** Container/Docker (1,2) · CI/CD & chuỗi cung ứng (3,4,5) · Cloud (6,7,8) · Shift-left & Runtime protection (9,10).
**Phân bố mức độ:** Trung bình ×5 (2,4,5,6,9) · Nâng cao ×5 (1,3,7,8,10).

---

## 1. `dso-docker-escape` — Thoát container chiếm quyền host

- **Mục đích:** Cho sinh viên trực tiếp thực hiện kỹ thuật *container escape* từ một container bị cấu hình sai, rồi tự tay vá lại cấu hình đó.
- **Ý nghĩa:** Container KHÔNG phải ranh giới bảo mật tuyệt đối. Các cấu hình tiện lợi nhưng nguy hiểm (`--privileged`, mount Docker socket, thừa capability) có thể biến một container bị chiếm thành bàn đạp chiếm toàn bộ host — bài học cốt lõi khi vận hành Docker trong DevOps.
- **Công cụ:** `docker` CLI, `mount`, `nsenter`, `capsh`/`getcap`, `cat`/`ls`/`grep`, (tùy chọn) `deepce`.
- **Quy trình:** (1) Trinh sát trong container (`/proc/1/cgroup`, `CapEff`, `docker.sock`, block device) để nhận diện cấu hình yếu → (2) Escape qua Docker socket bị lộ, HOẶC (3) Escape qua `--privileged`/`CAP_SYS_ADMIN` bằng `mount`/`nsenter` → (4) Đọc flag trên host → (5) **Hardening:** viết lại lệnh `docker run` an toàn (`--cap-drop=ALL`, bỏ socket/privileged, userns, seccomp) và giải thích vì sao từng đường escape thất bại.
- **Ánh xạ:** MITRE ATT&CK T1611 (Escape to Host), CIS Docker Benchmark.

## 2. `dso-image-scan` — Bảo mật image & quét lỗ hổng

- **Mục đích:** Phân tích một Docker image nội bộ để phát hiện secret bị nhúng trong layer và lỗ hổng CVE của base image; sau đó dựng lại image an toàn.
- **Ý nghĩa:** Secret "đã xóa" ở layer sau vẫn còn nguyên trong lịch sử layer; base image cũ mang theo CVE nghiêm trọng. Đây là rủi ro *supply-chain* điển hình — image là sản phẩm phân phối, mọi thứ trong nó đều có thể bị moi ra.
- **Công cụ:** `docker` (history/save/inspect), `tar`, `grep`, **Trivy** (quét offline), `dive` (tùy chọn), `jq`, `curl`.
- **Quy trình:** (1) Soi lịch sử layer (`docker history`) → (2) Giải nén layer (`docker save` + `tar`) trích xuất secret → (3) Quét CVE bằng Trivy + dùng secret gọi dịch vụ `vault-svc` lấy flag → (4) **Hardening:** multi-stage build, `.dockerignore`, base image pin version/tối giản, chạy non-root, quét đối chiếu để chứng minh đã sạch.
- **Ánh xạ:** MITRE T1552 (Unsecured Credentials), OWASP DevSecOps, CIS Docker Benchmark.

## 3. `dso-cicd-jenkins` — Bảo mật CI/CD pipeline

- **Mục đích:** Khai thác một máy chủ Jenkins cấu hình sai theo chuỗi đầy đủ, rồi hardening để triệt tiêu chuỗi tấn công.
- **Ý nghĩa:** Hệ thống CI/CD nắm giữ credential và quyền deploy — chiếm được CI thường đồng nghĩa chiếm được cả pipeline và các hệ thống hạ nguồn. Đây là mục tiêu giá trị cao và thường bị cấu hình lỏng lẻo.
- **Công cụ:** `curl`, `jq`, `grep`, Jenkins REST API & Script Console (Groovy), `jenkins-cli.jar` (tùy chọn), `git`/`docker` client để pivot.
- **Quy trình:** (1) Trinh sát Jenkins & phát hiện authorization sai (truy cập ẩn danh) → (2) RCE qua Script Console lấy flag trên máy CI → (3) Trích xuất credential từ log/biến môi trường/credential store → (4) Pivot bằng credential đánh cắp sang Docker Registry lấy flag mục tiêu → (5) **Hardening:** bật auth + Matrix Authorization, tắt/giới hạn Script Console, dùng Credentials Plugin, mask log.
- **Ánh xạ:** OWASP CI/CD Top 10, MITRE T1078 (Valid Accounts), T1059 (Command & Scripting Interpreter).

## 4. `dso-supplychain-sca` — SCA & SBOM (chuỗi cung ứng phần mềm)

- **Mục đích:** Lập danh mục thành phần (SBOM), quét phát hiện phụ thuộc có lỗ hổng, khai thác thực tế để chứng minh hậu quả, rồi vá và dựng cổng chặn trong pipeline.
- **Ý nghĩa:** Phần lớn mã trong một ứng dụng hiện đại là thư viện bên thứ ba (OWASP A06 - Vulnerable & Outdated Components). Cảnh báo "trên giấy" chỉ có sức nặng khi thấy nó dẫn tới hậu quả thực; và phòng ngừa bền vững là *security gate* tự động trong CI/CD.
- **Công cụ:** **Syft** (sinh SBOM CycloneDX), **Trivy** (SCA offline), `grype` (tùy chọn), `npm audit`/`pip-audit`, `curl`, `jq`, `git`.
- **Quy trình:** (1) Sinh SBOM & lập danh mục thành phần → (2) Quét SCA, xếp hạng theo severity, chỉ đích danh package+phiên bản+CVE (ưu tiên CVE cho RCE/injection/deserialization) → (3) Khai thác CVE đó trên `appserver` đang chạy để lấy flag → (4) **Remediation:** nâng cấp/pin phiên bản đã vá trong lockfile + dựng cổng quét `--exit-code 1` cho pipeline.
- **Ánh xạ:** OWASP Top 10 A06, OWASP DevSecOps, MITRE T1195 (Supply Chain Compromise).

## 5. `dso-secrets-git` — Quản lý bí mật (secret trong Git history)

- **Mục đích:** Đào secret bị lộ trong lịch sử commit của một Git repository, dùng nó truy cập dịch vụ, rồi thực hiện quy trình khắc phục đúng chuẩn.
- **Ý nghĩa:** `git commit` là *bất biến* — xóa secret ở commit sau KHÔNG loại nó khỏi lịch sử. Đây là một trong những nguồn rò rỉ credential phổ biến nhất; khắc phục đúng đòi hỏi **rotate** secret chứ không chỉ xóa file.
- **Công cụ:** `git` (log/rev-list/`log -p`), **gitleaks**, **trufflehog**, `grep`, `curl`, `jq`, `mc` (MinIO Client).
- **Quy trình:** (1) Trinh sát history, xác định commit nghi vấn → (2) Quét toàn bộ history bằng gitleaks/trufflehog, trích xuất AWS key + API token + DB password → (3) Dùng credential lộ truy cập dịch vụ mục tiêu (MinIO/API) lấy flag → (4) **Remediation:** rotate secret, chuyển sang `.env`/secret manager, thêm `.gitignore` + pre-commit hook quét secret, khái niệm dọn history (git filter-repo/BFG).
- **Ánh xạ:** OWASP DevSecOps (Secrets Management), MITRE T1552, CWE-798 (Hard-coded Credentials).

## 6. `cloud-s3-misconfig` — Object storage cấu hình sai

- **Mục đích:** Khai thác object storage (mô phỏng bằng MinIO tương thích S3) cho phép truy cập ẩn danh để liệt kê và trích xuất dữ liệu, rồi siết lại cấu hình.
- **Ý nghĩa:** Rò rỉ dữ liệu qua bucket cấu hình sai là một trong những sự cố cloud phổ biến nhất. Bài thể hiện chuỗi *misconfig → lộ dữ liệu → lộ credential → truy cập sâu hơn*, và nguyên tắc *least privilege*.
- **Công cụ:** `aws-cli` (`s3`/`s3api` với `--endpoint-url`), `mc` (MinIO Client), `curl`, `jq`.
- **Quy trình:** (1) Phát hiện & liệt kê bucket cho phép truy cập ẩn danh → (2) Trích xuất file backup, tìm credential lộ trong đó → (3) Dùng credential lộ truy cập bucket private lấy flag → (4) **Hardening:** gỡ policy public, áp least privilege, bật versioning/logging, rotate credential.
- **Ánh xạ:** MITRE T1530 (Data from Cloud Storage), T1552, T1580; OWASP Cloud; CIS.

## 7. `cloud-ssrf-imds` — SSRF tới dịch vụ metadata cloud

- **Mục đích:** Khai thác lỗ hổng SSRF trong ứng dụng web để tiếp cận dịch vụ metadata (IMDS giả tại `169.254.169.254`), đánh cắp credential tạm thời và truy cập tài nguyên cloud.
- **Ý nghĩa:** Tái hiện chính xác cơ chế của sự cố **Capital One 2019**. Cho thấy một lỗ hổng ứng dụng (SSRF) có thể xuyên thủng ranh giới hạ tầng cloud, và vì sao **IMDSv2** cùng chống SSRF là bắt buộc.
- **Công cụ:** `curl`, ứng dụng web mục tiêu (chức năng "fetch URL"/preview), `aws-cli` v2, `jq`.
- **Quy trình:** (1) Phát hiện & xác nhận SSRF → (2) Khai thác SSRF đọc IMDS, đánh cắp credential tạm thời (AccessKey/SecretKey/Token) → (3) Dùng credential truy cập object storage lấy flag → (4) **Hardening đa lớp:** allowlist/chặn CIDR link-local, bật IMDSv2 (PUT lấy token + hop limit), least privilege cho role.
- **Ánh xạ:** OWASP Top 10 A10:2021 (SSRF), MITRE T1552.005 (Cloud Instance Metadata API).

## 8. `cloud-k8s-rbac` — Bảo mật Kubernetes (RBAC & pod escape)

- **Mục đích:** Từ một pod bị chiếm, lạm dụng RBAC quá rộng để đọc secret và tạo pod nguy hiểm nhằm thoát ra node; sau đó vá tận gốc cả cụm.
- **Ý nghĩa:** Trong K8s, quyền của ServiceAccount và cấu hình pod quyết định mức thiệt hại khi một pod bị chiếm. Bài minh họa chuỗi *RBAC thừa quyền → lộ secret → pod hostPath/privileged → chiếm node*, và các lớp phòng thủ (least privilege, Pod Security, NetworkPolicy).
- **Công cụ:** `kubectl`, `base64`, `jq`, `curl`; (audit) `kube-bench`, `kubesec`, `kube-linter`.
- **Quy trình:** (1) Đọc ServiceAccount token, liệt kê quyền RBAC quá rộng → (2) Đọc secret qua API + phát hiện secret lộ trong ConfigMap → (3) Tạo pod hostPath/privileged thoát ra node lấy flag → (4) **Hardening:** RBAC least privilege, tách secret khỏi ConfigMap (Secret + mã hóa at-rest), Pod Security "restricted", NetworkPolicy; chạy lại chuỗi tấn công để chứng minh đã chặn.
- **Ánh xạ:** MITRE ATT&CK for Containers, OWASP Kubernetes Top 10, CIS Kubernetes Benchmark.
- *Ghi chú triển khai:* 2 phương án — (A) k3s 1 node (khuyến nghị) hoặc (B) audit tĩnh manifest cho VM yếu.

## 9. `dso-iac-scan` — Bảo mật Infrastructure as Code (shift-left)

- **Mục đích:** Quét tĩnh mã Terraform để phát hiện, phân loại và **khắc phục** các cấu hình sai kinh điển trước khi triển khai — đúng tinh thần *shift-left*.
- **Ý nghĩa:** Sửa cấu hình sai ở giai đoạn code rẻ và an toàn hơn nhiều so với khi đã lên production. Bài rèn tư duy phòng ngừa và biến "an toàn" thành tiêu chí đo lường được (quality gate).
- **Công cụ:** **tfsec**, **checkov**, **trivy config**, `terraform` (validate/plan — không apply lên cloud thật), `grep`, `git diff`. (Chạy hoàn toàn offline.)
- **Quy trình:** (1) Quét baseline & phân loại rủi ro theo severity/rule ID → (2) Khắc phục lỗi mạng & lưu trữ (SG mở `0.0.0.0/0`, S3 public/không mã hóa) → (3) Loại secret hardcode + siết IAM (`Action:*`/`Resource:*`) → (4) Bật logging, quét lại toàn diện và **vượt quality gate** (0 HIGH/CRITICAL) để nhận flag.
- **Ánh xạ:** OWASP IaC Security, CIS Benchmarks, MITRE ATT&CK Cloud (misconfiguration).

## 10. `dso-waf-crs` — WAF runtime (ModSecurity + OWASP CRS)

- **Mục đích:** Bảo vệ một web app có lỗ hổng bằng WAF ở tầng runtime, kiểm chứng hiệu quả bằng DAST, và cân bằng an toàn với khả dụng khi xử lý false positive.
- **Ý nghĩa:** WAF là lớp phòng thủ bổ sung (defense-in-depth) — chặn được tấn công phổ biến nhưng KHÔNG thay việc vá code, và luôn đi kèm bài toán false positive. Bài dạy triển khai lẫn *vận hành* WAF thực tế.
- **Công cụ:** `curl`, `nginx` (reverse proxy) + **ModSecurity v3** + **OWASP CRS**, **nikto** và/hoặc **OWASP ZAP** (baseline DAST), `tail`/`grep` trên audit log ModSecurity.
- **Quy trình:** (1) Khai thác app trực tiếp khi CHƯA có WAF (SQLi/XSS/traversal) lấy Flag 1 → (2) Dựng nginx+ModSecurity+CRS, bật chế độ chặn, gửi lại payload cũ để xác nhận 403 → Flag 2 → (3) Chạy DAST so sánh trước/sau WAF → (4) **Hardening:** viết rule exclusion khoanh vùng để khử false positive cho chức năng hợp lệ mà vẫn chặn tấn công → Flag 3.
- **Ánh xạ:** OWASP CRS, OWASP Top 10, OWASP DevSecOps Guideline.



