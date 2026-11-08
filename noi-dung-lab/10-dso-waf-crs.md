# HƯỚNG DẪN THỰC HÀNH — Bảo vệ ứng dụng runtime với WAF ModSecurity + OWASP CRS

> Học viện Công nghệ Bưu chính Viễn thông — SecLab PTIT
> **Mức độ:** Nâng cao  |  **Phân loại:** DevSecOps / Application Security / Runtime Protection
> **Ánh xạ khung:** OWASP Top 10 (A03 Injection, A05 Security Misconfiguration) · OWASP Core Rule Set (CRS) · OWASP DevSecOps Guideline (Runtime Protection / Dynamic Testing)

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `dso-waf-crs` |
| **Mức độ** | Nâng cao |
| **Công cụ sử dụng** | `curl`, `nginx` (reverse proxy) + **ModSecurity v3** (libmodsecurity + connector) + **OWASP CRS**, `nikto` và/hoặc **OWASP ZAP** (baseline scan), `tail`/`grep` trên audit log ModSecurity |
| **Kiến thức yêu cầu** | Cơ bản về HTTP request/response và mã trạng thái (200/403/500); khái niệm lỗ hổng web phổ biến (SQLi, XSS, path traversal); dòng lệnh Linux; hiểu sơ lược reverse proxy. Bài **độc lập**, mọi khái niệm cốt lõi được nhắc lại ở mục 3. |
| **Mục tiêu học tập** | - Hiểu vai trò của **WAF** như lớp phòng thủ runtime bổ sung (defense-in-depth), KHÔNG thay thế việc vá code. <br> - Nắm cơ chế **ModSecurity + OWASP CRS**: rule, anomaly scoring, paranoia level, chế độ Detection vs Blocking. <br> - Biết đặt reverse proxy có WAF trước một ứng dụng web lỗ hổng và kiểm chứng khả năng chặn tấn công. <br> - Biết dùng **DAST** (nikto/ZAP baseline) để đánh giá khách quan hiệu quả trước/sau khi bật WAF. <br> - Hiểu và xử lý được **false positive**: viết rule exclusion để cân bằng an toàn vs khả dụng. |
| **Kỹ năng đạt được** | - Kỹ năng khai thác thực tế các lỗ hổng SQLi / XSS / path traversal bằng `curl` để chứng minh rủi ro. <br> - Kỹ năng triển khai và cấu hình ModSecurity v3 + OWASP CRS trên nginx reverse proxy (chuyển từ `DetectionOnly` sang `On`). <br> - Kỹ năng đọc và phân tích **audit log** ModSecurity để xác định rule nào khớp (rule ID, anomaly score). <br> - Kỹ năng chạy và diễn giải kết quả **DAST** so sánh trạng thái có/không WAF. <br> - Kỹ năng viết **rule exclusion** (SecRuleRemoveById / ctl:ruleRemoveTargetById) đúng phạm vi để khử false positive mà không mở lại lỗ hổng. |

---

## 2. Kịch bản

**Tình huống:**
Công ty đang vận hành một ứng dụng web nội bộ (`webapp`) còn tồn tại nhiều lỗ hổng nghiêm trọng (SQL Injection, Reflected XSS, Path Traversal). Đội phát triển chưa thể vá code ngay trong sprint hiện tại vì phụ thuộc bên thứ ba. Ban lãnh đạo yêu cầu bộ phận DevSecOps **giảm rủi ro ngay lập tức** bằng cách đặt một lớp phòng thủ runtime trước ứng dụng, đồng thời chứng minh bằng số liệu rằng lớp phòng thủ này thực sự chặn được tấn công mà không làm hỏng chức năng hợp lệ của người dùng.

Sinh viên đóng vai **DevSecOps engineer**. Trước hết phải tự mình khai thác ứng dụng để hiểu rủi ro thật (lấy flag chứng minh lỗ hổng). Sau đó triển khai **WAF ModSecurity + OWASP CRS** trên một reverse proxy `nginx` đặt trước `webapp`, bật chế độ chặn, kiểm chứng các payload cũ giờ bị chặn (HTTP 403). Tiếp theo dùng **DAST** để so sánh khách quan trước/sau WAF. Cuối cùng, một chức năng hợp lệ của ứng dụng bị CRS chặn nhầm (false positive) — sinh viên phải viết **rule exclusion** đúng phạm vi để khôi phục chức năng đó mà vẫn giữ nguyên khả năng chặn tấn công.

