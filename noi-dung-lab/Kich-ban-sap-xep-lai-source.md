**KỊCH BẢN 10 BÀI LAB --- CLOUD / DEVOPS / DEVSECOPS (SẮP XẾP THEO ĐỘ
KHÓ TĂNG DẦN)**

Định hướng: Cloud -- DevOps -- DevSecOps; trọng tâm an toàn thông tin,
có kèm thiết lập môi trường.

Bối cảnh chung: Sinh viên tham gia một chiến dịch đánh giá an ninh cho
hệ thống cloud-native của một công ty công nghệ (giả định). Mười bài đi
từ ngoài vào trong, độ khó tăng dần; mỗi bài sinh viên vừa khai thác lỗ
hổng (mũ đỏ) vừa vá lỗi (mũ xanh -- DevSecOps). Các bài độc lập, có thể
thực hiện theo thứ tự bất kỳ.

**1. dso-iac-scan --- Bảo mật hạ tầng dạng mã, IaC (Cơ bản)**

Bối cảnh: Một lập trình viên của công ty vô tình đẩy toàn bộ mã hạ tầng
Terraform lên kho công khai. Sinh viên đóng vai kỹ sư DevSecOps, rà soát
mã trước khi nó bị khai thác.

Mục tiêu: Phát hiện, phân loại và khắc phục các cấu hình sai kinh điển
trong mã Terraform; đưa mã vượt qua cổng chất lượng an ninh (không còn
lỗi mức cao/nghiêm trọng) để nhận flag.

Công cụ: tfsec, checkov, trivy config, terraform (validate/plan), grep,
git diff.

Quy trình: (1) Quét baseline và phân loại rủi ro theo mức độ nghiêm
trọng → (2) Khắc phục lỗi mạng và lưu trữ (security group mở 0.0.0.0/0,
bucket lưu trữ công khai hoặc không mã hóa) → (3) Loại bỏ secret
hardcode và siết quyền IAM (Action: / Resource:) → (4) Bật logging, quét
lại toàn diện và vượt cổng chất lượng để nhận flag.

**2. dso-image-scan --- Bảo mật image container (Cơ bản)**

Bối cảnh: Từ thông tin về kho image nội bộ của công ty, sinh viên lấy
được một image ứng dụng và tiến hành phân tích.

Mục tiêu: Phát hiện secret bị nhúng trong lịch sử layer và lỗ hổng CVE
của base image; dùng secret truy cập dịch vụ nội bộ để lấy flag; dựng
lại image an toàn.

Công cụ: docker (history/save/inspect), tar, grep, Trivy (quét offline),
jq, curl.

Quy trình: (1) Soi lịch sử layer bằng docker history → (2) Giải nén
layer và trích xuất secret bị bỏ sót → (3) Quét CVE bằng Trivy và dùng
secret gọi dịch vụ xác thực nội bộ để lấy flag → (4) Khắc phục:
multi-stage build, .dockerignore, base image tối giản và ghim phiên bản,
chạy bằng người dùng không phải root, quét đối chiếu để chứng minh đã
sạch.

**3. dso-secrets-git --- Quản lý bí mật trong Git (Trung bình)**

Bối cảnh: Sinh viên truy cập được kho mã nguồn nội bộ của công ty. Một
secret từng bị commit rồi xóa ở commit sau, nhưng vẫn còn nguyên trong
lịch sử Git.

Mục tiêu: Đào secret trong toàn bộ lịch sử commit, dùng nó truy cập dịch
vụ tương ứng để lấy flag, sau đó thực hiện quy trình khắc phục đúng
chuẩn.

Công cụ: git, gitleaks, trufflehog, grep, curl, jq, mc (MinIO Client).

Quy trình: (1) Trinh sát lịch sử commit, xác định commit nghi vấn → (2)
Quét toàn bộ lịch sử bằng gitleaks/trufflehog, trích xuất khóa truy cập,
token API, mật khẩu cơ sở dữ liệu → (3) Dùng credential lộ để truy cập
dịch vụ mục tiêu và lấy flag → (4) Khắc phục: xoay vòng (rotate) secret,
chuyển sang biến môi trường hoặc secret manager, thêm .gitignore và
pre-commit hook quét secret, dọn secret khỏi lịch sử.

**4. dso-supplychain-sca --- Bảo mật chuỗi cung ứng phần mềm, SCA và
SBOM (Trung bình)**

Bối cảnh: Có mã nguồn ứng dụng của công ty, sinh viên phân tích chuỗi
cung ứng và phát hiện ứng dụng dùng một thư viện phụ thuộc (Node.js/npm)
có lỗ hổng nghiêm trọng.

Mục tiêu: Lập SBOM, xác định chính xác gói và CVE nguy hiểm, khai thác
lỗ hổng trên ứng dụng đang chạy để lấy flag, sau đó vá và dựng cổng chặn
trong pipeline.

Công cụ: syft (sinh SBOM), trivy (quét SCA offline), grype (tùy chọn),
npm audit, curl, jq, git.

Quy trình: (1) Sinh SBOM và lập danh mục thành phần → (2) Quét SCA, xếp
hạng theo mức độ, chỉ đích danh gói kèm phiên bản và mã CVE → (3) Khai
thác CVE trên máy chủ ứng dụng để lấy flag → (4) Khắc phục: nâng cấp và
ghim phiên bản đã vá trong lockfile, dựng cổng quét tự động chặn khi còn
lỗ hổng nghiêm trọng.

**5. cloud-s3-misconfig --- Lưu trữ đối tượng cấu hình sai (Trung
bình)**

Bối cảnh: Sinh viên tiếp cận dịch vụ lưu trữ đối tượng tương thích S3
(mô phỏng bằng MinIO) của công ty. Một bucket bị đặt cho phép truy cập
ẩn danh.

Mục tiêu: Liệt kê và trích xuất dữ liệu từ bucket cấu hình sai, lần theo
credential lộ để truy cập bucket riêng tư và lấy flag, sau đó siết lại
cấu hình.

Công cụ: aws-cli (s3/s3api với \--endpoint-url), mc (MinIO Client),
curl, jq.

Quy trình: (1) Phát hiện và liệt kê bucket cho phép truy cập ẩn danh →
(2) Tải về file backup và tìm credential lộ bên trong → (3) Dùng
credential truy cập bucket riêng tư để lấy flag → (4) Khắc phục: gỡ
policy công khai, áp nguyên tắc tối thiểu quyền, bật versioning và
logging, xoay vòng credential.

**6. dso-waf-crs --- Bảo vệ ứng dụng runtime bằng WAF (Trung bình khá)**

Bối cảnh: Ứng dụng web bán hàng của công ty liên tục bị dò quét. Sinh
viên đóng vai kỹ sư DevSecOps được giao đưa ứng dụng ra sau một tường
lửa ứng dụng web (WAF).

Mục tiêu: Khai thác trực tiếp ứng dụng khi chưa có WAF để thấy lỗ hổng
thật, dựng ModSecurity kèm OWASP CRS để chặn tấn công, đánh giá hiệu quả
bằng DAST và cân bằng an toàn với khả dụng khi xử lý cảnh báo sai.

Công cụ: curl, nginx (reverse proxy) kèm ModSecurity v3 và OWASP CRS,
nikto hoặc OWASP ZAP (DAST), tail/grep trên audit log.

Quy trình: (1) Khai thác ứng dụng khi chưa có WAF (SQLi, XSS, path
traversal) để lấy Flag 1 → (2) Dựng nginx kèm ModSecurity và CRS, bật
chế độ chặn, gửi lại payload cũ để xác nhận bị chặn (mã 403) và lấy Flag
2 → (3) Chạy DAST so sánh trước và sau WAF → (4) Khắc phục: viết rule
ngoại lệ để khử cảnh báo sai cho chức năng hợp lệ mà vẫn chặn được tấn
công, lấy Flag 3.

**7. cloud-ssrf-imds --- SSRF tới dịch vụ metadata cloud (Nâng cao)**

Bối cảnh: Ứng dụng web của công ty có chức năng xem trước ảnh theo URL
và bị dính lỗ hổng SSRF.

Mục tiêu: Khai thác SSRF để tiếp cận dịch vụ metadata của máy chủ cloud
(IMDS), đánh cắp credential tạm thời, rồi dùng credential đó truy cập
tài nguyên cloud và lấy flag; sau đó đề xuất phòng thủ nhiều lớp.

Công cụ: curl, ứng dụng web mục tiêu, aws-cli, jq.

Quy trình: (1) Phát hiện và xác nhận lỗ hổng SSRF → (2) Khai thác SSRF
để đọc IMDS và đánh cắp credential tạm thời → (3) Dùng credential truy
cập dịch vụ lưu trữ đối tượng để lấy flag → (4) Khắc phục nhiều lớp: cho
phép danh sách trắng và chặn dải địa chỉ link-local, bật IMDSv2 (yêu cầu
token và giới hạn hop), áp quyền tối thiểu cho role.

**8. dso-cicd-jenkins --- Bảo mật dây chuyền CI/CD (Nâng cao)**

