# Học viện Công nghệ Bưu chính Viễn thông - SecLab PTIT
## HƯỚNG DẪN THỰC HÀNH

# Bảo vệ ứng dụng runtime với WAF Coraza + OWASP CRS

**Mức độ:** Nâng cao  **|**  **Phân loại:** DevSecOps / Application Security / Runtime Protection  **|**  **Ánh xạ khung:** OWASP Top 10 (A03 Injection, A05 Security Misconfiguration) · OWASP Core Rule Set (CRS) · OWASP DevSecOps Guideline (Runtime Protection / Dynamic Testing)

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `devops-waf-crs` |
| **Mức độ** | Nâng cao |
| **Công cụ sử dụng** | **Firefox** (trình duyệt trên máy `client` — gửi request và quan sát trực quan trang trả về so với trang chặn 403 của WAF), `curl` (lưu flag vào file và các bước script hoá), **Caddy** (reverse proxy) + **Coraza v3** (module coraza-caddy, cung SecLang + OWASP CRS), `nikto` (DAST baseline scan), `tail`/`grep` trên audit log Coraza |
| **Kiến thức yêu cầu** | Cơ bản về HTTP request/response và mã trạng thái (200/403/500); khái niệm lỗ hổng web phổ biến (SQLi, XSS, path traversal); dòng lệnh Linux; hiểu sơ lược reverse proxy. Bài **độc lập**, mọi khái niệm cốt lõi được nhắc lại ở mục 3. |

**Mục tiêu học tập**
- Hiểu vai trò của **WAF** như lớp phòng thủ runtime bổ sung (defense-in-depth), KHÔNG thay thế việc vá code.
- Nắm cơ chế **Coraza + OWASP CRS**: rule, anomaly scoring, paranoia level, chế độ Detection vs Blocking.
- Biết đặt reverse proxy có WAF trước một ứng dụng web lỗ hổng và kiểm chứng khả năng chặn tấn công.
- Biết dùng **DAST** (nikto baseline) để đánh giá khách quan hiệu quả trước/sau khi bật WAF.
- Hiểu và xử lý được **false positive**: viết rule exclusion để cân bằng an toàn vs khả dụng.

**Kỹ năng đạt được**
- Khai thác thực tế các lỗ hổng SQLi / XSS / path traversal **bằng trình duyệt (Firefox)** và `curl` để chứng minh rủi ro và quan sát trực quan hành vi chặn của WAF.
- Triển khai và cấu hình Coraza v3 + OWASP CRS trên Caddy (chuyển `DetectionOnly` → `On`).
- Đọc và phân tích **audit log** Coraza để xác định rule nào khớp (rule ID, anomaly score).
- Chạy và diễn giải kết quả **DAST** so sánh trạng thái có/không WAF.
- Viết **rule exclusion** (`ctl:ruleRemoveTargetById`) đúng phạm vi để khử false positive mà không mở lại lỗ hổng.

---

## 2. Kịch bản

**Tình huống:**
Công ty đang vận hành một ứng dụng web nội bộ (`webapp`) còn tồn tại nhiều lỗ hổng nghiêm trọng (SQL Injection, Reflected XSS, Path Traversal). Đội phát triển chưa thể vá code ngay trong sprint hiện tại vì phụ thuộc bên thứ ba. Ban lãnh đạo yêu cầu bộ phận DevSecOps **giảm rủi ro ngay lập tức** bằng cách đặt một lớp phòng thủ runtime trước ứng dụng, đồng thời chứng minh bằng số liệu rằng lớp phòng thủ này thực sự chặn được tấn công mà không làm hỏng chức năng hợp lệ của người dùng.