**Vai trò của sinh viên (trên container `client`):**
1. Tấn công `webapp` khi CHƯA có WAF để lấy **Flag 1** (chứng minh lỗ hổng có thật).
2. Triển khai reverse proxy `nginx` + ModSecurity + OWASP CRS trước `webapp`, chuyển sang chế độ **Blocking**, xác nhận payload tấn công cũ trả về **403** → lấy **Flag 2**.
3. Chạy DAST (nikto/ZAP baseline) qua đường trực tiếp (webapp) và qua WAF, so sánh số lượng cảnh báo.
4. Khử false positive cho một chức năng hợp lệ bị CRS chặn nhầm bằng rule exclusion → xác nhận chức năng hoạt động lại (200) trong khi tấn công vẫn bị chặn (403) → lấy **Flag 3**.

**Sơ đồ mạng (text):**

```
                 mạng ảo Labtainer  (dải 172.25.x.x)

  +--------------------+        +-----------------------+        +--------------------+
  |     client         |        |        waf            |        |      webapp        |
  |  (attacker/DAST)   | -----> |  nginx reverse proxy  | -----> |  ứng dụng web      |
  |                    |  HTTP  |  + ModSecurity v3     |  HTTP  |  lỗ hổng           |
  | curl, nikto, zap   |  :80   |  + OWASP CRS          |  :8080 |  SQLi/XSS/traversal|
  |                    |        |  audit log           |        |                    |
  |  172.25.0.10       |        |  172.25.0.20          |        |  172.25.0.30       |
  +--------------------+        +-----------------------+        +--------------------+

  Luồng "chưa có WAF"  : client ---------------------------------> webapp:8080   (khai thác trực tiếp → Flag 1)
  Luồng "có WAF"       : client ----> waf:80 (ModSecurity/CRS) ---> webapp:8080  (tấn công bị 403 → Flag 2/3)
```

> Ghi chú: `webapp:8080` cố tình vẫn truy cập trực tiếp được từ `client` trong môi trường lab để so sánh trước/sau WAF. Trong thực tế production, `webapp` phải được đặt ở mạng nội bộ chỉ nhận traffic từ WAF.

---

## 3. Kiến thức bổ trợ

**Kiến thức nền tảng**

- **WAF (Web Application Firewall):** thiết bị/phần mềm lọc, giám sát và chặn traffic HTTP/HTTPS giữa client và ứng dụng web, dựa trên tập luật nhận diện mẫu tấn công (chữ ký, biểu thức). WAF là **lớp phòng thủ bổ sung (defense-in-depth)** ở tầng runtime — mua thời gian để vá code, chứ **không thay thế** việc sửa lỗ hổng gốc trong mã nguồn.
- **ModSecurity:** engine WAF mã nguồn mở. Phiên bản v3 (`libmodsecurity`) tích hợp vào nginx qua connector `ModSecurity-nginx`. Engine chỉ cung cấp bộ máy xử lý rule; tập luật thực tế do người quản trị nạp vào (thường là OWASP CRS).
- **OWASP Core Rule Set (CRS):** tập luật chung, mã nguồn mở, phát hiện các lớp tấn công phổ biến (SQLi, XSS, LFI/RFI, path traversal, RCE...). CRS dùng **anomaly scoring**: mỗi rule khớp cộng một số điểm; khi tổng điểm của request vượt ngưỡng (`inbound_anomaly_score_threshold`, mặc định 5) thì request bị chặn.
- **Paranoia Level (PL):** mức "đa nghi" của CRS (PL1→PL4). PL càng cao càng bắt được nhiều biến thể tấn công nhưng càng dễ **false positive**. Cân bằng PL là một quyết định vận hành cốt lõi.
- **Chế độ hoạt động (SecRuleEngine):** `DetectionOnly` = chỉ ghi log, không chặn (dùng khi mới triển khai để quan sát); `On` = chặn thật (trả 403); `Off` = tắt.
- **False positive:** WAF chặn nhầm một request hợp lệ (ví dụ người dùng nhập nội dung có ký tự giống payload). Xử lý bằng **rule exclusion** khoanh vùng đúng chỗ (bỏ 1 rule ID cho 1 đường dẫn/tham số cụ thể) thay vì tắt cả nhóm luật.
- **DAST (Dynamic Application Security Testing):** kiểm thử bảo mật động — gửi request tấn công tới ứng dụng đang chạy và quan sát phản hồi (nikto, OWASP ZAP baseline). Dùng để đo lường khách quan hiệu quả của WAF trước/sau khi bật.