Bối cảnh: Sinh viên phát hiện máy chủ CI/CD (Jenkins) của công ty bị cấu
hình lỏng lẻo, cho phép truy cập ẩn danh.

Mục tiêu: Khai thác Jenkins theo chuỗi đầy đủ, từ thực thi mã từ xa đến
trộm credential và pivot sang kho Docker Registry để lấy flag, sau đó
hardening để triệt tiêu chuỗi tấn công.

Công cụ: curl, jq, grep, Jenkins REST API và Script Console (Groovy),
docker client để pivot.

Quy trình: (1) Trinh sát Jenkins và phát hiện phân quyền sai → (2) Thực
thi mã từ xa qua Script Console để lấy flag trên máy CI → (3) Trích xuất
credential từ log, biến môi trường và credential store → (4) Pivot bằng
credential đánh cắp sang Docker Registry để lấy flag mục tiêu → (5) Khắc
phục: bật xác thực và phân quyền theo ma trận, tắt hoặc giới hạn Script
Console, dùng Credentials Plugin, che credential trong log.

**9. dso-docker-escape --- Thoát container chiếm quyền host (Nâng cao)**

Bối cảnh: Trên một container ứng dụng của công ty đã bị chiếm, sinh viên
nhận ra container bị cấu hình sai: gắn Docker socket, hoặc chạy ở chế độ
privileged, hoặc thừa capability nguy hiểm.

Mục tiêu: Thoát khỏi container để chiếm quyền trên máy host và đọc flag,
sau đó cấu hình lại container theo hướng an toàn.

Công cụ: docker CLI, mount, nsenter, capsh/getcap, cat/ls/grep.

Quy trình: (1) Trinh sát trong container để nhận diện cấu hình yếu → (2)
Thoát ra host qua Docker socket bị lộ, hoặc qua privileged/CAP_SYS_ADMIN
bằng mount/nsenter → (3) Đọc flag trên host → (4) Khắc phục: viết lại
lệnh chạy container an toàn (loại bỏ toàn bộ capability không cần, bỏ
socket và privileged, bật user namespace, áp seccomp) và giải thích vì
sao mỗi đường thoát bị chặn.

**10. cloud-k8s-rbac --- Bảo mật Kubernetes, RBAC và pod escape (Chuyên
sâu)**

Bối cảnh: Máy host chiếm được là một node trong cụm Kubernetes
production của công ty; sinh viên đang có chỗ đứng trong một pod.

Mục tiêu: Lạm dụng quyền RBAC quá rộng để đọc secret và tạo pod nguy
hiểm nhằm thoát ra node, chiếm toàn bộ nền tảng và lấy flag; sau đó vá
tận gốc cả cụm.

Công cụ: kubectl, base64, jq, curl.

Quy trình: (1) Đọc ServiceAccount token và liệt kê quyền RBAC quá rộng →
(2) Đọc secret qua API và phát hiện secret bị để lẫn trong ConfigMap →
(3) Tạo pod dùng hostPath hoặc privileged để thoát ra node và lấy flag →
(4) Khắc phục: áp RBAC tối thiểu quyền, tách secret khỏi ConfigMap, áp
chuẩn Pod Security mức restricted, thêm NetworkPolicy; chạy lại chuỗi
tấn công để chứng minh đã bị chặn.


\newpage

# PHỤ LỤC A — KIẾN TRÚC HẠ TẦNG & SƠ ĐỒ MẠNG (Hệ thống CloudNova)

> Nguồn: `Kich-Ban-2.txt` (Kịch bản tổng quan chi tiết v2.0). Toàn bộ 10 bài lab
> chạy **độc lập** trên Labtainer (không chạy đồng thời); sơ đồ dưới đây **gộp**
> 22 container vào một bức tranh hệ thống CloudNova để thể hiện các vùng mạng,
> vai trò container và luồng kill-chain nối các bài.

**Tổng hợp:** 22 container · 6 vùng mạng/tầng · 10 bài lab · 12 flag · 40 nhiệm vụ · 40 câu hỏi.
Yêu cầu VM: Ubuntu 20.04 + Docker Engine, RAM ≥ 4 GB, CPU ≥ 2 vCPU, chạy OFFLINE.

## A.1 — Bảng tổng hợp máy/container (tất cả 10 bài)

| Bài | Container | IP | OS / Base image | Vai trò |
|----|-----------|-----|-----------------|---------|
| 1 | devsecops | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Bàn làm việc kỹ sư; quét IaC |
| 2 | devsecops | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Workstation phân tích image |
| 2 | registry | 172.25.0.20 | Alpine 3.18 (registry:2) | Docker Registry v2 nội bộ |
| 3 | attacker | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Máy tấn công: git, gitleaks, trufflehog |
| 3 | gitserver | 172.25.0.20 | Alpine/Debian (Gitea 1.21) | Git server nội bộ chứa repo lỗ hổng |
| 4 | devsecops | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Workstation: npm audit, retire.js, snyk |
| 4 | appserver | 172.25.0.20 | Debian 12 (Node.js 18 LTS) | Ứng dụng Node.js có CVE trong dependencies |
| 5 | attacker | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Máy tấn công: aws-cli, curl, jq, mc |
| 5 | storage | 172.25.0.20 | Debian 12 (MinIO) | Object storage S3-compatible (MinIO) |
| 6 | client | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Attacker/DAST: curl, nikto, (ZAP opt.) |
| 6 | waf | 172.25.0.20 | Debian 12 (nginx 1.24) | Reverse proxy + ModSecurity v3 + CRS 4.x |
| 6 | webapp | 172.25.0.30 | Debian 12 (Python 3.11) | Web app lỗ hổng (Flask): SQLi/XSS/traversal |
| 7 | client | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Attacker: curl, aws-cli, jq |
| 7 | webapp | 172.25.0.20 | Debian 12 (Python 3.11) | App "imgproxy-portal" dính SSRF |
| 7 | imds | 169.254.169.254 (alias) | Alpine 3.18 (Python httpd) | IMDS giả: metadata + credential tạm |
| 7 | storage | 172.25.0.30 | Debian 12 (MinIO) | Object storage S3-compatible (MinIO) |
| 8 | attacker | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Máy tấn công: curl, jq, git |
| 8 | jenkins | 172.25.0.20 | Debian 12 (Python 3.11) | Jenkins mock (Flask) — endpoint lỗ hổng |
| 8 | gitserver | 172.25.0.30 | Alpine/Debian (Gitea 1.21) | Git server + Docker registry phụ |
| 9 | app | 172.60.2.10 | Ubuntu 20.04 (labtainer) | Container mục tiêu — shell SV (docker.sock + privileged) |
| 9 | host-sim | 172.60.2.5 | Alpine (docker:24-dind) | Mô phỏng máy host (DinD); chứa /root/flag.txt |
| 10 | attacker | 172.25.0.10 | Ubuntu 20.04 (labtainer) | Shell "trong pod bị chiếm": kubectl |
| 10 | k8s-node | 172.25.0.20 | Ubuntu 22.04 (k3s v1.28) | K3s single-node; chứa /opt/host-secrets/flag.txt |

## A.2 — Bảng phần mềm & phiên bản

| Phần mềm / Hệ thống | Phiên bản | Dùng ở bài | Ghi chú |
|---------------------|-----------|-----------|---------|
| Ubuntu (base Labtainer) | 20.04 LTS | Tất cả | Base container sinh viên thao tác |
| Terraform CLI | ≥ 1.5.x | 1 | Binary tĩnh; chỉ validate/plan |
| tfsec | ≥ 1.28.x | 1 | Binary Go tĩnh, offline |
| checkov | ≥ 3.0.x | 1 | Python; cài via pip, đóng gói sẵn |
| Trivy | ≥ 0.50.x | 1, 2 | Binary; đóng gói sẵn DB rule |
| Docker Registry | v2 (registry:2) | 2 | Registry nội bộ chứa image CloudNova |
| Grype | ≥ 0.74.x | 2 | SCA cho image; binary tĩnh |
| Syft | ≥ 1.0.x | 2, 4 | Tạo SBOM; binary tĩnh |
| Git | ≥ 2.34 | 3, 8, 9 | Có sẵn trong Ubuntu base |
| Gitea | 1.21.x | 3, 8 | Git server tự host, nhẹ |
| Gitleaks | ≥ 8.18.x | 3 | Binary Go tĩnh, offline |
| TruffleHog | ≥ 3.70.x | 3 | Binary Go tĩnh |
| git-filter-repo | ≥ 2.38 | 3 | Python script, cài sẵn |
| Node.js / npm | 18 LTS / ≥ 9 | 4 | Runtime app có CVE; npm audit |
| retire.js | ≥ 4.x | 4 | SCA cho JS; cài via npm global |
| MinIO Server / mc | 2024+ | 5, 7 | Object storage S3-compatible + CLI |
| AWS CLI v2 | ≥ 2.15.x | 5, 7 | Tương tác S3-compatible; bundle offline |
| nginx | 1.24.x/1.26.x | 6 | Reverse proxy cho WAF |
| ModSecurity v3 (libmodsecurity) | ≥ 3.0.12 | 6 | WAF engine; biên dịch sẵn |
| ModSecurity-nginx connector | ≥ 1.0.3 | 6 | Module connector; build cùng nginx |
| OWASP Core Rule Set (CRS) | ≥ 4.0.x | 6 | Bộ luật WAF; giải nén sẵn |
| nikto | ≥ 2.5.0 | 6 | DAST scanner (Perl), nhẹ |
| OWASP ZAP (tùy chọn) | ≥ 2.14 | 6 | DAST nặng (JVM), nếu đủ RAM |
| Python 3 + Flask | 3.11 / Flask 3.x | 6, 7, 8 | Backend webapp lỗ hổng & Jenkins mock |
| IMDS mock (Python httpd) | custom | 7 | HTTP server giả /latest/meta-data/... |
| Docker CLI / Engine (DinD) | ≥ 24 / docker:24-dind | 9 | Client qua socket; DinD mô phỏng host |
| libcap2-bin (capsh/getcap) | ≥ 2.44 | 9 | Liệt kê/giải mã capabilities |
| util-linux (nsenter/mount/lsblk) | ≥ 2.37 | 9 | Công cụ escape |
| k3s / kubectl | v1.28.x / ≥ 1.28 | 10 | Lightweight K8s single-node + CLI |
| kube-linter / kubesec / kube-bench | ≥ 0.6 / ≥ 2.14 / ≥ 0.7 | 10 | Audit tĩnh + CIS K8s Benchmark |
| curl / jq / grep / base64 | coreutils | Tất cả | Công cụ chung |