**Vai trò của sinh viên (DevOps engineer):**
1. Tấn công `webapp` khi CHƯA có WAF để lấy **Flag 1** (chứng minh lỗ hổng có thật).
2. Triển khai reverse proxy Caddy + Coraza + OWASP CRS trước `webapp`, chuyển sang chế độ **Blocking**, xác nhận payload tấn công cũ trả về **403** → lấy **Flag 2**.
3. Chạy DAST (nikto) qua đường trực tiếp (webapp) và qua WAF, so sánh số lượng cảnh báo.
4. Khử false positive cho một chức năng hợp lệ bị CRS chặn nhầm bằng rule exclusion → xác nhận chức năng hoạt động lại (200) trong khi tấn công vẫn bị chặn (403) → lấy **Flag 3**.

**Sơ đồ mạng (text):**

```
                 mạng ảo Labtainer  WAF_NET (172.38.0.0/24)

  +--------------------+        +-----------------------+        +--------------------+
  |     client         |        |        waf            |        |      webapp        |
  |  (attacker/DAST)   | -----> |  reverse proxy (Coraza)  | -----> |  ứng dụng web      |
  |                    |  HTTP  |  + Coraza v3     |  HTTP  |  lỗ hổng           |
  | curl, nikto        |  :80   |  + OWASP CRS          |  :8080 |  SQLi/XSS/traversal |
  |                    |        |  audit log            |        |                    |
  |  172.38.0.10       |        |  172.38.0.20          |        |  172.38.0.30       |
  +--------------------+        +-----------------------+        +--------------------+

  Luồng "chưa có WAF"  : client ---------------------------------> webapp:8080   (khai thác trực tiếp -> Flag 1)
  Luồng "có WAF"       : client ----> waf:80 (Coraza/CRS) ---> webapp:8080  (tấn công bị 403 -> Flag 2/3)
```

> Ghi chú: `webapp:8080` cố tình vẫn truy cập trực tiếp được từ `client` trong môi trường lab để so sánh trước/sau WAF. Trong thực tế production, `webapp` phải được đặt ở mạng nội bộ chỉ nhận traffic từ WAF.

---

## 3. Kiến thức bổ trợ

**Kiến thức nền tảng**

- **WAF (Web Application Firewall):** phần mềm lọc, giám sát và chặn traffic HTTP giữa client và ứng dụng web, dựa trên tập luật nhận diện mẫu tấn công. WAF là **lớp phòng thủ bổ sung** ở tầng runtime — mua thời gian để vá code, chứ **không thay thế** việc sửa lỗ hổng gốc.
- **Coraza:** engine WAF mã nguồn mở. Phiên bản v3 viet bang Go, nhung dung cung ngon ngu rule SecLang va tuong thich OWASP CRS nhu ModSecurity; o lab nay Coraza chay nhu module trong reverse proxy Caddy dat truoc webapp. Engine chỉ cung cấp bộ máy xử lý rule; tập luật thực tế do người quản trị nạp vào (thường là OWASP CRS).
- **OWASP Core Rule Set (CRS):** tập luật chung, mã nguồn mở, phát hiện các lớp tấn công phổ biến (SQLi, XSS, LFI/RFI, path traversal, RCE...). CRS dùng **anomaly scoring**: mỗi rule khớp cộng một số điểm; khi tổng điểm của request vượt ngưỡng (`inbound_anomaly_score_threshold`, mặc định 5) thì request bị chặn.
- **Paranoia Level (PL):** mức "đa nghi" của CRS (PL1→PL4). PL càng cao càng bắt được nhiều biến thể tấn công nhưng càng dễ **false positive**.
- **Chế độ hoạt động (SecRuleEngine):** `DetectionOnly` = chỉ ghi log, không chặn; `On` = chặn thật (trả 403); `Off` = tắt.
- **False positive:** WAF chặn nhầm một request hợp lệ. Xử lý bằng **rule exclusion** khoanh vùng đúng chỗ (bỏ 1 rule ID cho 1 đường dẫn/tham số cụ thể) thay vì tắt cả nhóm luật.
- **DAST (Dynamic Application Security Testing):** gửi request tấn công tới ứng dụng đang chạy và quan sát phản hồi (nikto). Dùng để đo lường khách quan hiệu quả của WAF trước/sau khi bật.