**Thành phần cần quan sát trong bài lab**

| Thành phần | Vai trò |
|---|---|
| `webapp` (172.25.0.30:8080) | Ứng dụng web lỗ hổng thật: endpoint SQLi (đăng nhập/tra cứu), endpoint XSS (phản chiếu tham số), endpoint path traversal (đọc file). Nơi chứa Flag 1. |
| `waf` (172.25.0.20:80) | Reverse proxy nginx + ModSecurity v3 + OWASP CRS. Nơi cấu hình `SecRuleEngine`, paranoia level, rule exclusion. Nơi sinh ra audit log. |
| File cấu hình ModSecurity (`modsecurity.conf`) | Chứa chỉ thị `SecRuleEngine` (DetectionOnly/On) và cấu hình audit log. |
| CRS setup (`crs-setup.conf`) | Nơi đặt paranoia level và ngưỡng anomaly score. |
| Audit log ModSecurity (`/var/log/modsec_audit.log`) | Ghi chi tiết request bị chặn: rule ID khớp, anomaly score, tham số vi phạm. Bằng chứng chấm điểm & để chẩn đoán false positive. |
| Chức năng hợp lệ bị chặn nhầm | Một endpoint hợp lệ (ví dụ ô tìm kiếm/bình luận cho phép nội dung "giống mã") bị CRS chặn → cần viết exclusion. |