## A.3 — Sơ đồ mạng chi tiết (ASCII)

> Giữ nguyên dạng ký tự (monospace) từ kịch bản tổng quan v2.0. Sơ đồ hợp nhất
> rất rộng — nếu khó đọc trong Word, xem bản gốc `Kich-Ban-2.txt`.


```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                              VM LABTAINER  (Ubuntu 20.04 + Docker Engine)                                     ║
║                              RAM >= 4 GB  |  CPU >= 2 vCPU  |  OFFLINE                                       ║
║                                                                                                               ║
║  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  ║
║  ┃  INTERNET GIẢ ĐỊNH / BỀ MẶT NGOÀI  (nơi attacker/DevSecOps tiếp cận ban đầu)                           ┃  ║
║  ┃                                                                                                          ┃  ║
║  ┃    [attacker / devsecops / client]                                                                       ┃  ║
║  ┃    172.25.0.10  (Bài 1–8, 10)  |  172.60.2.10  (Bài 9)                                                  ┃  ║
║  ┃    Ubuntu 20.04  —  Máy sinh viên thao tác (terminal chính)                                              ┃  ║
║  ┃    ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐     ┃  ║
║  ┃    │  Công cụ cài sẵn (tùy bài):                                                                   │     ┃  ║
║  ┃    │  curl, jq, grep, git, base64, vim                              (chung tất cả bài)              │     ┃  ║
║  ┃    │  tfsec, checkov, trivy, terraform                              (Bài 1)                         │     ┃  ║
║  ┃    │  trivy, grype, syft, docker CLI, tar                           (Bài 2)                         │     ┃  ║
║  ┃    │  gitleaks >= 8.18, trufflehog >= 3.70, git-filter-repo         (Bài 3)                         │     ┃  ║
║  ┃    │  npm >= 9, retire.js >= 4, snyk (opt.), syft, grype            (Bài 4)                         │     ┃  ║
║  ┃    │  aws-cli v2, mc (MinIO client)                                 (Bài 5, 7)                      │     ┃  ║
║  ┃    │  nikto >= 2.5, ZAP (opt.)                                      (Bài 6)                         │     ┃  ║
║  ┃    │  jenkins-cli.jar                                               (Bài 8)                         │     ┃  ║
║  ┃    │  docker CLI >= 24, capsh, getcap, nsenter, mount, fdisk, lsblk (Bài 9)                         │     ┃  ║
║  ┃    │  kubectl >= 1.28, kube-linter, kubesec (opt.)                  (Bài 10)                        │     ┃  ║
║  ┃    └─────────────────────────────────────────────────────────────────────────────────────────────────┘     ┃  ║
║  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  ║
║          │          │          │          │          │         │          │          │          │               ║
║          │ Bài 1    │ Bài 2    │ Bài 3    │ Bài 4    │ Bài 5   │ Bài 6    │ Bài 7    │ Bài 8    │ Bài 9,10     ║
║          │ tfsec    │ pull     │ git      │ HTTP     │ S3 API  │ HTTP     │ HTTP     │ HTTP     │ docker/      ║
║          │ scan     │ image    │ clone    │ exploit  │ :9000   │ :80/:8080│ :8080    │ :8080    │ kubectl      ║
║          ▼          ▼          ▼          ▼          ▼         ▼          ▼          ▼          ▼               ║
║  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  ║
║  ┃  VÙNG DỊCH VỤ NỘI BỘ CLOUDNOVA  —  Mạng 172.25.0.0/24  (Bài 1–8, 10)  |  172.60.2.0/24  (Bài 9)      ┃  ║
║  ┃                                                                                                          ┃  ║
║  ┃  ╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗ ┃  ║
║  ┃  ║  TẦNG SOURCE CODE & IaC                                                                            ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  [Bài 1 — ~/iac-project/]              [Bài 3 — gitserver]           [Bài 2 — registry]            ║ ┃  ║
║  ┃  ║  (local trên devsecops)                  172.25.0.20                  172.25.0.20                   ║ ┃  ║
║  ┃  ║  Terraform code lỗi                      Gitea 1.21 (Alpine)         Docker Registry v2 (Alpine)   ║ ┃  ║
║  ┃  ║  main.tf, network.tf,                    Repo CloudNova              Image CloudNova                ║ ┃  ║
║  ┃  ║  storage.tf, iam.tf,                     lịch sử commit              (chứa secret trong layer)     ║ ┃  ║
║  ┃  ║  variables.tf, logging.tf                chứa secret lộ              HTTP :3000 (Gitea UI)         ║ ┃  ║
║  ┃  ║  gate.sh (CI mô phỏng)                  HTTP :3000 (Gitea)           HTTP :5000 (Registry API)     ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  Luồng: [1]──lộ kiến trúc──►[2]──lộ API key──►[3]──lộ AWS key──►[5]                               ║ ┃  ║
║  ┃  ╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝ ┃  ║
║  ┃                                          │                                                               ┃  ║
║  ┃                                          ▼ (credential sprawl — cùng bộ khóa lộ ở nhiều tầng)            ┃  ║
║  ┃  ╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗ ┃  ║
║  ┃  ║  TẦNG ỨNG DỤNG & BUILD                                                                             ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  [Bài 4 — appserver]               [Bài 8 — jenkins]              [Bài 8 — gitserver]              ║ ┃  ║
║  ┃  ║  172.25.0.20                        172.25.0.20                    172.25.0.30                      ║ ┃  ║
║  ┃  ║  Node.js 18 LTS (Debian 12)        Flask mock (Debian 12)         Gitea 1.21 + Registry            ║ ┃  ║
║  ┃  ║  App CloudNova có CVE              HOẶC Jenkins LTS (JVM)         Repo CI + deploy keys            ║ ┃  ║
║  ┃  ║  (prototype pollution /            Script Console (RCE)            HTTP :3000                       ║ ┃  ║
║  ┃  ║   deserialization)                 Credential Store                                                 ║ ┃  ║
║  ┃  ║  node_modules cài sẵn             HTTP :8080                                                       ║ ┃  ║
║  ┃  ║  HTTP :8080 (hoặc :3000)                                                                           ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  Luồng: [3]──mã nguồn──►[4]──shell trên app──►[8]──credential deploy──►[9]                        ║ ┃  ║
║  ┃  ╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝ ┃  ║
║  ┃                                          │                                                               ┃  ║
║  ┃                                          ▼                                                               ┃  ║
║  ┃  ╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗ ┃  ║
║  ┃  ║  TẦNG WEB PERIMETER (WAF + STOREFRONT)                                                             ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  [Bài 6 — waf]                   [Bài 6,7 — webapp]                                                ║ ┃  ║
║  ┃  ║  172.25.0.20                      172.25.0.30 (Bài 6) / 172.25.0.20 (Bài 7)                        ║ ┃  ║
║  ┃  ║  nginx 1.24 (Debian 12)           Python 3.11 + Flask (Debian 12)                                  ║ ┃  ║
║  ┃  ║  + ModSecurity v3 >= 3.0.12       Storefront CloudNova                                              ║ ┃  ║
║  ┃  ║  + OWASP CRS >= 4.0              SQLi, XSS, Path Traversal (Bài 6)                                 ║ ┃  ║
║  ┃  ║  + modsec-nginx connector         "imgproxy-portal" / SSRF (Bài 7)                                  ║ ┃  ║
║  ┃  ║  Audit log: /var/log/modsec_*     fetch?url= (điểm nhập SSRF)                                      ║ ┃  ║
║  ┃  ║  Cổng :80 (reverse proxy)         Cổng :8080 (backend)                                              ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  Luồng:  client──►[6] waf (bảo vệ)──►webapp ──►[7] webapp (SSRF)──►imds──►credential──►storage    ║ ┃  ║
║  ┃  ╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝ ┃  ║
║  ┃                                          │                                                               ┃  ║
║  ┃                                          ▼                                                               ┃  ║
║  ┃  ╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗ ┃  ║
║  ┃  ║  TẦNG CLOUD SERVICES (MÔ PHỎNG)                                                                    ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  [Bài 5,7 — storage]               [Bài 7 — imds]                                                  ║ ┃  ║
║  ┃  ║  172.25.0.20 (Bài 5)               169.254.169.254 (alias)                                          ║ ┃  ║
║  ┃  ║  172.25.0.30 (Bài 7)               Alpine 3.18                                                      ║ ┃  ║
║  ┃  ║  MinIO Server (Debian 12)           Python http.server custom                                        ║ ┃  ║
║  ┃  ║  S3-compatible                      /latest/meta-data/                                               ║ ┃  ║
║  ┃  ║  Cổng :9000 (S3 API)               /latest/meta-data/iam/                                           ║ ┃  ║
║  ┃  ║  Cổng :9001 (Console)                security-credentials/                                           ║ ┃  ║
║  ┃  ║  Buckets:                           AccessKeyId / SecretKey / Token                                  ║ ┃  ║
║  ┃  ║   • public-assets (ẩn danh)         IMDSv1 (mặc định) → IMDSv2                                      ║ ┃  ║
║  ┃  ║   • internal-backup (credential)    Cổng :80 (HTTP link-local)                                       ║ ┃  ║
║  ┃  ║   • finance-reports (private)                                                                       ║ ┃  ║
║  ┃  ║   • fin-reports (Bài 7, flag)                                                                       ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  Luồng: [5]──S3 misconfig──►exfil backup──►lộ thêm key──►bucket private                            ║ ┃  ║
║  ┃  ║          [7]──SSRF──►imds──►credential──►storage──►flag                                             ║ ┃  ║
║  ┃  ╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝ ┃  ║
║  ┃                                          │                                                               ┃  ║
║  ┃                                          ▼                                                               ┃  ║
║  ┃  ╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗ ┃  ║
║  ┃  ║  TẦNG CONTAINER & HOST  (Mạng 172.60.2.0/24)                                                       ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  [Bài 9 — app]                         [Bài 9 — host-sim]                                          ║ ┃  ║
║  ┃  ║  172.60.2.10                            172.60.2.5                                                   ║ ┃  ║
║  ┃  ║  Ubuntu 20.04                           Alpine (docker:24-dind)                                      ║ ┃  ║
║  ┃  ║  Container bị chiếm (shell SV)          Mô phỏng MÁY HOST                                           ║ ┃  ║
║  ┃  ║                                         Docker Engine (dockerd)                                      ║ ┃  ║
║  ┃  ║  Cấu hình YẾU cố ý:                    /var/run/docker.sock                                         ║ ┃  ║
║  ┃  ║   • --privileged                        /root/flag.txt  ← MỤC TIÊU                                  ║ ┃  ║
║  ┃  ║   • mount docker.sock ◄── socket ──►    /root/.hostmarker (canary)                                   ║ ┃  ║
║  ┃  ║   • CAP_SYS_ADMIN                                                                                   ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  Đường escape A: docker.sock ──► tạo container mới mount / ──► chroot ──► đọc flag                  ║ ┃  ║
║  ┃  ║  Đường escape B: mount /dev/sda1 ──► /mnt/host ──► đọc flag                                         ║ ┃  ║
║  ┃  ║  Đường escape C: nsenter --target 1 ──► shell host ──► đọc flag                                     ║ ┃  ║
║  ┃  ╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝ ┃  ║
║  ┃                                          │                                                               ┃  ║
║  ┃                                          ▼ (host = node Kubernetes)                                      ┃  ║
║  ┃  ╔═══════════════════════════════════════════════════════════════════════════════════════════════════════╗ ┃  ║
║  ┃  ║  TẦNG ORCHESTRATION — KUBERNETES  (Mạng 172.25.0.0/24)                    ★ ĐỈNH KILL-CHAIN ★      ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  [Bài 10 — k8s-node]                                                                               ║ ┃  ║
║  ┃  ║  172.25.0.20                                                                                        ║ ┃  ║
║  ┃  ║  Ubuntu 22.04 + k3s v1.28 (single-node: control-plane + worker)                                     ║ ┃  ║
║  ┃  ║  --disable traefik,servicelb,metrics-server  |  SQLite (thay etcd)                                   ║ ┃  ║
║  ┃  ║  ┌──────────────────────────────────────────────────────────────────────────────────────────────┐    ║ ┃  ║
║  ┃  ║  │  API Server :6443                                                                            │    ║ ┃  ║
║  ┃  ║  │                                                                                              │    ║ ┃  ║
║  ┃  ║  │  namespace: app                                                                              │    ║ ┃  ║
║  ┃  ║  │  ┌─────────────────────────────────────────────────────────────────────────────────────────┐ │    ║ ┃  ║
║  ┃  ║  │  │  pod: web-app                                                                           │ │    ║ ┃  ║
║  ┃  ║  │  │  ServiceAccount: web-sa  ← RBAC QUÁ RỘNG (list secrets, create pods)                    │ │    ║ ┃  ║
║  ┃  ║  │  │  /var/run/secrets/kubernetes.io/serviceaccount/token                                     │ │    ║ ┃  ║
║  ┃  ║  │  ├─────────────────────────────────────────────────────────────────────────────────────────┤ │    ║ ┃  ║
║  ┃  ║  │  │  Secret: db-credentials  (base64: username + password)                                   │ │    ║ ┃  ║
║  ┃  ║  │  │  ConfigMap: app-config   (LẪN secret plaintext — anti-pattern)                           │ │    ║ ┃  ║
║  ┃  ║  │  └─────────────────────────────────────────────────────────────────────────────────────────┘ │    ║ ┃  ║
║  ┃  ║  │                                                                                              │    ║ ┃  ║
║  ┃  ║  │  NODE FILESYSTEM:  /opt/host-secrets/flag.txt  ← MỤC TIÊU CUỐI CÙNG                         │    ║ ┃  ║
║  ┃  ║  │  (chỉ đọc được qua pod hostPath/privileged escape)                                           │    ║ ┃  ║
║  ┃  ║  └──────────────────────────────────────────────────────────────────────────────────────────────┘    ║ ┃  ║
║  ┃  ║                                                                                                     ║ ┃  ║
║  ┃  ║  Luồng: SA token ──► RBAC quá rộng ──► đọc secret ──► tạo pod hostPath ──► đọc flag NODE           ║ ┃  ║
║  ┃  ╚═══════════════════════════════════════════════════════════════════════════════════════════════════════╝ ┃  ║
║  ┃                                                                                                          ┃  ║
║  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  ║
║                                                                                                               ║
║  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  ║
║  ┃  LUỒNG KILL-CHAIN TỔNG THỂ (từ ngoài vào trong, từ nông đến sâu)                                       ┃  ║
║  ┃                                                                                                          ┃  ║
║  ┃   [1] IaC lộ ──► [2] Image ──► [3] Git secret ──► [4] App CVE ──► [5] S3 cloud                         ┃  ║
║  ┃   tfsec/checkov   docker/trivy   gitleaks/trufflehog  SCA+exploit    aws-cli+MinIO                      ┃  ║
║  ┃   lộ kiến trúc    lộ API key     lộ AWS key           chiếm shell    exfil dữ liệu                     ┃  ║
║  ┃       │               │              │                    │              │                                ┃  ║
║  ┃       └───────── cùng bộ credential cloud (mô-típ "credential sprawl") ─┘                                ┃  ║
║  ┃                                                                   │                                      ┃  ║
║  ┃   [6] WAF bảo vệ ──► [7] SSRF→IMDS ──► [8] Jenkins ──► [9] Docker escape ──► [10] K8s RBAC             ┃  ║
║  ┃   ModSec+CRS          cắp role cloud     RCE pipeline    thoát ra host         chiếm toàn cụm            ┃  ║
║  ┃   chặn SQLi/XSS       Capital One 2019   trộm cred       docker.sock          SA token→pod escape       ┃  ║
║  ┃                                                           privileged            hostPath→flag NODE        ┃  ║
║  ┃                                                                                                          ┃  ║
║  ┃   ═══════════════════════════════════════════════════════════════════════════                              ┃  ║
║  ┃   CƠ BẢN (★)                    TRUNG BÌNH (★★★★)              NÂNG CAO–ĐỈNH (★★★★★★★★★)               ┃  ║
║  ┃   Bài 1, 2                       Bài 3, 4, 5, 6                Bài 7, 8, 9, 10                           ┃  ║
║  ┃   ═══════════════════════════════════════════════════════════════════════════                              ┃  ║
║  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  ║
║                                                                                                               ║
║  TỔNG HỢP: 22 container  |  6 vùng mạng/tầng  |  10 bài lab  |  12 flag  |  40 nhiệm vụ  |  40 câu hỏi     ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### A.4 — Chi tiết từng bài (sơ đồ mạng + container + nhiệm vụ)

```
================================================================================
PHẦN C — CHI TIẾT TỪNG BÀI LAB
================================================================================