**Thành phần cần quan sát trong bài lab**

| Thành phần | Vai trò |
|---|---|
| `webapp` (172.38.0.30:8080) | Ứng dụng web lỗ hổng thật: endpoint SQLi (`/product?id=`), path traversal (`/download?file=`), reflected XSS (`/search?q=`), và endpoint hợp lệ `/feedback?comment=`. Nơi chứa Flag 1. |
| `waf` (172.38.0.20:80) | Reverse proxy Caddy + Coraza v3 + OWASP CRS. Nơi cấu hình `SecRuleEngine`, paranoia level, rule exclusion. Nơi sinh ra audit log. |
| `coraza.conf` (`/etc/coraza/`) | Chứa chỉ thị `SecRuleEngine` (DetectionOnly/On) và cấu hình audit log. |
| `crs-setup.conf` (`/etc/coraza/`) | Nơi đặt paranoia level và ngưỡng anomaly score. |
| `crs-exclusions.conf` (`/etc/coraza/`) | File rỗng được include đúng thứ tự để sinh viên viết rule exclusion. |
| Audit log (`/var/log/coraza/audit.log`) | Ghi chi tiết request bị chặn: rule ID khớp, anomaly score, tham số vi phạm. |

**Bảng công cụ & cú pháp**

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| **Firefox** | Mở từ menu ứng dụng của máy `client`, gõ URL vào thanh địa chỉ: `http://<IP>:<port>/<path>?<param>=<payload>` | Gửi request HTTP bằng trình duyệt và **xem trực quan** nội dung trả về (trang bình thường) so với **trang chặn 403** của WAF. Cách thao tác gần với người dùng/kẻ tấn công thật qua trình duyệt. |
| `curl` | `curl -s -i "http://<IP>:<port>/<path>?<param>=<payload>"` | Gửi request HTTP ở dòng lệnh, in cả header (`-i`) để đọc mã trạng thái (200/403). Dùng khi cần **lưu kết quả vào file** (ví dụ lấy flag) hoặc thao tác lặp/script hoá. |
| `curl` (SQLi) | `curl -s -i "http://172.38.0.30:8080/product?id=1'%20OR%20'1'='1"` | Kiểm chứng SQL Injection qua tham số truy vấn. |
| `curl` (path traversal) | `curl -s "http://172.38.0.30:8080/download?file=../../../../etc/passwd"` | Kiểm chứng đọc file ngoài thư mục cho phép. |
| `curl` (qua WAF) | `curl -s -i "http://172.38.0.20/product?id=1'%20OR%20'1'='1"` | Gửi cùng payload nhưng qua reverse proxy WAF để xem có bị 403 không. |
| `systemctl` | `sudo systemctl restart caddy` | Nap lai cau hinh WAF sau khi sua. |
| Coraza conf | `SecRuleEngine On` \| `DetectionOnly` \| `Off` | Bật/tắt chế độ chặn của WAF (trong `coraza.conf`). |
| CRS setup | `setvar:tx.blocking_paranoia_level=<1..4>` | Đặt paranoia level trong `crs-setup.conf`. |
| Exclusion (khoanh vùng) | `SecRule REQUEST_URI "@beginsWith /<path>" "id:<n>,phase:1,pass,nolog,ctl:ruleRemoveTargetById=<ruleId>;ARGS:<param>"` | Loại 1 rule chỉ cho 1 tham số trên 1 đường dẫn — cách khử false positive đúng phạm vi. |
| `tail` / `grep` | `sudo tail -n 80 /var/log/coraza/audit.log` · `grep -oE 'id \\"[0-9]+\\"' ...` | Theo dõi và lọc audit log để tìm rule ID đã khớp và anomaly score. Coraza ghi audit log dạng **JSON**: rule ID nằm trong `messages[].error_message` dưới dạng `[id \"942100\"]` (dấu nháy bị escape), nên grep theo `id \\"[0-9]+\\"`. |
| `nikto` | `nikto -h http://<IP>:<port> -o <out> -Format txt` | Quét lỗ hổng web động (DAST) nhanh, xuất báo cáo. |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/devops-waf-crs.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer devops-waf-crs
```

(chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm)

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho máy `client` (nơi sinh viên gõ lệnh và chạy DAST). Máy `client` đã cài sẵn **Firefox**: mở trình duyệt từ menu ứng dụng của máy ảo để **gửi request tấn công và quan sát trực quan** kết quả (trang bình thường ở cổng trực tiếp, so với trang **403 Forbidden** khi đi qua WAF). Việc cấu hình WAF được thực hiện trên container `waf` (truy cập bằng lệnh chuyển terminal của Labtainer, ví dụ `moreterm.sh waf`).

> **Cách làm hybrid (GUI + dòng lệnh):** Bài này khuyến khích **quan sát hành vi tấn công/phòng thủ bằng trình duyệt** (dán URL payload vào thanh địa chỉ Firefox, nhìn 200 so với trang chặn 403), còn các thao tác **cấu hình WAF, đọc audit log, chạy nikto và lưu flag vào file** vẫn dùng dòng lệnh. Riêng **bước lấy flag phải chạy đúng lệnh `curl ... | tee ~/flagN.txt`** vì hệ thống chấm điểm đọc nội dung các file `~/flag1.txt`, `~/flag2.txt`, `~/flag3.txt` — xem flag trên trình duyệt là để hiểu, nhưng phải lưu vào file thì mới được chấm.

---

### Nhiệm vụ 1 — `exploit_direct`: Khai thác ứng dụng khi CHƯA có WAF

**Mục tiêu:** Chứng minh `webapp` thực sự có lỗ hổng bằng cách khai thác trực tiếp (bỏ qua WAF), lấy **Flag 1**.

**Bước 1 (GUI):** Mở **Firefox** trên máy `client`, truy cập trang chủ ứng dụng để xem nó còn sống và khám phá giao diện:
```
http://172.38.0.30:8080/
```

**Bước 2 (GUI):** Khai thác **SQL Injection** (endpoint tra cứu sản phẩm) — dán URL sau vào thanh địa chỉ Firefox và quan sát dữ liệu trả về bị rò rỉ / thay đổi bất thường:
```
http://172.38.0.30:8080/product?id=1' OR '1'='1
```
(Firefox tự mã hoá khoảng trắng; nếu cần gõ tay bản đã mã hoá: `http://172.38.0.30:8080/product?id=1'%20OR%20'1'='1`.)

