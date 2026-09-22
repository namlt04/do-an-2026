# THIẾT KẾ LẠI KỊCH BẢN — 10 Lab theo lộ trình Cơ bản → Chuyên sâu (bản đề xuất để duyệt)

> **Thay đổi so với bản cũ:** giữ nguyên 10 chủ đề, nhưng (1) **sắp xếp lại theo độ khó tăng dần**, (2) **gắn kết thành một cốt truyện kill-chain xuyên suốt** trên cùng một hệ thống doanh nghiệp giả định, và (3) bổ sung **đánh giá độ khả thi** khi triển khai trên Labtainer.
> **Trạng thái:** đây là *bản đề xuất* — chưa chỉnh sửa các file `01`–`10`. Sau khi bạn duyệt, tôi sẽ áp dụng (viết lại phần Kịch bản + đổi số thứ tự + xuất Word).

---

## 0. Nguyên tắc thiết kế & cách dung hòa "độc lập" với "cốt truyện"

Yêu cầu ban đầu: 10 bài **độc lập** (không bắt buộc làm bài trước mới làm được bài sau). Yêu cầu mới: **liên kết chặt theo cốt truyện**. Hai điều này được dung hòa bằng nguyên tắc **"độc lập kỹ thuật – liên tục tường thuật"**:

- **Về kỹ thuật:** mỗi bài vẫn **tự chứa** — chiến lợi phẩm/thông tin mà cốt truyện nói là "lấy từ bài trước" đều được **cấp sẵn (pre-seed)** ngay đầu bài (trong file đề bài, biến môi trường, hoặc container khởi tạo). Sinh viên KHÔNG cần hoàn thành bài trước.
- **Về tường thuật:** các bài cùng diễn ra trên hệ thống của một công ty giả định, và chiến lợi phẩm của bài N chính là điểm khởi đầu (đã được cấp sẵn) của bài N+1 → tạo cảm giác một chiến dịch tấn công – phòng thủ liền mạch, đi từ ngoài vào trong, từ nông đến sâu.
- **Trục sắp xếp chính là ĐỘ KHÓ.** Cốt truyện được thiết kế để trùng khớp với chiều tăng độ khó (phân tích tĩnh → 1 container → nhiều container → mô phỏng cloud → orchestration).
- Giữ tỷ lệ **bảo mật ~60% / môi trường ~40%** và mỗi bài vẫn có **nhiệm vụ hardening/remediation**.

---

## 1. Bối cảnh cốt truyện chung: Công ty **CloudNova**

**CloudNova** là một startup fintech/thương mại điện tử vận hành nền tảng *cloud-native* (container hóa, CI/CD, hạ tầng mô tả bằng code, chạy trên Kubernetes). Sinh viên tham gia một **chiến dịch đánh giá an ninh (red team + blue team)** kéo dài, đi từ bề mặt ngoài cùng (mã hạ tầng bị lộ) tiến dần vào lõi hệ thống (cụm Kubernetes production). Ở **mỗi chặng**, sinh viên vừa **khai thác** (mũ đỏ) vừa **vá lỗi** (mũ xanh – DevSecOps).

**Mô-típ xuyên suốt — "credential sprawl":** cùng một bộ khóa/định danh của tài khoản cloud CloudNova liên tục rò rỉ ở nhiều tầng (mã IaC, image, git, cloud storage, metadata). Đây là sợi chỉ đỏ nối các bài và cũng là bài học lớn nhất của cả chuỗi.

### Bảng lộ trình mới