──────────────────────────────────────────────────────────────────────
C.1  BÀI 1 — dso-iac-scan  |  Bảo mật Infrastructure as Code
──────────────────────────────────────────────────────────────────────

Độ khó:      ★ (Cơ bản)
Số container: 1
Mạng:        172.25.0.0/24
Kill-chain:  Trinh sát — mã hạ tầng lộ

Sơ đồ mạng:
┌─────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24  (không ra Internet)      │
│                                                             │
│  [devsecops]  172.25.0.10                                   │
│  Ubuntu 20.04 | ~/iac-project/ (mã Terraform lỗi)          │
│  Công cụ: tfsec, checkov, trivy config, terraform, git     │
│  Script CI: ~/gate.sh → tiết lộ flag khi 0 HIGH/CRITICAL   │
│                                                             │
│  Kiến trúc mà Terraform MÔ TẢ (không tồn tại thật):        │
│  Internet ──► [SG] ──► EC2 ──► S3 bucket                   │
│                          └── IAM role/policy                │
└─────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ devsecops     │ 172.25.0.10  │ Ubuntu 20.04 │ terraform >= 1.5            │
  │               │              │              │ tfsec >= 1.28               │
  │               │              │              │ checkov >= 3.0 (Python)     │
  │               │              │              │ trivy >= 0.50               │
  │               │              │              │ git, grep, jq               │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (baseline_scan, fix_network_storage, fix_secret_iam, pass_gate)