**Bước 3 (GUI):** Khai thác **Reflected XSS** — nhập URL sau và quan sát chuỗi `<script>` bị phản chiếu nguyên vẹn vào trang (tham số không được lọc):
```
http://172.38.0.30:8080/search?q=<script>alert(1)</script>
```

**Bước 4 (GUI quan sát):** Khai thác **Path Traversal** — xem thử việc đọc file ngoài phạm vi cho phép bằng Firefox:
```
http://172.38.0.30:8080/download?file=../../../../etc/passwd
```
Trang hiển thị nội dung `/etc/passwd` → xác nhận traversal thành công.

**Bước 4b (lưu Flag 1 — dùng dòng lệnh):** Mở terminal `client` và chạy lệnh sau để đọc **Flag 1** và **lưu vào file** (bắt buộc, vì hệ thống chấm đọc `~/flag1.txt`):
```bash
curl -s "http://172.38.0.30:8080/download?file=../../../../flag1.txt" | tee ~/flag1.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Khai thác thành công trực tiếp `webapp` (không qua WAF) và lưu chuỗi **Flag 1** vào `~/flag1.txt`.

**Câu hỏi 1:** Nếu chỉ dựa vào việc đặt WAF phía trước mà KHÔNG vá các lỗ hổng SQLi/traversal trong mã nguồn, những rủi ro tồn dư nào vẫn còn (gợi ý: bypass WAF, truy cập nội bộ, lỗi cấu hình)? Vì sao WAF được coi là biện pháp giảm nhẹ chứ không phải khắc phục triệt để?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `deploy_waf`: Triển khai Coraza + OWASP CRS và bật chế độ chặn

**Mục tiêu:** Cấu hình reverse proxy `waf` để nạp OWASP CRS, chuyển Coraza sang chế độ **Blocking**, xác nhận payload tấn công cũ bị trả **403** → lấy **Flag 2**.

**Bước 1:** Chuyển sang terminal container `waf` (`moreterm.sh waf`). Kiểm tra reverse proxy đã trỏ về `webapp`:
```bash
cat /etc/coraza/main.conf
# kỳ vọng: proxy_pass http://172.38.0.30:8080;
```

**Bước 2:** Xác nhận Coraza đã bật và CRS đã được include:
```bash
grep -R "SecRuleEngine" /etc/coraza/coraza.conf
grep -E "crs-setup|crs/rules|custom-rules" /etc/coraza/main.conf\|grep -E "crs-setup|crs/rules|custom-rules" /etc/coraza/main.conf
```

**Bước 3:** Mở `coraza.conf` và kiểm tra chỉ thị `SecRuleEngine` (ban đầu là `DetectionOnly` để quan sát an toàn), sau đó chuyển sang chặn thật:
```bash
grep "SecRuleEngine" /etc/coraza/coraza.conf
sudo sed -i 's/^SecRuleEngine .*/SecRuleEngine On/' /etc/coraza/coraza.conf
```

**Bước 4:** (Tuỳ chọn) Đặt paranoia level trong `crs-setup.conf` (bắt đầu PL1, có thể nâng PL2 để bắt nhiều biến thể):
```bash
grep -n "blocking_paranoia_level" /etc/coraza/crs/crs-setup.conf
# bỏ comment và đặt: setvar:tx.blocking_paranoia_level=1  (hoặc =2)
```

**Bước 5:** Nạp lại cấu hình WAF:
```bash
sudo systemctl restart caddy
```

**Bước 6 (GUI):** Quay lại **Firefox** trên `client`, gửi LẠI đúng các payload của Nhiệm vụ 1 nhưng lần này qua địa chỉ WAF (`172.38.0.20`, không còn cổng `:8080`). Dán lần lượt từng URL vào thanh địa chỉ:
```
http://172.38.0.20/product?id=1' OR '1'='1
http://172.38.0.20/download?file=../../../../etc/passwd
http://172.38.0.20/search?q=<script>alert(1)</script>
```
Kỳ vọng: thay vì trang dữ liệu như ở Nhiệm vụ 1, Firefox nay hiển thị **trang "403 Forbidden"** của WAF — tấn công đã bị Coraza/CRS chặn. (Muốn thấy rõ mã trạng thái dạng text, có thể chạy lại bằng `curl -s -i "http://172.38.0.20/product?id=1'%20OR%20'1'='1"` trong terminal.)

**Bước 7:** Trên `waf`, đọc audit log để xác nhận rule CRS đã khớp. Coraza ghi audit log dạng JSON; liệt kê các rule ID vừa khớp:
```bash
sudo tail -n 80 /var/log/coraza/audit.log | grep -oE 'id \\"[0-9]+\\"' | sort -u
```

**Bước 8:** Trên `client`, lấy **Flag 2** (chỉ phát khi WAF thực sự đang chặn tấn công và vẫn cho request hợp lệ đi qua):
```bash
curl -s http://172.38.0.20/flag2 | tee ~/flag2.txt
```

**Điều kiện hoàn thành nhiệm vụ:** `SecRuleEngine On` đang hiệu lực; payload tấn công của Nhiệm vụ 1 khi gửi qua `172.38.0.20` trả về mã **403**; audit log ghi nhận rule CRS khớp; **Flag 2** được lưu vào `~/flag2.txt`.

**Câu hỏi 2:** Vì sao nên triển khai WAF ở chế độ `DetectionOnly` trong giai đoạn đầu trước khi bật `On`? Anomaly scoring của CRS khác gì so với cơ chế "một rule khớp là chặn ngay", và lợi ích của cách tiếp cận này là gì?
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `dast_compare`: Đánh giá bằng DAST trước/sau WAF

**Mục tiêu:** Dùng công cụ DAST quét ứng dụng qua đường trực tiếp và qua WAF, so sánh khách quan số lượng cảnh báo để định lượng hiệu quả của WAF.

**Bước 1:** Trên `client`, chạy DAST vào `webapp` trực tiếp (không WAF) và lưu báo cáo:
```bash
nikto -h http://172.38.0.30:8080 -o ~/dast_noWAF.txt -Format txt
```

**Bước 2:** Chạy DAST cùng công cụ vào WAF (`172.38.0.20`) và lưu báo cáo:
```bash
nikto -h http://172.38.0.20 -o ~/dast_WAF.txt -Format txt
```

**Bước 3:** So sánh số lượng phát hiện/cảnh báo giữa hai lần quét:
```bash
grep -c '^+ ' ~/dast_noWAF.txt
grep -c '^+ ' ~/dast_WAF.txt
```
Kỳ vọng: số cảnh báo khi quét qua WAF **giảm rõ rệt** so với quét trực tiếp; nhiều request tấn công bị 403.

**Bước 4:** Trên `waf`, đối chiếu bằng cách đếm số request bị chặn trong audit log (Coraza đánh dấu giao dịch bị chặn bằng `interrupted`):
```bash
sudo grep -c interrupted /var/log/coraza/audit.log
```

**Điều kiện hoàn thành nhiệm vụ:** Tồn tại hai báo cáo DAST (`~/dast_noWAF.txt` và `~/dast_WAF.txt`); số lượng cảnh báo của bản quét qua WAF nhỏ hơn bản quét trực tiếp (hoặc báo cáo qua WAF ghi nhận request bị chặn 403).

**Câu hỏi 3:** DAST quét qua WAF cho ít cảnh báo hơn — điều này có đồng nghĩa ứng dụng đã "an toàn" và không cần vá nữa không? Nêu 2 hạn chế của việc chỉ dựa vào kết quả DAST sau WAF để kết luận về mức độ an toàn thực sự.
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `tune_falsepositive`: Khử false positive bằng rule exclusion (hardening)

**Mục tiêu:** Một chức năng hợp lệ của ứng dụng bị OWASP CRS chặn nhầm (ô `/feedback` cho phép người dùng nhập nội dung kỹ thuật chứa từ khoá giống payload, ví dụ `UNION`, `SELECT`, `ORDER BY`). Sinh viên phải viết **rule exclusion đúng phạm vi** để khôi phục chức năng đó mà KHÔNG mở lại lỗ hổng thật ở các endpoint khác → lấy **Flag 3**.

**Bước 1 (GUI):** Trên **Firefox**, tái hiện false positive — gửi một góp ý HỢP LỆ (chứa từ khoá kỹ thuật `UNION SELECT`, `ORDER BY`) tới chức năng feedback qua WAF:
```
http://172.38.0.20/feedback?comment=Please add UNION SELECT and ORDER BY price to the price list
```
Quan sát: góp ý hợp lệ này lại bị WAF trả **trang 403** (false positive — CRS tưởng nhầm là SQLi).

**Bước 2:** Trên `waf`, xác định **rule ID** đã chặn nhầm từ audit log (JSON của Coraza; lấy đúng giao dịch `/feedback` gần nhất rồi trích các rule ID):
```bash
sudo grep feedback /var/log/coraza/audit.log | grep '"messages"' | tail -1 \
  | grep -oE 'id \\"[0-9]+\\"' | grep -oE '[0-9]+' | sort -u