| Thứ tự mới | (Cũ) | Mã lab | Chủ đề | Độ khó | Giai đoạn kill-chain | Khả thi |
|:---:|:---:|---|---|:---:|---|:---:|
| 1 | (9) | `dso-iac-scan` | Bảo mật IaC (shift-left) | ★☆☆☆☆☆☆☆☆ | Trinh sát: mã hạ tầng lộ | Rất cao |
| 2 | (2) | `dso-image-scan` | Bảo mật image container | ★★☆☆☆☆☆☆☆ | Thu thập: image nội bộ | Cao |
| 3 | (5) | `dso-secrets-git` | Bí mật trong Git history | ★★★☆☆☆☆☆☆ | Thu thập: mã nguồn | Cao |
| 4 | (4) | `dso-supplychain-sca` | SCA & SBOM (chuỗi cung ứng) | ★★★★☆☆☆☆☆ | Chiếm chỗ đứng: app | Trung bình–Cao |
| 5 | (6) | `cloud-s3-misconfig` | Object storage cấu hình sai | ★★★★☆☆☆☆☆ | Rò rỉ dữ liệu cloud | Cao |
| 6 | (10) | `dso-waf-crs` | WAF runtime (ModSecurity+CRS) | ★★★★★☆☆☆☆ | Vận hành: bảo vệ app | Trung bình |
| 7 | (7) | `cloud-ssrf-imds` | SSRF → cloud metadata | ★★★★★★☆☆☆ | Leo thang vào cloud | Trung bình–Cao |
| 8 | (3) | `dso-cicd-jenkins` | Bảo mật CI/CD (Jenkins) | ★★★★★★★☆☆ | Chiếm pipeline | Trung bình |
| 9 | (1) | `dso-docker-escape` | Thoát container chiếm host | ★★★★★★★★☆ | Thoát ra host | Trung bình–Thấp |
| 10 | (8) | `cloud-k8s-rbac` | Bảo mật Kubernetes (RBAC) | ★★★★★★★★★ | Chiếm toàn cụm (đỉnh) | Thấp–Trung bình |

**Phân bố độ khó:** Cơ bản (1–2) · Trung bình (3–5) · Trung bình khá (6) · Nâng cao (7–9) · Chuyên sâu (10).

---

## 2. Sơ đồ kill-chain nối 10 bài

```
                       CHIẾN DỊCH ĐÁNH GIÁ AN NINH HỆ THỐNG CLOUDNOVA
                        (đi từ ngoài vào trong, từ nông đến sâu)

[1] IaC repo lộ ──► [2] Image registry ──► [3] Git source ──► [4] App đang chạy
   (tfsec/checkov)     (docker history/Trivy)   (gitleaks)        (SCA + khai thác CVE)
   phát hiện kiến      lộ API key + CVE         lộ AWS key/DB      chiếm shell trên
   trúc + secret       → truy cập vault-svc     pass/token         appserver
        │                     │                      │                   │
        └─── cùng bộ credential cloud CloudNova (mô-típ "credential sprawl") ───┐
                                                                                ▼
[5] Cloud storage (MinIO/S3) ◄──────────────────────────────── dùng credential lộ
   bucket public → exfiltrate backup → lộ thêm key → bucket private (dữ liệu mật)
        │
        ▼
[6] Storefront web app đưa ra sau WAF  ──►  [7] Chính app đó dính SSRF
   (ModSecurity+CRS chặn SQLi/XSS)            fetch URL → IMDS giả (169.254.169.254)
                                              → cắp credential role tạm thời → cloud
        │                                             │
        ▼                                             ▼
[8] Jenkins CI/CD  ──►  RCE + trộm credential deploy  ──►  pivot Docker Registry (bài 2)
   (attacker giờ có thể đầu độc build)
        │
        ▼
[9] Container bị chiếm  ──►  escape ra HOST (docker.sock/privileged)
        │
        ▼
[10] HOST là 1 node trong cụm Kubernetes  ──►  lạm quyền RBAC + secret + pod escape
     ──►  CHIẾM TOÀN BỘ CỤM (đỉnh của chuỗi)
```

Mỗi mũi tên "──►" là điểm bàn giao chiến lợi phẩm; trong triển khai, chiến lợi phẩm đó được **cấp sẵn** ở bài nhận để đảm bảo tính độc lập.

---

## 3. Kịch bản mới từng bài

> Mỗi bài nêu: **Bối cảnh** (trong cốt truyện), **Đầu vào** (chiến lợi phẩm nhận — đã pre-seed), **Bàn giao** (mở đường cho bài sau), **Độ khó**, và **Đánh giá khả thi + rủi ro/giảm thiểu**.