**Bảng công cụ & cú pháp**

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `curl` | `curl -s -i "http://<IP>:<port>/<path>?<param>=<payload>"` | Gửi request HTTP, in cả header (`-i`) để đọc mã trạng thái (200/403). |
| `curl` (SQLi) | `curl -s -i "http://172.25.0.30:8080/product?id=1'%20OR%20'1'='1"` | Kiểm chứng SQL Injection qua tham số truy vấn. |
| `curl` (path traversal) | `curl -s "http://172.25.0.30:8080/download?file=../../../../etc/passwd"` | Kiểm chứng đọc file ngoài thư mục cho phép. |
| `curl` (qua WAF) | `curl -s -i "http://172.25.0.20/product?id=1'%20OR%20'1'='1"` | Gửi cùng payload nhưng qua reverse proxy WAF để xem có bị 403 không. |
| `nginx` | `nginx -t` / `nginx -s reload` | Kiểm tra cú pháp cấu hình / nạp lại cấu hình sau khi sửa. |
| ModSecurity conf | `SecRuleEngine On` \| `DetectionOnly` \| `Off` | Bật/tắt chế độ chặn của WAF (trong `modsecurity.conf`). |
| CRS setup | `SecAction "id:900000,...,setvar:tx.blocking_paranoia_level=<1..4>"` | Đặt paranoia level trong `crs-setup.conf`. |
| Exclusion (theo rule) | `SecRuleRemoveById <ruleId>` | Vô hiệu hoá hẳn 1 rule (phạm vi rộng — hạn chế dùng). |
| Exclusion (khoanh vùng) | `SecRule REQUEST_URI "@beginsWith /<path>" "id:<n>,phase:1,pass,nolog,ctl:ruleRemoveTargetById=<ruleId>;ARGS:<param>"` | Loại 1 rule chỉ cho 1 tham số trên 1 đường dẫn — cách khử false positive đúng phạm vi. |
| `tail` / `grep` | `tail -f /var/log/modsec_audit.log` · `grep -E "id \"9[0-9]{5}\"" /var/log/modsec_audit.log` | Theo dõi và lọc audit log để tìm rule ID đã khớp và anomaly score. |
| `nikto` | `nikto -h http://<IP>:<port> -o <out> -Format txt` | Quét lỗ hổng web động (DAST) nhanh, xuất báo cáo. |
| OWASP ZAP | `zap-baseline.py -t http://<IP>:<port> -r <report.html>` | Quét baseline thụ động/chủ động nhẹ, xuất báo cáo HTML (thay thế/bổ sung nikto). |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-waf-crs.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer dso-waf-crs
```

(chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm)

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy `client` (nơi sinh viên gõ lệnh tấn công và chạy DAST). Việc cấu hình WAF được thực hiện trên container `waf` (truy cập bằng lệnh chuyển terminal của Labtainer, ví dụ `moreterm.sh waf` hoặc chọn terminal `waf` theo hướng dẫn khởi động).

---

### Nhiệm vụ 1 — `exploit_direct`: Khai thác ứng dụng khi CHƯA có WAF

**Mục tiêu:** Chứng minh `webapp` thực sự có lỗ hổng bằng cách khai thác trực tiếp (bỏ qua WAF), lấy **Flag 1**.

**Bước 1:** Kiểm tra ứng dụng còn sống và khám phá các endpoint:
```bash
curl -s -i http://172.25.0.30:8080/
```

**Bước 2:** Khai thác **SQL Injection** để bypass logic truy vấn (ví dụ endpoint tra cứu sản phẩm/đăng nhập). Thử payload boolean-based:
```bash
curl -s -i "http://172.25.0.30:8080/product?id=1'%20OR%20'1'='1"
```
Quan sát: phản hồi trả về nhiều bản ghi hơn bình thường / bypass được điều kiện → xác nhận SQLi.

**Bước 3:** Khai thác **Path Traversal** để đọc file ngoài phạm vi cho phép:
```bash
curl -s "http://172.25.0.30:8080/download?file=../../../../etc/passwd"
```

**Bước 4:** Khai thác **Reflected XSS** để xác nhận tham số bị phản chiếu không được lọc:
```bash
curl -s "http://172.25.0.30:8080/search?q=<script>alert(1)</script>"
```

**Bước 5:** Tận dụng một trong các lỗ hổng trên (ví dụ path traversal đọc file flag, hoặc SQLi trích dữ liệu) để lấy **Flag 1**. Gợi ý:
```bash
curl -s "http://172.25.0.30:8080/download?file=../../../../flag1.txt"
```

**Điều kiện hoàn thành nhiệm vụ:** Khai thác thành công trực tiếp `webapp` (không qua WAF) và thu được chuỗi **Flag 1** đúng định dạng trong phản hồi HTTP.

**Câu hỏi 1:** Nếu chỉ dựa vào việc đặt WAF phía trước mà KHÔNG vá các lỗ hổng SQLi/traversal trong mã nguồn, những rủi ro tồn dư nào vẫn còn (gợi ý: bypass WAF, truy cập nội bộ, lỗi cấu hình)? Vì sao WAF được coi là biện pháp giảm nhẹ chứ không phải khắc phục triệt để?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `deploy_waf`: Triển khai ModSecurity + OWASP CRS và bật chế độ chặn

**Mục tiêu:** Cấu hình reverse proxy `waf` để định tuyến về `webapp`, nạp OWASP CRS, chuyển ModSecurity sang chế độ **Blocking**, xác nhận payload tấn công cũ bị trả **403** → lấy **Flag 2**.

**Bước 1:** Chuyển sang terminal container `waf`. Kiểm tra reverse proxy đã trỏ về `webapp`:
```bash
grep -R "proxy_pass" /etc/nginx/
# kỳ vọng: proxy_pass http://172.25.0.30:8080;
```

**Bước 2:** Xác nhận ModSecurity đã bật cho nginx và CRS đã được include:
```bash
grep -R "modsecurity" /etc/nginx/nginx.conf /etc/nginx/conf.d/
grep -R "crs-setup.conf\|rules/\*.conf" /etc/nginx/modsec/
```

**Bước 3:** Ban đầu để quan sát an toàn, đặt chế độ theo dõi rồi mới chặn. Mở `modsecurity.conf` và kiểm tra chỉ thị:
```bash
grep "SecRuleEngine" /etc/nginx/modsec/modsecurity.conf
```
Đặt tạm `SecRuleEngine DetectionOnly` để quan sát log trước (không chặn), sau đó chuyển sang chặn thật:
```bash
sed -i 's/^SecRuleEngine .*/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf
```

**Bước 4:** Đặt paranoia level (khuyến nghị bắt đầu ở PL1, có thể nâng PL2 để bắt nhiều biến thể) trong `crs-setup.conf`:
```bash
grep -n "blocking_paranoia_level" /etc/nginx/modsec/crs-setup.conf
# bỏ comment và đặt: setvar:tx.blocking_paranoia_level=1  (hoặc =2)
```

**Bước 5:** Kiểm tra cú pháp và nạp lại nginx:
```bash
nginx -t && nginx -s reload
```

**Bước 6:** Quay lại `client`, gửi LẠI đúng các payload của Nhiệm vụ 1 nhưng qua WAF (`172.25.0.20`):
```bash
curl -s -i "http://172.25.0.20/product?id=1'%20OR%20'1'='1"
curl -s -i "http://172.25.0.20/download?file=../../../../etc/passwd"
curl -s -i "http://172.25.0.20/search?q=<script>alert(1)</script>"
```
Kỳ vọng: các request này trả về **HTTP/1.1 403 Forbidden**.

**Bước 7:** Trên `waf`, đọc audit log để xác nhận rule CRS đã khớp và lấy **Flag 2** (flag phát khi có ≥1 tấn công bị chặn thành công / hiển thị trong trang lỗi 403 do lab cấu hình):
```bash
tail -n 50 /var/log/modsec_audit.log | grep -E "id \"9[0-9]{5}\"|Access denied|anomaly"
```

**Điều kiện hoàn thành nhiệm vụ:** `SecRuleEngine On` đang hiệu lực; ít nhất 2/3 payload tấn công của Nhiệm vụ 1 khi gửi qua `172.25.0.20` trả về mã **403**; audit log ghi nhận rule CRS khớp; thu được **Flag 2**.

**Câu hỏi 2:** Vì sao nên triển khai WAF ở chế độ `DetectionOnly` trong giai đoạn đầu trước khi bật `On`? Anomaly scoring của CRS khác gì so với cơ chế "một rule khớp là chặn ngay", và lợi ích của cách tiếp cận này là gì?
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `dast_compare`: Đánh giá bằng DAST trước/sau WAF

**Mục tiêu:** Dùng công cụ DAST quét ứng dụng qua đường trực tiếp và qua WAF, so sánh khách quan số lượng cảnh báo để định lượng hiệu quả của WAF.

**Bước 1:** Trên `client`, chạy DAST vào `webapp` trực tiếp (không WAF) và lưu báo cáo:
```bash
nikto -h http://172.25.0.30:8080 -o /root/dast_noWAF.txt -Format txt
# hoặc: zap-baseline.py -t http://172.25.0.30:8080 -r /root/dast_noWAF.html
```

**Bước 2:** Chạy DAST cùng công cụ vào WAF (`172.25.0.20`) và lưu báo cáo:
```bash
nikto -h http://172.25.0.20 -o /root/dast_WAF.txt -Format txt
# hoặc: zap-baseline.py -t http://172.25.0.20 -r /root/dast_WAF.html
```

**Bước 3:** So sánh số lượng phát hiện/cảnh báo giữa hai lần quét:
```bash
grep -c "OSVDB\|+ " /root/dast_noWAF.txt
grep -c "OSVDB\|+ " /root/dast_WAF.txt
```
Kỳ vọng: số cảnh báo (đặc biệt các mục injection/XSS/traversal) khi quét qua WAF **giảm rõ rệt** so với quét trực tiếp; nhiều request tấn công bị 403.

**Bước 4:** Trên `waf`, đối chiếu bằng cách đếm số request bị chặn trong audit log trong lúc quét:
```bash
grep -c "Access denied" /var/log/modsec_audit.log
```

**Điều kiện hoàn thành nhiệm vụ:** Tồn tại hai báo cáo DAST (`dast_noWAF` và `dast_WAF`); số lượng cảnh báo/phát hiện của bản quét qua WAF nhỏ hơn bản quét trực tiếp; audit log ghi nhận request tấn công từ DAST bị chặn.

**Câu hỏi 3:** DAST quét qua WAF cho ít cảnh báo hơn — điều này có đồng nghĩa ứng dụng đã "an toàn" và không cần vá nữa không? Nêu 2 hạn chế của việc chỉ dựa vào kết quả DAST sau WAF để kết luận về mức độ an toàn thực sự.
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `tune_falsepositive`: Khử false positive bằng rule exclusion (hardening)

**Mục tiêu:** Một chức năng hợp lệ của ứng dụng bị OWASP CRS chặn nhầm (ví dụ ô bình luận/tìm kiếm cho phép người dùng nhập nội dung kỹ thuật chứa ký tự giống payload, như đoạn mã, dấu ngoặc, `SELECT`, `<`). Sinh viên phải viết **rule exclusion đúng phạm vi** để khôi phục chức năng đó mà KHÔNG mở lại lỗ hổng thật ở các endpoint khác → lấy **Flag 3**.

**Bước 1:** Trên `client`, tái hiện false positive — gửi một request HỢP LỆ tới chức năng bị chặn nhầm (đường dẫn `/feedback`, tham số `comment`):
```bash
curl -s -i "http://172.25.0.20/feedback?comment=I%20love%20the%20SELECT%20menu%20and%20the%20%3Cb%3Ebold%3C/b%3E%20layout"
```
Quan sát: request hợp lệ này bị trả **403** (false positive).

**Bước 2:** Trên `waf`, xác định **rule ID** đã chặn nhầm và tham số vi phạm từ audit log:
```bash
tail -n 30 /var/log/modsec_audit.log | grep -E "\[id \"[0-9]+\"\]|/feedback|ARGS:comment"
```
Ghi lại rule ID (ví dụ một rule trong nhóm 941xxx XSS hoặc 942xxx SQLi) và tham số `ARGS:comment`.

**Bước 3:** Viết **rule exclusion khoanh vùng** — chỉ loại đúng rule đó, chỉ cho tham số `comment` trên đường dẫn `/feedback`, đặt trong file exclusion (ví dụ `/etc/nginx/modsec/crs-exclusions.conf`, được include TRƯỚC các rule CRS liên quan):
```apache
SecRule REQUEST_URI "@beginsWith /feedback" \
  "id:100001,phase:1,pass,nolog,\
   ctl:ruleRemoveTargetById=<RULE_ID>;ARGS:comment"