```
Kết quả gồm rule SQLi nhóm `942xxx` (ví dụ `942190`) cần loại cho `ARGS:comment`; rule `949110` là rule cộng dồn anomaly (KHÔNG loại rule này).
Ghi lại rule ID (ví dụ một rule trong nhóm 942xxx SQLi) và tham số `ARGS:comment`.

**Bước 3:** Trên `waf`, viết **rule exclusion khoanh vùng** vào file `/etc/coraza/custom-rules.conf` — chỉ loại đúng rule đó, chỉ cho tham số `comment` trên đường dẫn `/feedback`:
```apache
SecRule REQUEST_URI "@beginsWith /feedback" \
  "id:100001,phase:1,pass,nolog,\
   ctl:ruleRemoveTargetById=<RULE_ID>;ARGS:comment"
```
> Lưu ý: KHÔNG dùng `SecRuleRemoveById <RULE_ID>` trần (vô hiệu rule đó trên toàn site) và KHÔNG hạ `SecRuleEngine` xuống Off/DetectionOnly — đó là cách sai vì mở lại lỗ hổng. Nếu một request hợp lệ khớp nhiều rule, liệt kê nhiều chỉ thị `ctl:ruleRemoveTargetById=<id>;ARGS:comment` trong cùng một `SecRule`.

**Bước 4:** Kiểm tra cú pháp và nạp lại:
```bash
sudo systemctl restart caddy
```

**Bước 5 (GUI):** Trên **Firefox**, xác nhận **hai điều kiện đồng thời** bằng cách dán lần lượt các URL và quan sát trang trả về:
```
# (a) góp ý hợp lệ phải hoạt động lại -> trang feedback bình thường (200)
http://172.38.0.20/feedback?comment=Please add UNION SELECT and ORDER BY price to the price list