### Bài 1 — `dso-iac-scan` · Điểm khởi đầu chiến dịch  ★ (Cơ bản)
- **Bối cảnh:** Một lập trình viên CloudNova vô tình đẩy toàn bộ repo Terraform lên GitHub công khai. Sinh viên (DevSecOps của đội đánh giá) tiếp nhận repo này để rà soát cấu hình hạ tầng trước khi nó bị khai thác.
- **Đầu vào (pre-seed):** repo Terraform của CloudNova (đặt sẵn trong container).
- **Bàn giao:** mã lộ ra kiến trúc hệ thống + **tên container registry nội bộ** và **mẫu đặt tên bucket/khóa IAM** → gợi mở Bài 2 và Bài 5.
- **Vì sao đặt đầu tiên:** thuần **phân tích tĩnh, không khai thác, 1 container**, thiên phòng thủ — làm quen tư duy "shift-left" nhẹ nhàng nhất.
- **Khả thi: RẤT CAO.** Chạy hoàn toàn offline trong 1 container. *Rủi ro:* cần tải sẵn rule DB của tfsec/checkov/trivy vào image. *Giảm thiểu:* đóng gói DB khi build image (không cần mạng lúc chạy).

### Bài 2 — `dso-image-scan` · Soi image nội bộ  ★★ (Cơ bản+)
- **Bối cảnh:** Từ tên registry lộ ở Bài 1, sinh viên lấy được một image ứng dụng của CloudNova và phân tích nó.
- **Đầu vào (pre-seed):** file image (dạng `.tar`) đặt sẵn trong container workstation.
- **Bàn giao:** trong layer có **API key** dùng cho `vault-svc`, và dấu vết trỏ tới **repo mã nguồn** của CloudNova → gợi mở Bài 3.
- **Độ khó tăng nhẹ:** thêm thao tác khai thác (giải nén layer, dùng key gọi dịch vụ) so với Bài 1 nhưng vẫn gói gọn quanh 1 workstation.
- **Khả thi: CAO.** *Rủi ro:* nếu yêu cầu Docker daemon trong container (DinD) sẽ nặng. *Giảm thiểu:* dùng image `.tar` + `trivy image --input file.tar` và `tar` để bóc layer — **không cần Docker daemon**; chỉ cần thêm `vault-svc` là 1 container HTTP nhẹ.

### Bài 3 — `dso-secrets-git` · Đào bí mật trong mã nguồn  ★★★ (Trung bình)
- **Bối cảnh:** Truy được repo mã nguồn CloudNova (từ Bài 2). Secret từng bị commit rồi "xóa" nhưng vẫn nằm trong lịch sử Git.
- **Đầu vào (pre-seed):** bản clone repo có lịch sử commit dàn dựng sẵn.
- **Bàn giao:** lộ **AWS-style access key + secret key**, DB password, API token — chính là bộ credential mở khóa **cloud storage** ở Bài 5 (mô-típ credential sprawl).
- **Khả thi: CAO.** git + gitleaks/trufflehog (binary offline), 2–3 container nhẹ. *Rủi ro thấp.* *Giảm thiểu:* đóng gói sẵn nhị phân công cụ; dịch vụ đích dùng lại `vault-svc`/MinIO nhẹ.

### Bài 4 — `dso-supplychain-sca` · Chiếm chỗ đứng qua phụ thuộc  ★★★★ (Trung bình)
- **Bối cảnh:** Có mã nguồn (Bài 3), sinh viên phân tích chuỗi cung ứng và nhận ra app CloudNova dùng một thư viện có CVE nghiêm trọng — rồi khai thác chính app đang chạy để chứng minh hậu quả.
- **Đầu vào (pre-seed):** mã nguồn + `appserver` đang chạy phiên bản dễ tổn thương.
- **Bàn giao:** có **shell/khả năng thực thi trên appserver** — bàn đạp để tiến vào tầng cloud (Bài 5) và về sau là container/host (Bài 9).
- **Khả thi: TRUNG BÌNH–CAO.** *Rủi ro:* cần một CVE **tái lập được offline** và ổn định. *Giảm thiểu:* **chốt 1 CVE cụ thể** (ví dụ một CVE Node.js hoặc Python cho RCE/deserialization), cài sẵn `node_modules`/venv trong image, không phụ thuộc mạng. → *đây là điểm cần bạn quyết ở mục 5.*

### Bài 5 — `cloud-s3-misconfig` · Rò rỉ dữ liệu cloud  ★★★★ (Trung bình)
- **Bối cảnh:** Dùng bộ khóa cloud lộ (từ Bài 3) và tên bucket suy ra (từ Bài 1), sinh viên truy cập object storage của CloudNova (mô phỏng bằng MinIO). Một bucket để chế độ ẩn danh.
- **Đầu vào (pre-seed):** endpoint MinIO + (tùy chọn) credential lộ; bucket dàn dựng sẵn.
- **Bàn giao:** exfiltrate được backup, lộ thêm credential → truy cập bucket private chứa dữ liệu mật; xác nhận cloud account đã bị xâm phạm → nối sang chuỗi cloud sâu hơn (Bài 7).
- **Khả thi: CAO.** MinIO + aws-cli/mc chạy tốt offline, 2 container. *Rủi ro thấp.*

