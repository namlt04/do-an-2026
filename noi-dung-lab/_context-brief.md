# BRIEF DÙNG CHUNG — Thiết kế nội dung 10 bài Lab DevSecOps/Cloud cho Labtainer

> Đây là tài liệu bối cảnh cho các subagent thiết kế nội dung lab. ĐỌC KỸ TRƯỚC KHI VIẾT.
> Nhiệm vụ của bạn: **chỉ viết NỘI DUNG (đề bài + hướng dẫn) để duyệt**, CHƯA cài đặt/build lab thật.

---

## 1. Bối cảnh đồ án

- Ngành: An toàn thông tin (Học viện Công nghệ BCVT — PTIT / SecLab PTIT).
- Đề tài: Thiết kế bài lab cho nền tảng **Labtainer** (https://nps.edu/web/c3o/labtainers).
- Định hướng: **Cloud, DevOps, DevSecOps**.
- **Trọng tâm BẢO MẬT (security) ~60%, thiết lập môi trường (DevOps/Cloud) ~40%.** Vẫn phải dựng môi trường thật nhưng phần nổi bật, được chấm điểm và đặt câu hỏi phải là an toàn thông tin.
- **10 bài lab ĐỘC LẬP**: mỗi bài tự chứa, KHÔNG được giả định sinh viên đã làm bài khác trước đó. Không có chuỗi tiên quyết. Kiến thức nền cần thiết phải được nhắc lại trong mục "Kiến thức bổ trợ" của chính bài đó.

## 2. Ràng buộc kỹ thuật của Labtainer (RẤT QUAN TRỌNG khi thiết kế)

Labtainer là framework lab an toàn thông tin chạy **cục bộ, offline**, dựa trên **Docker** (mỗi "máy tính" là 1 container Linux), trên 1 máy ảo Labtainer.

Hệ quả cho thiết kế:
- **KHÔNG có cloud thật** (không AWS/Azure/GCP thật). Mọi thứ "cloud" phải được **mô phỏng cục bộ** bằng container:
  - S3/object storage → **MinIO** (tương thích S3) hoặc HTTP server giả.
  - Cloud metadata/IMDS (169.254.169.254) → một **HTTP server giả** đóng vai IMDS, trả về credential giả.
  - "Cloud credentials" → khóa/API token giả do lab sinh ra.
- Nhiều container nối với nhau qua **mạng ảo Labtainer** (khai báo trong `start.config`), mỗi container có IP tĩnh (ví dụ dải `172.x.x.x`). Thường có 1 container `client`/`attacker` (nơi sinh viên gõ lệnh) và 1..n container dịch vụ (`server`, `registry`, `ci`, `k8s`...).
- **Chấm điểm tự động** dựa trên *artifacts* (stdin/stdout, file output, bash history, log hệ thống) và *goals* (so khớp chuỗi/giá trị, thường là chuỗi **flag** hoặc kết quả lệnh). Vì vậy MỖI nhiệm vụ nên có **"Điều kiện hoàn thành nhiệm vụ"** đo lường được (ví dụ: lấy được flag, tạo được file kết quả, chạy được lệnh cho output cụ thể).
- Công cụ cài trong container qua **Dockerfile** (apt/pip...). Nên chọn công cụ **cài đặt được offline/nhẹ**, tránh thứ quá nặng cho 1 VM. Với Kubernetes ưu tiên bản nhẹ (k3s/kind 1 node) hoặc **audit tĩnh manifest** thay vì cụm lớn; nếu nặng thì GHI CHÚ rõ đây là điểm cần cân nhắc khi triển khai.
- Có hỗ trợ **quiz** (đúng/sai, câu hỏi) và tham số hóa lab (mỗi sinh viên 1 flag khác nhau).
- Phân phối bài qua lệnh `imodule <url>.tar` rồi khởi động bằng `labtainer <ten-lab>`.

## 3. Cấu trúc/template chuẩn của một bài lab SecLab PTIT

Xem file mẫu `_ref-sample-lab-t1057.txt` (bài atk-mitre-t1057) để nắm giọng văn và format. Nội dung bạn viết PHẢI theo đúng bố cục sau (tiếng Việt, xưng "sinh viên"):

**Tiêu đề + badge**: Tên bài, Mức độ (Cơ bản/Trung bình/Nâng cao), nhãn phân loại (ví dụ: Cloud Security / DevSecOps / Container).

**1. Giới thiệu lab** — bảng thông tin:
- Tên Lab (mã lab, ví dụ `dso-docker-escape`)
- Mức độ
- Công cụ sử dụng (liệt kê công cụ chính)
- Kiến thức yêu cầu (nền tảng tối thiểu, vì bài độc lập nên ghi rõ)
- **Mục tiêu học tập** (3–5 gạch đầu dòng)
- **Kỹ năng đạt được** (3–5 gạch đầu dòng, thiên về kỹ năng bảo mật)

**2. Kịch bản**
- Tình huống (câu chuyện thực tế: sinh viên đóng vai ai — attacker/pentester/DevSecOps engineer — mục tiêu là gì)
- Vai trò của sinh viên (các việc chính phải làm)
- **Sơ đồ mạng** (mô tả text các container, IP, dịch vụ, luồng tấn công/phòng thủ)

**3. Kiến thức bổ trợ**
- Kiến thức nền tảng (giải thích các khái niệm cốt lõi: khái niệm bảo mật + khái niệm DevOps/Cloud liên quan; nhắc lại đủ để bài độc lập)
- Bảng "Thành phần cần quan sát trong bài lab" (component | vai trò)
- **Bảng công cụ & cú pháp** (Công cụ | Tùy chọn/Cú pháp | Mô tả tác dụng) — rất quan trọng, liệt kê lệnh chính sẽ dùng

**4. Các nhiệm vụ của bài thực hành**
- Câu mở đầu về `imodule ...` và `labtainer <ten-lab>` (dùng placeholder URL: `https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/<ten-lab>.tar`)
- Ghi chú nhập mã sinh viên khi được hỏi (dùng để chấm điểm)
- Các **Nhiệm vụ 1..N** (đặt tên goal ngắn kiểu `scan_network`, `exploit_x`, `get_flag`, `harden_x`), mỗi nhiệm vụ gồm:
  - Mô tả mục tiêu nhiệm vụ
  - Các **Bước** cụ thể kèm lệnh (dùng placeholder `<...>` khi cần sinh viên tự điền)
  - **Điều kiện hoàn thành nhiệm vụ** (đo lường được — sẽ dùng để chấm tự động)
  - **Câu hỏi** (1 câu hỏi tư duy/bảo mật cho mỗi nhiệm vụ, có dòng "Trả lời: ____")

**Yêu cầu về tỷ lệ 60/40**: Trong các nhiệm vụ, phần liên quan trực tiếp đến bảo mật (khai thác, phát hiện lỗ hổng, phân tích rủi ro, HARDENING/khắc phục) phải chiếm ưu thế. Nên có **ít nhất 1 nhiệm vụ "phòng thủ/khắc phục" (hardening/remediation)** để thể hiện tư duy DevSecOps chứ không chỉ tấn công.

## 4. Ánh xạ khung tham chiếu (thêm chiều sâu học thuật)

Khi phù hợp, ghi chú ánh xạ tới các khung: **MITRE ATT&CK** (đặc biệt ATT&CK for Containers/Cloud), **OWASP** (Top 10, DevSecOps Guideline), **CIS Benchmarks** (Docker/Kubernetes). Không bắt buộc mọi bài, chỉ khi tự nhiên.

## 5. Tài liệu tham khảo có sẵn (đọc nếu cần)
- `_ref-labtainer-designer.txt` — trích Labtainer Lab Designer Guide (khả năng & giới hạn framework).
- `_ref-devops-syllabus.txt` — đề cương môn Nhập môn DevOps (phạm vi kiến thức của sinh viên).
- `_ref-sample-lab-t1057.txt` — bài lab mẫu chuẩn format PTIT.
- Repo tham khảo (bối cảnh, không bắt buộc truy cập mạng):
  Cloud roadmap; iam-veeramalla: aws-devops / Docker / Jenkins / Kubernetes zero-to-hero;
  OWASP DevSecOps-Guideline; OWASP coreruleset (CRS cho WAF).

## 6. Định dạng đầu ra
- Viết bằng **tiếng Việt**, giọng kỹ thuật, rõ ràng, đúng template mục 3.
- Xuất ra **Markdown** hợp lệ (dùng bảng markdown, code block ```bash, tiêu đề ##).
- Lệnh cụ thể, khả thi trong Labtainer (offline, mô phỏng cục bộ).
- CHƯA cần viết Dockerfile/start.config/mã chấm điểm — chỉ nội dung đề bài & hướng dẫn để duyệt. Có thể thêm cuối bài một mục ngắn **"Ghi chú triển khai (cho người xây lab)"**: liệt kê container cần dựng, dịch vụ, flag/goal dự kiến, điểm cần lưu ý về tài nguyên.