```
> Lưu ý: KHÔNG dùng `SecRuleRemoveById <RULE_ID>` trần (vô hiệu rule đó trên toàn site) và KHÔNG hạ `SecRuleEngine` xuống Off/DetectionOnly — đó là cách sai vì mở lại lỗ hổng.

**Bước 4:** Kiểm tra cú pháp và nạp lại:
```bash
nginx -t && nginx -s reload
```

**Bước 5:** Trên `client`, xác nhận **hai điều kiện đồng thời**:
```bash
# (a) chức năng hợp lệ hoạt động lại → phải 200
curl -s -i "http://172.25.0.20/feedback?comment=I%20love%20the%20SELECT%20menu%20and%20the%20%3Cb%3Ebold%3C/b%3E%20layout"

# (b) tấn công THẬT vẫn bị chặn → phải 403
curl -s -i "http://172.25.0.20/product?id=1'%20OR%20'1'='1"
curl -s -i "http://172.25.0.20/feedback?comment=<script>document.location='http://evil'</script>"
```
Nếu cả hai điều kiện thoả (chức năng hợp lệ 200, tấn công 403), lab phát **Flag 3**:
```bash
curl -s http://172.25.0.20/flag3
```

**Điều kiện hoàn thành nhiệm vụ:** Request hợp lệ tới `/feedback?comment=...` trả về **200**; đồng thời payload tấn công (SQLi trên `/product`, hoặc XSS thực sự) vẫn trả **403**; exclusion được viết khoanh vùng theo `ctl:ruleRemoveTargetById` (không tắt engine, không remove rule toàn cục); thu được **Flag 3**.

**Câu hỏi 4:** So sánh ba cách xử lý false positive: (a) `SecRuleEngine DetectionOnly`, (b) `SecRuleRemoveById` trần, (c) `ctl:ruleRemoveTargetById` khoanh vùng theo đường dẫn + tham số. Cách nào giữ được cân bằng tốt nhất giữa **an toàn** và **khả dụng**, và vì sao hai cách còn lại làm tăng rủi ro?
Trả lời: _______________________________________

---

## 5. Ghi chú triển khai (cho người xây lab)

**Container cần dựng (3):**
- `client` (172.25.0.10): cài `curl`, `nikto`, và OWASP ZAP baseline (`zap-baseline.py` — có thể dùng gói `zaproxy` hoặc chỉ giữ nikto nếu ZAP quá nặng cho VM; xem ghi chú tài nguyên). Nơi sinh viên gõ lệnh.
- `waf` (172.25.0.20): `nginx` + `libmodsecurity3` + connector `ModSecurity-nginx` + OWASP CRS. Reverse proxy `proxy_pass` về `webapp:8080`. Cấu hình sẵn `modsecurity.conf`, `crs-setup.conf`, và một file `crs-exclusions.conf` rỗng (được include đúng thứ tự) để sinh viên viết exclusion.
- `webapp` (172.25.0.30:8080): ứng dụng web lỗ hổng cố ý — chọn app nhẹ tự viết (Flask/PHP) hoặc dùng bản rút gọn dạng DVWA/juice-shop-mini. Cần có tối thiểu: endpoint SQLi (`/product?id=`), path traversal (`/download?file=`), reflected XSS (`/search?q=`), và endpoint hợp lệ `/feedback?comment=` để tạo false positive.

**Flag/goal dự kiến:**
- Goal `exploit_direct` → **Flag 1**: đặt trong `flag1.txt` ở vị trí lấy được qua path traversal/SQLi trực tiếp (không qua WAF). Chấm bằng chuỗi flag xuất hiện trong stdout `client`.
- Goal `deploy_waf` → **Flag 2**: phát khi `SecRuleEngine On` và có request tấn công bị 403 (ví dụ nhúng flag trong trang lỗi 403 tuỳ biến, hoặc script kiểm tra audit log có "Access denied"). Chấm bằng chuỗi flag + kiểm tra mã 403.
- Goal `dast_compare`: chấm bằng tồn tại hai file báo cáo và số cảnh báo `dast_WAF < dast_noWAF` (đối chiếu artifact file output + audit log count).
- Goal `tune_falsepositive` → **Flag 3**: endpoint `/flag3` trên `waf` chỉ trả flag khi backend kiểm tra đồng thời: (a) `/feedback` hợp lệ → 200 và (b) payload SQLi/XSS → 403. Có thể hiện thực bằng một script health-check nhỏ chạy trên `waf` ghi trạng thái, hoặc chấm dựa trên cặp mã trạng thái quan sát trong bash history/log.

**Cấu hình CRS offline & audit log (lưu ý quan trọng):**
- **Cài CRS offline:** đóng gói sẵn `coreruleset` (giải nén vào `/etc/nginx/modsec/`) trong image; KHÔNG tải rule qua mạng khi chạy (Labtainer offline). Tương tự, wordlist/dependency của DAST phải đóng gói sẵn.
- **Audit log:** bật `SecAuditEngine RelevantOnly`, `SecAuditLog /var/log/modsec_audit.log`, `SecAuditLogParts ABIJDEFHZ` để log đủ rule ID và anomaly score phục vụ Nhiệm vụ 2 & 4. Đảm bảo nginx worker có quyền ghi log.
- **Thứ tự include:** file `crs-exclusions.conf` của sinh viên phải được include SAU `crs-setup.conf` nhưng cần đúng phase để `ctl:ruleRemoveTargetById` có hiệu lực (rule exclusion phase:1 hoạt động trước khi rule CRS phase:2 chạy). Kiểm thử trước khi phát hành.
- **`webapp` cố ý truy cập trực tiếp được** từ `client` (để so sánh trước/sau WAF). Cần ghi rõ trong đề đây là dàn dựng cho mục đích học tập; production phải cô lập backend.

**Lưu ý tài nguyên:**
- OWASP ZAP tương đối nặng (JVM). Nếu VM Labtainer hạn chế RAM, khuyến nghị dùng **nikto làm công cụ DAST chính** và để ZAP là tuỳ chọn. Ghi chú lựa chọn này khi build.
- ModSecurity v3 + nginx nên build sẵn trong image (biên dịch connector tốn thời gian) để rút ngắn thời gian khởi động lab.
- Tham số hoá flag theo mã sinh viên (mỗi sinh viên 1 bộ Flag 1/2/3 khác nhau) để chống chép bài.