### Bài 6 — `dso-waf-crs` · Vận hành: dựng lá chắn runtime  ★★★★★ (Trung bình khá)
- **Bối cảnh:** CloudNova phát hiện storefront web bị dò quét, giao sinh viên (DevSecOps) đưa app ra sau WAF. Sinh viên trước hết khai thác trực tiếp (SQLi/XSS/traversal) để thấy lỗ hổng thật, rồi dựng ModSecurity + OWASP CRS chặn lại, chạy DAST đối chiếu và xử lý false positive.
- **Đầu vào (pre-seed):** storefront web app có lỗ hổng + reverse proxy chưa bật WAF.
- **Bàn giao:** đây **chính là web app** sẽ bị khai thác SSRF ở Bài 7 (cùng một ứng dụng, đào sâu hơn ở tầng logic).
- **Độ khó tăng:** lần đầu phải **dựng nhiều container + build module WAF**, tư duy cả tấn công lẫn vận hành.
- **Khả thi: TRUNG BÌNH.** *Rủi ro:* build ModSecurity v3 + CRS hơi nặng; OWASP ZAP (JVM) tốn RAM. *Giảm thiểu:* dùng gói nginx + libmodsecurity offline; **ưu tiên `nikto`/`curl` cho DAST**, để ZAP là tùy chọn.

### Bài 7 — `cloud-ssrf-imds` · Leo thang từ app vào cloud  ★★★★★★ (Nâng cao)
- **Bối cảnh:** Chính storefront ở Bài 6 có chức năng "xem trước ảnh theo URL" dính SSRF. Sinh viên ép app gọi tới dịch vụ metadata (IMDS giả) để cắp credential role tạm thời, rồi dùng nó truy cập cloud — tái hiện sự cố Capital One 2019.
- **Đầu vào (pre-seed):** web app có SSRF + `imds` giả + `storage` đích.
- **Bàn giao:** credential/role cloud + hiểu biết mạng nội bộ → hỗ trợ tiếp cận hạ tầng CI/CD (Bài 8).
- **Khả thi: TRUNG BÌNH–CAO.** Mọi thành phần mock được, container nhẹ. *Rủi ro:* alias địa chỉ link-local `169.254.169.254` trong mạng Labtainer cần kiểm chứng. *Giảm thiểu:* nếu không gán được IP link-local, dùng DNS name `imds` nội bộ và nêu rõ vai trò mô phỏng.

### Bài 8 — `dso-cicd-jenkins` · Chiếm dây chuyền phát hành  ★★★★★★★ (Nâng cao)
- **Bối cảnh:** Có chỗ đứng trong mạng nội bộ, sinh viên phát hiện Jenkins của CloudNova cấu hình lỏng: truy cập ẩn danh → RCE qua Script Console → trộm credential deploy → pivot sang **Docker Registry** (đúng registry ở Bài 2). Chiếm được CI nghĩa là có thể đầu độc mọi bản build.
- **Đầu vào (pre-seed):** Jenkins dễ tổn thương + registry đích.
- **Bàn giao:** credential deploy + chỗ đứng trên một **container build** → bàn đạp cho Bài 9.
- **Khả thi: TRUNG BÌNH.** *Rủi ro:* Jenkins thật ngốn RAM (JVM). *Giảm thiểu:* cung cấp **2 phương án** — (A) Jenkins thật (cần cấp RAM) hoặc (B) mock các endpoint dễ tổn thương bằng Flask (nhẹ, khả thi cao). → *cần bạn chốt phương án mặc định ở mục 5.*