Flag: 1 (khi quality gate đạt 0 HIGH/CRITICAL)
Khả thi: RẤT CAO — 1 container, phân tích tĩnh thuần túy


──────────────────────────────────────────────────────────────────────
C.2  BÀI 2 — dso-image-scan  |  Bảo mật Image Container
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★ (Cơ bản+)
Số container: 2
Mạng:        172.25.0.0/24
Kill-chain:  Thu thập — image nội bộ lộ API key

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24                                 │
│                                                                    │
│  [devsecops] 172.25.0.10  ◄──pull/scan──►  [registry] 172.25.0.20│
│  Ubuntu 20.04                                Alpine (registry:2) │
│  trivy, grype, syft,                         Docker Registry v2   │
│  docker CLI, jq, tar                         Image CloudNova      │
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ devsecops     │ 172.25.0.10  │ Ubuntu 20.04 │ trivy, grype, syft          │
  │               │              │              │ docker CLI, jq, tar         │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ registry      │ 172.25.0.20  │ Alpine 3.18  │ Docker Registry v2          │
  │               │              │              │ Image dàn dựng sẵn          │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (scan_image, analyze_layers, exploit_leaked_secret, harden_image)
Flag: 1 (qua khai thác API key lộ trong layer)
Khả thi: CAO


──────────────────────────────────────────────────────────────────────
C.3  BÀI 3 — dso-secrets-git  |  Bí mật trong lịch sử Git
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★★ (Trung bình)
Số container: 2
Mạng:        172.25.0.0/24
Kill-chain:  Thu thập — mã nguồn lộ credential

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24                                 │
│                                                                    │
│  [attacker] 172.25.0.10  ◄──git clone──►  [gitserver] 172.25.0.20│
│  Ubuntu 20.04                              Gitea 1.21 (Alpine)    │
│  git, gitleaks, trufflehog                 Repo CloudNova         │
│  git-filter-repo                           (lịch sử commit lỗi)  │
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ attacker      │ 172.25.0.10  │ Ubuntu 20.04 │ git, gitleaks >= 8.18       │
  │               │              │              │ trufflehog >= 3.70          │
  │               │              │              │ git-filter-repo >= 2.38     │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ gitserver     │ 172.25.0.20  │ Alpine/Debian│ Gitea 1.21                  │
  │               │              │              │ Repo dàn dựng sẵn           │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (clone_scan, deep_history, exploit_credential, harden_purge)
Flag: 1 (dùng credential lộ truy cập dịch vụ đích)
Khả thi: CAO


──────────────────────────────────────────────────────────────────────
C.4  BÀI 4 — dso-supplychain-sca  |  SCA & SBOM (Chuỗi cung ứng)
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★★★ (Trung bình)
Số container: 1-2
Mạng:        172.25.0.0/24
Kill-chain:  Chiếm chỗ đứng — khai thác CVE phụ thuộc

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24                                 │
│                                                                    │
│  [devsecops] 172.25.0.10  ◄──HTTP──►  [appserver] 172.25.0.20   │
│  Ubuntu 20.04                          Node.js 18 LTS (Debian)   │
│  npm audit, retire.js, snyk            App có CVE (prototype     │
│  syft, grype, jq                       pollution / deserialization)│
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ devsecops     │ 172.25.0.10  │ Ubuntu 20.04 │ npm >= 9.x, retire.js >= 4  │
  │               │              │              │ syft, grype, snyk (opt.)    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ appserver     │ 172.25.0.20  │ Debian 12    │ Node.js 18 LTS, npm         │
  │  (tùy chọn)  │              │              │ node_modules cài sẵn offline │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (audit_deps, generate_sbom, exploit_cve, fix_deps)
Flag: 1 (khai thác CVE thành công)
Khả thi: TRUNG BÌNH–CAO (cần chốt CVE tái lập offline)
Hệ sinh thái: Node.js (npm) ✅ ĐÃ CHỐT


──────────────────────────────────────────────────────────────────────
C.5  BÀI 5 — cloud-s3-misconfig  |  Object Storage cấu hình sai
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★★★ (Trung bình)
Số container: 2
Mạng:        172.25.0.0/24
Kill-chain:  Rò rỉ dữ liệu cloud

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24                                 │
│                                                                    │
│  [attacker] 172.25.0.10  ◄──S3 API 9000──►  [storage] 172.25.0.20│
│  Ubuntu 20.04                                 MinIO Server        │
│  aws-cli v2, curl, jq, mc                     Buckets:            │
│                                                 public-assets     │
│                                                 internal-backup   │
│                                                 finance-reports   │
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ attacker      │ 172.25.0.10  │ Ubuntu 20.04 │ aws-cli v2, curl, jq, mc   │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ storage       │ 172.25.0.20  │ Debian 12    │ MinIO Server (latest)       │
  │               │              │              │ Cổng: 9000 (S3 API)         │
  │               │              │              │       9001 (Console)        │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (discover_public, exfil_backup, access_private, harden_bucket)
Flag: 2 (bucket public + bucket private)
Khả thi: CAO


──────────────────────────────────────────────────────────────────────
C.6  BÀI 6 — dso-waf-crs  |  WAF Runtime (ModSecurity + CRS)
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★★★★ (Trung bình khá)
Số container: 3
Mạng:        172.25.0.0/24
Kill-chain:  Vận hành — bảo vệ app

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24                                 │
│                                                                    │
│  [client]  ──HTTP:80──►  [waf]  ──HTTP:8080──►  [webapp]          │
│  .10                     .20                     .30               │
│  curl, nikto             nginx 1.24              Flask (Python)    │
│  (ZAP tùy chọn)         + ModSecurity v3         SQLi, XSS,       │
│                          + OWASP CRS 4.x         Path Traversal   │
│                          audit log               flag1.txt         │
│                                                                    │
│  Luồng CHƯA có WAF: client ──────────────────► webapp:8080       │
│  Luồng CÓ WAF:     client ──► waf:80 ────────► webapp:8080      │
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ client        │ 172.25.0.10  │ Ubuntu 20.04 │ curl, nikto >= 2.5          │
  │               │              │              │ ZAP >= 2.14 (tùy chọn)     │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ waf           │ 172.25.0.20  │ Debian 12    │ nginx 1.24                  │
  │               │              │              │ libmodsecurity3 >= 3.0.12   │
  │               │              │              │ modsecurity-nginx >= 1.0.3  │
  │               │              │              │ OWASP CRS >= 4.0            │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ webapp        │ 172.25.0.30  │ Debian 12    │ Python 3.11, Flask 3.x      │
  │               │              │              │ App lỗ hổng cố ý            │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (exploit_direct, deploy_waf, dast_compare, tune_falsepositive)
Flag: 3 (khai thác trực tiếp, WAF chặn, khử false positive)
Khả thi: TRUNG BÌNH (ModSecurity cần build sẵn, ZAP nặng)


