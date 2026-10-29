# BUILD NOTES — dso-image-scan

Lab có `workstation` (terminal sinh viên, Docker daemon, image mẫu) và `vault-svc` (không terminal). API key/flag dùng `HASH_REPLACE`; không dùng giá trị tĩnh. Khi build VM, cần kiểm tra Docker daemon hoạt động trong workstation và Trivy có cache DB trước khi chạy offline scan. Solver phải PASS toàn bộ goal, còn lab chưa làm phải FAIL.