### Bài 9 — `dso-docker-escape` · Thoát khỏi container  ★★★★★★★★ (Nâng cao)
- **Bối cảnh:** Trên một container build/app bị chiếm (từ Bài 4 hoặc 8), sinh viên nhận ra nó cấu hình sai (`--privileged` / mount `docker.sock` / thừa capability) và thoát ra chiếm quyền host.
- **Đầu vào (pre-seed):** container mục tiêu cấu hình yếu + host mô phỏng.
- **Bàn giao:** quyền trên **host** — mà host này là một **node Kubernetes** → dẫn thẳng vào Bài 10.
- **Khả thi: TRUNG BÌNH–THẤP.** *Rủi ro lớn nhất của cả bộ:* chạy **nested privileged / mount docker.sock bên trong** container Labtainer phụ thuộc vào lớp Docker của VM — cần **kiểm thử thực tế**. *Giảm thiểu:* mô phỏng host bằng container `host-sim` chia sẻ socket; nếu privileged không ổn định thì tập trung đường **docker.sock** (ổn định hơn) và để đường privileged là tùy chọn.

### Bài 10 — `cloud-k8s-rbac` · Chiếm toàn bộ cụm (đỉnh)  ★★★★★★★★★ (Chuyên sâu)
- **Bối cảnh:** Host chiếm được ở Bài 9 là một node trong cụm Kubernetes production của CloudNova. Từ chỗ đứng trong một pod, sinh viên lạm quyền RBAC quá rộng, đọc secret, tạo pod hostPath/privileged để thoát ra node — hoàn tất việc chiếm toàn bộ nền tảng.
- **Đầu vào (pre-seed):** chỗ đứng trong pod + cấu hình cụm dàn dựng.
- **Bàn giao:** đỉnh của chuỗi — tổng kết toàn bộ bài học credential sprawl + phòng thủ theo chiều sâu.
- **Khả thi: THẤP–TRUNG BÌNH.** *Rủi ro:* K8s trong 1 VM nặng RAM/CPU. *Giảm thiểu:* **2 phương án** — (A) k3s 1 node (thật, cần tài nguyên) hoặc (B) audit tĩnh manifest (kube-linter/kubesec/kube-bench) + API mock (nhẹ, giảm tính "thật"). → *cần bạn chốt ở mục 5.*

---

## 4. Sơ lược thay đổi TRƯỚC → SAU

| Bài (mới) | Cũ# | Thay đổi thứ tự | Kịch bản CŨ (rời rạc) | Kịch bản MỚI (trong cốt truyện) |
|:---:|:---:|---|---|---|
| 1 `dso-iac-scan` | 9 | 9 → 1 (lên đầu) | DevSecOps engineer nhận một bộ Terraform bất kỳ để quét | Mở màn chiến dịch: repo IaC của **CloudNova bị lộ công khai**; kết quả rà soát lộ registry + mẫu khóa cho các bài sau |
| 2 `dso-image-scan` | 2 | 2 → 2 (giữ) | Phân tích "một image nội bộ" chung chung | Lấy image **từ registry lộ ở Bài 1**; API key trong layer trỏ tới mã nguồn (Bài 3) |
| 3 `dso-secrets-git` | 5 | 5 → 3 | Có "một Git repo nội bộ" để đào secret | Đào repo **CloudNova truy từ Bài 2**; khóa AWS lộ chính là chìa cho cloud storage (Bài 5) |
| 4 `dso-supplychain-sca` | 4 | 4 → 4 (giữ) | Ứng dụng web "ví dụ" có phụ thuộc lỗi | Khai thác phụ thuộc trên **app CloudNova (mã từ Bài 3)** để có shell — bàn đạp vào cloud/host |
| 5 `cloud-s3-misconfig` | 6 | 6 → 5 | Phát hiện "một endpoint MinIO" ẩn danh | Dùng **khóa lộ (Bài 3) + tên bucket (Bài 1)** truy cập storage CloudNova; xác nhận cloud bị xâm phạm |
| 6 `dso-waf-crs` | 10 | 10 → 6 | Bảo vệ "một web app có lỗ hổng" | Bảo vệ **storefront CloudNova**; đây là app sẽ bị SSRF ở Bài 7 |
| 7 `cloud-ssrf-imds` | 7 | 7 → 7 (giữ) | App "fetch URL" bất kỳ dính SSRF | **Chính storefront Bài 6** dính SSRF → cắp role cloud → mở đường tới CI (Bài 8) |
| 8 `dso-cicd-jenkins` | 3 | 3 → 8 | Phát hiện "một Jenkins nội bộ" | Từ chỗ đứng mạng, chiếm Jenkins CloudNova, **pivot về đúng registry ở Bài 2** |
| 9 `dso-docker-escape` | 1 | 1 → 9 | Attacker "đã có shell trong một container" | Container build/app bị chiếm **từ Bài 4/8**; escape ra host — mà host là node K8s (Bài 10) |
| 10 `cloud-k8s-rbac` | 8 | 8 → 10 (lên đỉnh) | Attacker "đã có quyền trong một pod" | **Host Bài 9 là node của cụm**; chiếm toàn bộ nền tảng CloudNova — cao trào |