──────────────────────────────────────────────────────────────────────
C.7  BÀI 7 — cloud-ssrf-imds  |  SSRF → Cloud Metadata
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★★★★★ (Nâng cao)
Số container: 4
Mạng:        172.25.0.0/24
Kill-chain:  Leo thang vào cloud (Capital One 2019)

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24                                 │
│                                                                    │
│  [client] .10                                                      │
│    │ (1) HTTP "fetch URL"                                          │
│    ▼                                                               │
│  [webapp] .20 (:8080) ──(2) SSRF──► [imds] 169.254.169.254        │
│  "imgproxy-portal"                   IMDS giả (Python httpd)      │
│  Flask + SSRF cố ý                  /latest/meta-data/...         │
│    │                                credential tạm thời            │
│    │ (4) credential                                                │
│    ▼                                                               │
│  [storage] .30 (:9000)                                             │
│  MinIO (S3-compatible)                                             │
│  Bucket: fin-reports → flag.txt                                    │
│                                                                    │
│  GHI CHÚ: client KHÔNG truy cập trực tiếp imds/storage            │
│           (theo kịch bản — chỉ qua webapp)                         │
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ client        │ 172.25.0.10  │ Ubuntu 20.04 │ curl, aws-cli v2, jq        │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ webapp        │ 172.25.0.20  │ Debian 12    │ Python 3.11, Flask          │
  │               │              │              │ App dính SSRF cố ý          │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ imds          │ 169.254.169. │ Alpine 3.18  │ Python http.server custom   │
  │               │ 254 (alias)  │              │ /latest/meta-data/...       │
  │               │              │              │ IMDSv1 (mặc định) + IMDSv2  │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ storage       │ 172.25.0.30  │ Debian 12    │ MinIO Server (latest)       │
  │               │              │              │ Bucket: fin-reports         │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (discover_ssrf, steal_credentials, access_storage_get_flag, harden_ssrf_imds)
Flag: 1 (qua SSRF → IMDS → credential → S3 → flag)
Khả thi: TRUNG BÌNH–CAO


──────────────────────────────────────────────────────────────────────
C.8  BÀI 8 — dso-cicd-jenkins  |  Bảo mật CI/CD (Jenkins)
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★★★★★★ (Nâng cao)
Số container: 3
Mạng:        172.25.0.0/24
Kill-chain:  Chiếm pipeline

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24                                 │
│                                                                    │
│  [attacker] .10 ──HTTP:8080──► [jenkins] .20 ──HTTP──► [git] .30 │
│  curl, jq, git                 Flask mock (mặc định)   Gitea 1.21│
│  jenkins-cli.jar               HOẶC Jenkins LTS thật   Repo CI   │
│                                 Script Console           + Registry│
│                                 Credential Store                   │
│                                 Build trigger                      │
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ attacker      │ 172.25.0.10  │ Ubuntu 20.04 │ curl, jq, git               │
  │               │              │              │ jenkins-cli.jar             │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ jenkins       │ 172.25.0.20  │ Debian 12    │ Phương án A (mặc định):     │
  │               │              │              │   Python 3.11 + Flask mock  │
  │               │              │              │ Phương án B (tùy chọn):     │
  │               │              │              │   Jenkins LTS 2.426+ (JVM)  │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ gitserver     │ 172.25.0.30  │ Alpine/Debian│ Gitea 1.21                  │
  │               │              │              │ Docker Registry (tùy chọn)  │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (recon_jenkins, rce_script_console, steal_credentials, harden_jenkins)
Flag: 1 (RCE qua Script Console)
Khả thi: TRUNG BÌNH
Phương án mặc định: Mock Flask ✅ ĐÃ CHỐT


──────────────────────────────────────────────────────────────────────
C.9  BÀI 9 — dso-docker-escape  |  Thoát container chiếm host
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★★★★★★★ (Nâng cao)
Số container: 2
Mạng:        172.60.2.0/24
Kill-chain:  Thoát ra host

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.60.2.0/24                                 │
│                                                                    │
│  [app]  172.60.2.10                   [host-sim]  172.60.2.5      │
│  Ubuntu 20.04                          Alpine (docker:24-dind)    │
│  (shell SV — attacker)                 (mô phỏng host)           │
│                                                                    │
│  Cấu hình YẾU cố ý:                   Docker daemon (dockerd)    │
│   • /var/run/docker.sock ──mount──►    /var/run/docker.sock       │
│   • --privileged                       /root/flag.txt (mục tiêu)  │
│   • CAP_SYS_ADMIN                     /root/.hostmarker (canary) │
│                                                                    │
│  Công cụ: docker CLI, mount,                                      │
│  nsenter, capsh, getcap,                                           │
│  fdisk, lsblk, deepce (opt.)                                      │
│                                                                    │
│  Luồng escape:                                                     │
│  Đường A: app ──docker.sock──► host-sim daemon ──► container mới  │
│           mount / host → chroot → đọc flag                         │
│  Đường B: app ──mount /dev/sda1──► /mnt/host → đọc flag           │
│  Đường C: app ──nsenter --target 1──► shell trên host             │
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ app           │ 172.60.2.10  │ Ubuntu 20.04 │ docker CLI >= 24            │
  │               │              │              │ libcap2-bin (capsh/getcap)  │
  │               │              │              │ util-linux (nsenter/mount)  │
  │               │              │              │ deepce.sh (tùy chọn)       │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ host-sim      │ 172.60.2.5   │ Alpine       │ docker:24-dind              │
  │               │              │ (DinD image) │ Docker Engine (dockerd)     │
  │               │              │              │ /root/flag.txt              │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 5 (recon_container, escape_via_socket, escape_via_privileged,
              get_flag, harden_container)
Flag: 1 (PTIT{...} trên host-sim)
Khả thi: TRUNG BÌNH–THẤP (nested DinD cần kiểm thử)
Đường chính: docker.sock (ổn định) ✅


──────────────────────────────────────────────────────────────────────
C.10  BÀI 10 — cloud-k8s-rbac  |  Bảo mật Kubernetes (RBAC)
──────────────────────────────────────────────────────────────────────

Độ khó:      ★★★★★★★★★ (Chuyên sâu — đỉnh)
Số container: 2
Mạng:        172.25.0.0/24
Kill-chain:  Chiếm toàn cụm

Sơ đồ mạng:
┌────────────────────────────────────────────────────────────────────┐
│  Mạng ảo Labtainer 172.25.0.0/24                                 │
│                                                                    │
│  [attacker] 172.25.0.10                                            │
│  Ubuntu 20.04                                                      │
│  kubectl, base64, jq, curl                                         │
│  (mô phỏng shell trong pod web-app bị chiếm)                      │
│    │                                                               │
│    │  kubectl / curl --token=<SA token>                            │
│    ▼                                                               │
│  [k8s-node] 172.25.0.20                                            │
│  Ubuntu 22.04 + k3s v1.28 (single-node: control-plane + worker)   │
│    ├─ API server :6443                                             │
│    ├─ namespace app:                                               │
│    │   ├─ pod web-app (SA: web-sa ← RBAC quá rộng)                │
│    │   ├─ ConfigMap app-config (LẪN secret plaintext)              │
│    │   └─ Secret db-credentials                                    │
│    └─ FILESYSTEM NODE: /opt/host-secrets/flag.txt (mục tiêu)      │
│                                                                    │
│  Luồng khai thác:                                                  │
│  đọc SA token → liệt kê RBAC (list secrets / create pods)         │
│  → đọc Secret + ConfigMap lộ secret                                │
│  → tạo pod hostPath/privileged → đọc flag trên node               │
└────────────────────────────────────────────────────────────────────┘

Containers:
  ┌───────────────┬──────────────┬──────────────┬─────────────────────────────┐
  │ Tên           │ IP           │ OS           │ Phần mềm                    │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ attacker      │ 172.25.0.10  │ Ubuntu 20.04 │ kubectl >= 1.28             │
  │               │              │              │ base64, jq, curl            │
  │               │              │              │ kube-linter, kubesec (opt.) │
  ├───────────────┼──────────────┼──────────────┼─────────────────────────────┤
  │ k8s-node      │ 172.25.0.20  │ Ubuntu 22.04 │ k3s v1.28 (single-node)    │
  │               │              │              │ --disable traefik,servicelb │
  │               │              │              │ --disable metrics-server    │
  │               │              │              │ SQLite (thay etcd)          │
  │               │              │              │ busybox/alpine (cached)     │
  │               │              │              │ kube-bench >= 0.7 (opt.)    │
  └───────────────┴──────────────┴──────────────┴─────────────────────────────┘

Nhiệm vụ: 4 (recon_rbac, loot_secrets, escape_node, harden_cluster)
Flag: 1 (trên filesystem node)
Khả thi: THẤP–TRUNG BÌNH (k3s nặng RAM)
Phương án mặc định: k3s thật ✅ ĐÃ CHỐT
Phương án dự phòng: Audit tĩnh manifest + API mock
Yêu cầu tối thiểu: 2 vCPU, 2–3 GB RAM


================================================================================
PHẦN D — YÊU CẦU TÀI NGUYÊN & TỔNG HỢP PHIÊN BẢN
================================================================================

D.1  YÊU CẦU TÀI NGUYÊN VM LABTAINER
──────────────────────────────────────

┌────────────────────────────────┬────────────┬───────────┬──────────────────────┐
│ Nhóm bài                       │ RAM tối    │ CPU tối   │ Ghi chú              │
│                                │ thiểu      │ thiểu     │                      │
├────────────────────────────────┼────────────┼───────────┼──────────────────────┤
│ Bài 1, 4                       │ 1 GB       │ 1 vCPU    │ 1 container, nhẹ     │
│ Bài 2, 3, 5                    │ 2 GB       │ 1 vCPU    │ 2 container nhẹ      │
│ Bài 6, 7, 8                    │ 2–3 GB     │ 2 vCPU    │ 3-4 container        │
│ Bài 9                           │ 3–4 GB     │ 2 vCPU    │ DinD cần RAM         │
│ Bài 10                          │ 3–4 GB     │ 2 vCPU    │ k3s cần RAM + CPU    │
├────────────────────────────────┼────────────┼───────────┼──────────────────────┤
│ KHUYẾN NGHỊ CHUNG VM           │ >= 4 GB    │ 2 vCPU    │ Chạy được mọi bài    │
└────────────────────────────────┴────────────┴───────────┴──────────────────────┘