# (b) tấn công THẬT vẫn phải bị chặn -> trang 403
http://172.38.0.20/product?id=1' OR '1'='1
http://172.38.0.20/feedback?comment=<script>document.location='http://evil'</script>
```
(Có thể kiểm chứng lại mã trạng thái bằng `curl -s -i` tương ứng trong terminal nếu muốn thấy rõ `200`/`403`.)

**Bước 6:** Nếu cả hai điều kiện thoả (chức năng hợp lệ 200, tấn công 403), lấy **Flag 3**:
```bash
curl -s http://172.38.0.20/flag3 | tee ~/flag3.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Request hợp lệ tới `/feedback?comment=...` trả về **200**; đồng thời payload tấn công (SQLi trên `/product`, và XSS thực sự trên `/feedback`) vẫn trả **403**; exclusion được viết khoanh vùng theo `ctl:ruleRemoveTargetById` (không tắt engine, không remove rule toàn cục); **Flag 3** được lưu vào `~/flag3.txt`.

**Câu hỏi 4:** So sánh ba cách xử lý false positive: (a) `SecRuleEngine DetectionOnly`, (b) `SecRuleRemoveById` trần, (c) `ctl:ruleRemoveTargetById` khoanh vùng theo đường dẫn + tham số. Cách nào giữ được cân bằng tốt nhất giữa **an toàn** và **khả dụng**, và vì sao hai cách còn lại làm tăng rủi ro?
Trả lời: _______________________________________

Sau khi hoàn thành cả bốn nhiệm vụ, chạy lệnh sau trên `client` để kiểm tra kết quả:
```bash
checkwork
```

---

## 5. Ánh xạ khung tham chiếu

- **OWASP Top 10:** A03:2021 Injection (SQLi/XSS), A05:2021 Security Misconfiguration (triển khai/điều chỉnh WAF).
- **OWASP Core Rule Set (CRS):** anomaly scoring, paranoia level, rule exclusion.
- **OWASP DevSecOps Guideline:** Runtime Protection (WAF) và Dynamic Testing (DAST) trong vòng đời phát triển an toàn.
- **Nguyên tắc defense-in-depth:** WAF là lớp giảm nhẹ runtime, bổ sung chứ không thay thế việc vá lỗ hổng ở mã nguồn.