**Bản chất thay đổi:** chủ đề, công cụ, nhiệm vụ kỹ thuật của từng bài **không đổi**; phần thay đổi là (a) **thứ tự** theo độ khó, (b) **khung tường thuật** — từ các tình huống rời rạc gộp thành một chiến dịch liền mạch trên hệ thống CloudNova, và (c) **các móc nối chiến lợi phẩm** giữa các bài (đều được pre-seed để giữ tính độc lập).

---

## 5. Đánh giá độ khả thi tổng thể & các điểm cần chốt

**Tổng quan:** 8/10 bài **khả thi cao đến trung bình** và chạy offline gọn trong Labtainer. 2 bài cuối (9, 10) — đúng theo tính chất "đỉnh" của chuỗi — là **rủi ro triển khai cao nhất** và cần quyết định/kiểm thử. Đây là đánh đổi hợp lý: độ khó tăng thì độ phức tạp hạ tầng cũng tăng.

| Nhóm | Bài | Kết luận khả thi |
|---|---|---|
| Chạy ngay, rủi ro thấp | 1, 3, 5, 2 | Offline, container nhẹ; chỉ cần đóng gói sẵn công cụ/DB |
| Khả thi, cần chốt chi tiết | 4, 6, 7 | Cần: chốt CVE (4), ưu tiên nikto thay ZAP (6), kiểm chứng alias IMDS (7) |
| Cần quyết định phương án / kiểm thử | 8, 9, 10 | Jenkins thật vs mock (8); nested-privileged (9); k3s vs audit tĩnh (10) |

**Quyết định đã chốt (cập nhật):**
1. ✅ **Bài 4 (SCA):** dùng hệ sinh thái **Node.js (npm)** — sẽ chốt 1 CVE npm tái lập được offline (ứng viên: prototype pollution / deserialization / RCE), cài sẵn `node_modules`, ghi rõ CVE trong tài liệu.
2. ✅ **Bài 8 (Jenkins):** mặc định **mock Flask** các endpoint dễ tổn thương (nhẹ, khả thi cao); vẫn giữ mô tả phương án Jenkins thật như tùy chọn nâng cao.
3. ✅ **Bài 10 (K8s):** mặc định **k3s 1 node (thật)** — kubectl/RBAC/pod escape thật; kéo theo yêu cầu tài nguyên (xem mục 5.4).

**Còn lại (đề xuất mặc định, bạn chỉ cần xác nhận khi áp dụng):**
4. **Bài 9:** đề xuất lấy đường **docker.sock** làm chính (ổn định trong Labtainer), để **privileged/CAP_SYS_ADMIN** là đường tùy chọn — do nested-privileged phụ thuộc lớp Docker của VM.
5. **Tài nguyên VM Labtainer:** vì đã chọn **k3s thật (Bài 10)**, máy chấm cần cấp đủ RAM/CPU (khuyến nghị ≥ 4 GB RAM, 2 vCPU cho bài này). Các bài còn lại nhẹ. Cần xác nhận cấu hình máy chấm để tôi ghi ngưỡng tài nguyên vào "Ghi chú triển khai" của Bài 10.

---

## 6. Bước tiếp theo (sau khi bạn duyệt)

Khi bạn đồng ý phương án này, tôi sẽ:
1. Viết lại **mục "2. Kịch bản"** (Tình huống, Vai trò, Sơ đồ mạng) + cập nhật **Mức độ** trong từng file `01`–`10` theo cốt truyện CloudNova và thứ tự mới.
2. **Đổi số thứ tự file** theo lộ trình mới (1→10) và cập nhật bảng tổng quan `00-TONG-QUAN-10-LAB.md`.
3. Bổ sung vào mỗi bài dòng **"Đầu vào / Bàn giao"** (nêu rõ phần pre-seed) để vẫn giữ tính độc lập.
4. Xuất lại bản **Word** cho tài liệu tổng quan.