D.2  THỐNG KÊ NHANH
─────────────────────

- Tổng số bài lab:          10
- Tổng số container:        22 (không chạy đồng thời)
- Container/bài ít nhất:     1 (Bài 1, Bài 4)
- Container/bài nhiều nhất:  4 (Bài 7)
- Bài nhẹ nhất:             Bài 1 (phân tích tĩnh, 1 container)
- Bài nặng nhất:            Bài 10 (k3s cluster)
- Hệ sinh thái lập trình:   Node.js (Bài 4), Python/Flask (Bài 6,7,8)
- Cloud mock:               MinIO (Bài 5,7), IMDS mock (Bài 7)
- Orchestration:            k3s/Kubernetes (Bài 10)
- WAF:                      ModSecurity v3 + OWASP CRS (Bài 6)
- CI/CD:                    Jenkins mock (Flask) / Jenkins LTS thật (Bài 8)

D.3  ÁNH XẠ KHUNG THAM CHIẾU TỔNG HỢP
─────────────────────────────────────────

┌──────┬───────────────────────────────────┬────────────────────────────────────┐
│ Bài  │ MITRE ATT&CK                      │ OWASP / CIS                        │
├──────┼───────────────────────────────────┼────────────────────────────────────┤
│  1   │ T1190, T1552, T1078, T1562.008    │ OWASP IaC, CIS AWS 1-5             │
│  2   │ T1525, T1552, T1204.003           │ CIS Docker 4.x/5.x                │
│  3   │ T1552.001                          │ OWASP Secrets Management           │
│  4   │ T1195.001, T1195.002              │ OWASP A06:2021 (Vulnerable Comp.)  │
│  5   │ T1530                              │ CIS AWS 2.1.x (S3)                │
│  6   │ A03 Injection, A05 Misconfig       │ OWASP CRS, DevSecOps Guideline     │
│  7   │ T1552.005 (IMDS)                  │ OWASP A10:2021 (SSRF)              │
│  8   │ T1072, T1059.004, T1552.001       │ CIS Jenkins Benchmark              │
│  9   │ T1611 (Escape to Host)            │ CIS Docker 5.3/5.4/5.31           │
│ 10   │ T1552.001, T1610, T1611, T1613    │ OWASP K8s Top 10, CIS K8s         │
└──────┴───────────────────────────────────┴────────────────────────────────────┘

================================================================================
KẾT THÚC TÀI LIỆU
================================================================================
```

# PHỤ LỤC B — ÁNH XẠ BÀI LAB ↔ ĐỀ CƯƠNG MÔN HỌC (SEC1412_CLC)


**Môn học:** Introduction to DevOps — SEC1412_CLC  
**Số tín chỉ:** 3 | **Lab:** 8h | **Project:** 8h  
**Ngày tạo:** 30/09/2026

---

## 1. CẤU TRÚC ĐỀ CƯƠNG (tóm tắt)

| Chương | Tên chủ đề | Thời lượng lý thuyết | Lab/Project |
|--------|-----------|---------------------|-------------|
| Ch.1 | Introduction to DevOps | 3h lecture | — |
| Ch.2 | Security in DevOps | 4h lecture + 1h exercise | — |
| Ch.3 | Containerization & Cloud Computing | 4h lecture + 2h exercise | **3h lab + 3h project** |
| Ch.4 | Continuous Integration & Deployment | 6h lecture + 1h exercise | **3h lab + 3h project** |
| Ch.5 | Design Options (SOA, Microservices) | 4h lecture + 1h exercise | **2h lab + 2h project** |
| Ch.6 | Secure Development & DevSecOps | 3h lecture | — |

**Course Learning Outcomes:**
- **CLO1:** Identify requirements that integrate software development and IT operations → Ch.1, 2, 6
- **CLO2:** Describe & select appropriate tools/techniques to enhance security, efficiency, quality in DevOps phases → Ch.3, 4, 5, 6

---

## 2. BẢNG MAPPING CHÍNH: LAB ↔ ĐỀ CƯƠNG

| # | Tên Lab | Chương chính | Mục cụ thể | CLO | Độ phủ lý thuyết |
|---|---------|-------------|-----------|-----|-----------------|
| **Bài 1** | `dso-iac-scan` — IaC Security | **Ch.3** + Ch.6 | 3.2 Cloud Computing, 3.3 VMs vs Containers; 6.1 What to protect, 6.2 Vulnerability Discovery | CLO1, CLO2 | ★★★★☆ |
| **Bài 2** | `dso-image-scan` — Image Security | **Ch.3** | 3.1 Docker Basics, 3.3 VMs vs Containers | CLO2 | ★★★★★ |
| **Bài 3** | `dso-secrets-git` — Secrets in Git | **Ch.6** + Ch.2 | 6.1 What to protect, 6.2 Vulnerability Discovery; 2.2 Security Best Practices | CLO1, CLO2 | ★★★★☆ |
| **Bài 4** | `dso-supplychain-sca` — SCA & SBOM | **Ch.6** + Ch.2 | 6.2 Vulnerability Discovery & Patching; 2.3 Vulnerability Management | CLO2 | ★★★★★ |
| **Bài 5** | `cloud-s3-misconfig` — S3 Misconfig | **Ch.3** + Ch.2 | 3.2 Cloud Computing; 2.2 Security Best Practices, 2.4 Compliance & Governance | CLO1, CLO2 | ★★★☆☆ |
| **Bài 6** | `dso-waf-crs` — WAF Runtime | **Ch.6** + Ch.4 | 6.4 DevSecOps, 6.3 Authentication & Authorization; 4.5 Monitoring & Logging | CLO2 | ★★★★☆ |
| **Bài 7** | `cloud-ssrf-imds` — SSRF→IMDS | **Ch.3** + Ch.6 | 3.2 Cloud Computing; 6.2 Vulnerability Discovery, 6.1 What to protect | CLO1, CLO2 | ★★★☆☆ |
| **Bài 8** | `dso-cicd-jenkins` — CI/CD Security | **Ch.4** + Ch.6 | 4.1 CI, 4.2 CI Setup, 4.3 Automated Builds, 4.4 Deployment Pipeline; 6.4 DevSecOps | CLO1, CLO2 | ★★★★★ |
| **Bài 9** | `dso-docker-escape` — Container Escape | **Ch.3** + Ch.2 | 3.1 Docker Basics, 3.3 VMs vs Containers; 2.1 Principles, 2.2 Security Best Practices | CLO1, CLO2 | ★★★★☆ |
| **Bài 10** | `cloud-k8s-rbac` — Kubernetes RBAC | **Ch.3** + Ch.5 + Ch.6 | 3.1 Docker/Containers; 5.3 Microservice Architecture; 6.3 Auth & Authorization, 6.4 DevSecOps | CLO2 | ★★★★★ |

---

## 3. MAP THEO TỪNG CHƯƠNG ĐỀ CƯƠNG

### 📘 Chapter 1 — Introduction to DevOps
> **Nội dung:** What is DevOps? · Principles & Culture · Lifecycle · Benefits

| Lab liên quan | Mức độ | Ghi chú |
|--------------|--------|---------|
| Tất cả 10 bài | ★★☆☆☆ | Ngữ cảnh nền — sinh viên hiểu DevOps lifecycle qua thực tế vận hành |
| **Bài 8** (Jenkins CI/CD) | ★★★☆☆ | Minh họa trực tiếp DevOps pipeline: code → build → deploy |

> ⚠️ **Nhận xét:** Chương 1 là lý thuyết thuần túy, không có bài lab riêng. Nội dung lab nên mở đầu bằng 1–2 slide nhắc lại DevOps lifecycle trước khi vào thực hành.

---

### 📘 Chapter 2 — Security in DevOps
> **Nội dung:** 2.1 Principles · 2.2 Security Best Practices · 2.3 Vulnerability Management · 2.4 Compliance & Governance

| Lab liên quan | Mục bao phủ | Mức độ |
|--------------|------------|--------|
| **Bài 4** (SCA & SBOM) | 2.3 Vulnerability Management | ★★★★★ |
| **Bài 3** (Secrets in Git) | 2.2 Security Best Practices | ★★★★☆ |
| **Bài 9** (Docker Escape) | 2.1 Security Principles, 2.2 Best Practices | ★★★★☆ |
| **Bài 5** (S3 Misconfig) | 2.4 Compliance & Governance | ★★★☆☆ |

> ✅ **Nhận xét:** Chương 2 được bao phủ tốt — đặc biệt Vulnerability Management (Bài 4) và Security Best Practices (Bài 3, 9). Chỉ thiếu phần **2.4 Compliance & Governance** (chỉ được chạm nhẹ qua Bài 5).

---

### 📘 Chapter 3 — Containerization & Cloud Computing
> **Nội dung:** 3.1 Docker Basics · 3.2 Cloud Computing · 3.3 VMs vs Containers · 3.4 Serverless Computing  
> **Thời lượng thực hành:** 3h lab + 3h project

| Lab liên quan | Mục bao phủ | Mức độ |
|--------------|------------|--------|
| **Bài 9** (Docker Escape) | 3.1 Docker Basics, 3.3 VMs vs Containers | ★★★★★ |
| **Bài 2** (Image Scan) | 3.1 Docker Basics, 3.3 VMs vs Containers | ★★★★★ |
| **Bài 1** (IaC Scan) | 3.2 Cloud Computing | ★★★★☆ |
| **Bài 5** (S3 Misconfig) | 3.2 Cloud Computing | ★★★★☆ |
| **Bài 7** (SSRF→IMDS) | 3.2 Cloud Computing | ★★★☆☆ |
| **Bài 10** (K8s RBAC) | 3.1 Docker/Containers | ★★★★☆ |

> ✅ **Nhận xét:** Chương 3 được bao phủ **rất tốt và toàn diện nhất**. Docker (Bài 2, 9), Cloud (Bài 1, 5, 7), Kubernetes (Bài 10).  
> ⚠️ **Thiếu:** 3.4 Serverless Computing — không có bài lab nào đề cập trực tiếp.

---

### 📘 Chapter 4 — Continuous Integration & Deployment
> **Nội dung:** 4.1 CI · 4.2 CI Setup · 4.3 Automated Builds & Testing · 4.4 Deployment Pipeline · 4.5 Monitoring & Logging  
> **Thời lượng thực hành:** 3h lab + 3h project

| Lab liên quan | Mục bao phủ | Mức độ |
|--------------|------------|--------|
| **Bài 8** (Jenkins CI/CD) | 4.1, 4.2, 4.3, 4.4 — toàn bộ CI/CD | ★★★★★ |
| **Bài 6** (WAF CRS) | 4.5 Monitoring & Logging (audit log WAF) | ★★★☆☆ |
| **Bài 1** (IaC Scan) | 4.3 Automated Testing (quality gate CI) | ★★★☆☆ |

> ⚠️ **Nhận xét:** Bài 8 bao phủ rất tốt CI/CD nhưng **chỉ có 1 bài duy nhất** cho cả Chương 4. Mục **4.5 Monitoring & Logging** còn yếu — cần bổ sung nhiệm vụ xem/phân tích log pipeline trong Bài 8.

---

### 📘 Chapter 5 — Design Options (SOA, Microservices)
> **Nội dung:** 5.1 Intro · 5.2 Service-oriented Architecture · 5.3 Microservice Architecture · 5.4 Microservice Qualities  
> **Thời lượng thực hành:** 2h lab + 2h project

| Lab liên quan | Mục bao phủ | Mức độ |
|--------------|------------|--------|
| **Bài 10** (K8s RBAC) | 5.3 Microservice Architecture (Kubernetes orchestration) | ★★★☆☆ |
| **Bài 8** (Jenkins) | 5.2 SOA (pipeline = service-oriented workflow) | ★★☆☆☆ |

> ⚠️ **Nhận xét:** Chương 5 được bao phủ **yếu nhất**. Các bài lab tập trung vào bảo mật, không đi sâu vào thiết kế kiến trúc.  
> 📌 **Đề xuất:** Thêm phần giới thiệu ngắn về microservice architecture trong **Bài 10** hoặc tạo nhiệm vụ "thiết kế sơ đồ kiến trúc CloudNova" làm phần project.

---

### 📘 Chapter 6 — Secure Development & DevSecOps
> **Nội dung:** 6.1 What to protect · 6.2 Vulnerability Discovery & Patching · 6.3 Auth & Authorization · 6.4 DevSecOps

| Lab liên quan | Mục bao phủ | Mức độ |
|--------------|------------|--------|
| **Bài 4** (SCA) | 6.2 Vulnerability Discovery & Patching | ★★★★★ |
| **Bài 1** (IaC Scan) | 6.2 Vulnerability Discovery (shift-left) | ★★★★★ |
| **Bài 10** (K8s RBAC) | 6.3 Authentication & Authorization | ★★★★★ |
| **Bài 6** (WAF) | 6.4 DevSecOps (runtime protection) | ★★★★★ |
| **Bài 3** (Secrets Git) | 6.1 What to protect, 6.2 Discovery | ★★★★☆ |
| **Bài 8** (Jenkins) | 6.4 DevSecOps (secure pipeline) | ★★★★☆ |
| **Bài 9** (Docker Escape) | 6.4 DevSecOps (hardening) | ★★★★☆ |
| **Bài 7** (SSRF) | 6.1 What to protect | ★★★☆☆ |
| **Bài 5** (S3) | 6.1 What to protect | ★★★☆☆ |

> ✅ **Nhận xét:** Chương 6 là **chương được bao phủ tốt nhất** — đúng với định hướng bảo mật 60%. Mỗi bài đều có nhiệm vụ hardening/remediation (Blue team).

---

## 4. MA TRẬN TỔNG HỢP

```
              Ch.1  Ch.2  Ch.3  Ch.4  Ch.5  Ch.6
              Intro SecDev Cont  CI/CD Design SecDev
              ────────────────────────────────────
