**KỊCH BẢN 10 BÀI LAB --- CLOUD / DEVOPS / DEVSECOPS (SẮP XẾP THEO ĐỘ
KHÓ TĂNG DẦN)**

Định hướng: Cloud -- DevOps -- DevSecOps; trọng tâm an toàn thông tin,
có kèm thiết lập môi trường.

Bối cảnh chung: Sinh viên tham gia một chiến dịch đánh giá an ninh cho
hệ thống cloud-native của một công ty công nghệ (giả định). Mười bài đi
từ ngoài vào trong, độ khó tăng dần; mỗi bài sinh viên vừa khai thác lỗ
hổng (mũ đỏ) vừa vá lỗi (mũ xanh -- DevSecOps). Các bài độc lập, có thể
thực hiện theo thứ tự bất kỳ.

**MỤC TIÊU CHUNG**

Sau khi hoàn thành toàn bộ, người học có khả năng:

- Diễn giải được các vấn đề cơ bản và các kỹ thuật/công nghệ cốt lõi của
  DevOps (điện toán đám mây, container, CI/CD, phát triển an toàn ---
  DevSecOps).
- Áp dụng các công cụ và kỹ thuật DevOps để phát triển, vận hành hệ
  thống một cách an toàn, hiệu quả và tin cậy.
- Đánh giá và lựa chọn được giải pháp bảo mật phù hợp cho từng giai đoạn
  của vòng đời DevOps (phát hiện lỗ hổng, khắc phục, kiểm soát truy cập,
  tuân thủ).
- Rèn tư duy "shift-left": đưa kiểm tra an toàn vào sớm trong quy trình
  phát triển và triển khai, thay vì xử lý sau khi hệ thống đã vận hành.

Mỗi bài theo mô hình "hai mũ": người học vừa đóng vai tấn công (khai
thác lỗ hổng thật) để hiểu rủi ro, vừa đóng vai kỹ sư DevSecOps (vá lỗi,
hardening) để khắc phục triệt để. Các bài độc lập, chạy offline trên
Labtainer, có thể thực hiện theo thứ tự bất kỳ.

\newpage

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

**Ánh xạ đề cương:** Chương chính: Chương 3 --- Container và điện toán đám mây (3.2. Điện toán đám mây; 3.3. Máy ảo và container). Chương liên quan: Chương 6 (6.2. Phát hiện và vá lỗ hổng --- shift-left).

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

**Ánh xạ đề cương:** Chương chính: Chương 3 --- Container và điện toán đám mây (3.1. Kiến thức cơ bản về Docker; 3.3. Máy ảo và container).

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

**Ánh xạ đề cương:** Chương chính: Chương 6 --- Phát triển an toàn (6.1. Mục tiêu bảo vệ; 6.2. Phát hiện và vá lỗ hổng). Chương liên quan: Chương 2 (2.2. Thực tiễn đảm bảo an toàn).

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

**Ánh xạ đề cương:** Chương chính: Chương 6 --- Phát triển an toàn (6.2. Phát hiện và vá lỗ hổng). Chương liên quan: Chương 2 (2.3. Quản lý lỗ hổng).

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

**Ánh xạ đề cương:** Chương chính: Chương 3 --- Container và điện toán đám mây (3.2. Điện toán đám mây). Chương liên quan: Chương 2 (2.2. Thực tiễn đảm bảo an toàn; 2.4. Tuân thủ và quản trị).

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

**Ánh xạ đề cương:** Chương chính: Chương 6 --- Phát triển an toàn (6.4. DevSecOps; 6.3. Xác thực và ủy quyền). Chương liên quan: Chương 4 (4.5. Giám sát và ghi nhật ký).

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

**Ánh xạ đề cương:** Chương chính: Chương 3 --- Container và điện toán đám mây (3.2. Điện toán đám mây). Chương liên quan: Chương 6 (6.2. Phát hiện và vá lỗ hổng; 6.1. Mục tiêu bảo vệ).

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

**Ánh xạ đề cương:** Chương chính: Chương 4 --- Tích hợp và triển khai liên tục (4.1. Tích hợp liên tục (CI); 4.2. Thiết lập và cấu hình CI; 4.3. Phát triển và kiểm thử tự động; 4.4. Quy trình triển khai). Chương liên quan: Chương 6 (6.4. DevSecOps).

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

**Ánh xạ đề cương:** Chương chính: Chương 3 --- Container và điện toán đám mây (3.1. Kiến thức cơ bản về Docker; 3.3. Máy ảo và container). Chương liên quan: Chương 2 (2.1. Nguyên tắc; 2.2. Thực tiễn đảm bảo an toàn).

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

**Ánh xạ đề cương:** Chương chính: Chương 3 --- Container và điện toán đám mây (3.1. Kiến thức cơ bản về Docker/container). Chương liên quan: Chương 5 (5.3. Kiến trúc vi dịch vụ); Chương 6 (6.3. Xác thực và ủy quyền; 6.4. DevSecOps).