Bài 1  IaC    ░░    ░░    ████  ░░░   ░     ████
Bài 2  Image  ░     ░     █████ ░     ░     ░░
Bài 3  Git    ░     ████  ░     ░     ░     ████
Bài 4  SCA    ░     █████ ░     ░     ░     █████
Bài 5  S3     ░     ░░░   ████  ░     ░     ░░░
Bài 6  WAF    ░     ░░    ░     ░░░   ░     █████
Bài 7  SSRF   ░     ░     ░░░   ░     ░     ░░░
Bài 8  CI/CD  ░░░   ░     ░     █████ ░░    ████
Bài 9  Docker ░     ████  █████ ░     ░     ████
Bài 10 K8s    ░     ░     ████  ░     ░░░   █████
──────────────────────────────────────────────────
Độ phủ       Thấp  Tốt   Xuất  Trung Thấp  Xuất
             ★★    ★★★★  ★★★★★ ★★★   ★★    ★★★★★
```

*(█ = bao phủ trực tiếp, ░ = liên quan gián tiếp)*

---

## 5. PHÂN BỔ GIỜ LAB (8h tổng) THEO ĐỀ CƯƠNG

| Chương | Bài lab được phân công | Giờ lab | Ghi chú |
|--------|----------------------|---------|---------|
| **Ch.3** (3h lab) | Bài 2 (Image Scan) + Bài 9 (Docker Escape) | 3h | Bài 2: 1.5h · Bài 9: 1.5h |
| **Ch.4** (3h lab) | Bài 8 (Jenkins CI/CD) + Bài 1 (IaC/quality gate) | 3h | Bài 8: 2h · Bài 1: 1h |
| **Ch.5** (2h lab) | Bài 10 (K8s RBAC) | 2h | K8s minh họa microservice runtime |

> 📌 **Các bài còn lại** (3, 4, 5, 6, 7) phù hợp làm **Course Project (8h)** hoặc bài tập ngoài giờ, vì nội dung nâng cao và thiên về bảo mật cloud.

---

## 6. KHOẢNG TRỐNG & ĐỀ XUẤT BỔ SUNG

| Mục đề cương | Hiện trạng | Đề xuất |
|-------------|-----------|---------|
| **3.4 Serverless Computing** | ❌ Chưa có bài nào | Thêm phần demo ngắn về Function-as-a-Service trong Bài 7 (context cloud IMDS) |
| **4.5 Monitoring & Logging** | ⚠️ Rất yếu | Bổ sung nhiệm vụ xem log CI pipeline vào Bài 8 |
| **5.2 SOA Architecture** | ❌ Gần như không có | Bổ sung diagram kiến trúc CloudNova theo SOA trong phần giới thiệu Bài 10 |
| **5.4 Microservice Qualities** | ❌ Không đề cập | Đề cập trong hardening Bài 10: isolation, observability, least privilege |
| **2.4 Compliance & Governance** | ⚠️ Yếu | Tăng cường trong Bài 1: CIS benchmarks, OWASP standards |

---

## 7. GẮN NHÃN CLO CHO CÁC BÀI LAB

**CLO1** — Identify requirements that integrate software dev & IT operations (Ch.1, 2, 6):
> Bài 1, 3, 5, 7, 8, 9 *(hiểu vì sao cần bảo mật ở từng tầng DevOps)*

**CLO2** — Select appropriate tools & techniques (Ch.3, 4, 5, 6):
> Bài 2, 4, 6, 8, 10 *(thực hành công cụ: Trivy, npm audit, ModSecurity, Jenkins, kubectl)*

> 💡 **Gợi ý rubric chấm điểm Project (30%):**  
> Yêu cầu sinh viên chọn **3/10 bài lab**, thực hiện và viết báo cáo map rõ:  
> (1) bài lab thuộc chương nào của đề cương,  
> (2) công cụ sử dụng và kết quả,  
> (3) lỗ hổng phát hiện và biện pháp khắc phục  
> → đảm bảo bao phủ đủ CLO1 + CLO2.
