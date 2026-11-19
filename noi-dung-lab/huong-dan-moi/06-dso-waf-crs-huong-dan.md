# HƯỚNG DẪN THỰC HÀNH — Lab 6: Bảo vệ ứng dụng runtime với WAF Coraza + OWASP CRS

- **Mã lab:** `dso-waf-crs`
- **Mức độ:** 3/4 (Nâng cao)
- **Công cụ:** `curl`, `nikto`, Caddy + Coraza v3 + OWASP CRS (cấu hình SecLang), `systemctl`, `grep`/`tail` trên audit log
- **Kiến thức cần:** HTTP request/response và mã trạng thái (200/403), SQLi/XSS/path traversal ở mức khái niệm, reverse proxy, anomaly scoring và paranoia level của CRS

> Guide này mức **3/4**: chỉ cho **khái niệm + công cụ + khung lệnh trống nhiều chỗ `<...>`**. Bạn tự ghép chuỗi lệnh và tự sửa cấu hình. Nếu bí, mở mục **Gợi ý mở rộng** ở cuối mỗi nhiệm vụ để xem lệnh chi tiết hơn. Đáp án và flag không có sẵn ở đây.

## Bối cảnh
Công ty có một ứng dụng web nội bộ (`webapp`) đầy lỗ hổng nhưng chưa kịp vá code. Bạn là DevSecOps engineer: đặt một lớp **WAF** (reverse proxy Caddy + Coraza + OWASP CRS) phía trước để giảm rủi ro ngay, rồi **chứng minh bằng bằng chứng** rằng WAF chặn được tấn công mà không làm hỏng chức năng hợp lệ.

```
              mạng ảo Labtainer WAF_NET (172.38.0.0/24)

 +----------------+        +--------------------------+        +------------------+
 | client         | -----> | waf                      | -----> | webapp           |
 | curl, nikto    |  :80   | Caddy + Coraza + CRS     |  :8080 | SQLi/XSS/        |
 | 172.38.0.10    |        | audit log                |        | traversal        |
 |                |        | 172.38.0.20              |        | 172.38.0.30      |
 +----------------+        +--------------------------+        +------------------+

 Không có WAF : client ----------------------------> webapp:8080
 Có WAF       : client ----> waf:80 (Coraza/CRS) --> webapp:8080
```

Bạn làm việc trên **2 terminal**: `client` (tấn công, DAST) và `waf` (sửa cấu hình, đọc log; mở bằng `moreterm.sh waf`). Các file cấu hình WAF nằm ở `/etc/coraza/`.

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-waf-crs.tar
labtainer dso-waf-crs
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn).

---

## Câu lệnh tham khảo (cú pháp chung — tự ghép, tự điền `<...>`)

| Mục đích | Cú pháp chung |
|---|---|
| Gửi request khai thác / kiểm thử | `curl -s -i "http://<HOST>:<PORT>/<ENDPOINT>?<THAM_SỐ>=<PAYLOAD>"` |
| Chỉ xem mã trạng thái (200/403) | `curl -s -o /dev/null -w "%{http_code}\n" "<URL>"` |
| Quét DAST tự động | `nikto -h http://<HOST>:<PORT>` |
| Khởi động lại / xem trạng thái WAF | `sudo systemctl restart <SERVICE>` · `systemctl status <SERVICE>` |
| Sửa cấu hình CRS/Coraza | sửa file SecLang trong `/etc/coraza/` (bật/tắt rule, đổi paranoia level) |
| Đọc audit log WAF | `tail -n <N> <AUDIT_LOG>` · `grep -i "<RULE_ID|chuỗi>" <AUDIT_LOG>` |

> Đây chỉ là "từ vựng" lệnh. Bạn tự chọn endpoint/payload, tự ghép chuỗi và tự sửa cấu hình cho từng nhiệm vụ.

---

## Nhiệm vụ 1 — `exploit_direct`: Khai thác khi CHƯA có WAF
**Mục tiêu:** Chứng minh `webapp` có lỗ hổng thật bằng cách tấn công **trực tiếp** (bỏ qua WAF) và đọc được **Flag 1**.

**Gợi ý tư duy:**
- Trước hết hãy khám phá: ứng dụng có những endpoint nào, tham số nào? Một lần `curl` vào trang gốc thường đủ để thấy gợi ý.
- Ba họ lỗ hổng cần chứng minh: **SQLi** (tham số số nguyên bị ghép vào truy vấn), **Reflected XSS** (tham số tìm kiếm bị phản chiếu nguyên văn), **Path Traversal** (tham số tên file bị nối vào đường dẫn).
- Chú ý URL-encode: khoảng trắng/dấu nháy trong URL dòng lệnh cần được mã hoá (`%20`) hoặc bọc nháy kép cẩn thận.
- Flag 1 là một file nằm ở thư mục gốc của máy chủ ứng dụng; path traversal là con đường tới nó. Chỉ lấy dòng đầu chứa chuỗi flag.

**Khung lệnh (tự điền):**
```bash
curl -s -i http://<IP_WEBAPP>:<PORT>/
curl -s -i "http://<IP_WEBAPP>:<PORT>/<ENDPOINT_SQLI>?<THAM_SỐ>=<PAYLOAD_SQLI>"
curl -s "http://<IP_WEBAPP>:<PORT>/<ENDPOINT_XSS>?<THAM_SỐ>=<PAYLOAD_XSS>"
curl -s "http://<IP_WEBAPP>:<PORT>/<ENDPOINT_TRAVERSAL>?<THAM_SỐ>=<CHUỖI_ĐI_LÊN_NHIỀU_CẤP>/<FILE_ĐÍCH>"
# Lưu flag để chấm điểm:
curl -s "<URL_ĐỌC_FLAG>" | ... > ~/flag1.txt
```
**Hoàn thành khi:** `~/flag1.txt` chứa chuỗi flag 1 (một dòng, không thừa nội dung).

**Câu hỏi:** Nếu chỉ đặt WAF mà không vá code, rủi ro tồn dư nào còn lại (gợi ý: bypass WAF, truy cập thẳng `webapp:8080`, lỗi cấu hình)? Vì sao WAF chỉ là biện pháp giảm nhẹ? → Trả lời: ____

<details><summary>Gợi ý mở rộng</summary>

- Endpoint của webapp (cổng 8080): `/product?id=`, `/search?q=`, `/download?file=`, và `/feedback?comment=` (dùng ở Nhiệm vụ 4).
- SQLi cổ điển: `id=1' OR '1'='1` (mã hoá: `1'%20OR%20'1'='1`).
- XSS: `q=<script>alert(1)</script>`.
- Traversal: `file=../../../../etc/passwd` để xác nhận, rồi đổi file đích thành `flag1.txt` (cũng đi lên 4 cấp).
- Lấy dòng đầu: `... | tr -d '\r' | awk 'NF {print $1; exit}' > ~/flag1.txt`.
</details>

---

## Nhiệm vụ 2 — `deploy_waf`: Bật chế độ chặn Coraza và lấy Flag 2
**Mục tiêu:** Chuyển Coraza từ chế độ chỉ quan sát sang **chặn thật**, rồi chứng minh payload của Nhiệm vụ 1 gửi qua WAF bị trả **403**. Khi WAF chặn đúng, endpoint cấp **Flag 2** mới mở.

**Gợi ý tư duy:**
- `SecRuleEngine` có 3 giá trị: `On` (chặn), `DetectionOnly` (chỉ ghi log), `Off`. Lab khởi đầu ở chế độ quan sát. File chứa chỉ thị này là `coraza.conf`.
- Sau khi sửa file cấu hình, Caddy phải được **nạp lại** thì Coraza mới đổi hành vi.
- Cùng payload cũ, nhưng lần này nhắm vào **IP của WAF cổng 80** thay vì `webapp:8080`. Kỳ vọng mã trả về là gì?
- CRS chặn theo **anomaly score**: mỗi rule khớp cộng điểm, vượt ngưỡng thì 403. Có thể thử đổi **paranoia level** (tuỳ chọn) trong `crs-setup.conf`; tăng PL bắt thêm biến thể nhưng dễ false positive.
- Audit log Coraza là **JSON**; rule ID nằm trong thông điệp lỗi dạng `[id "..."]` với dấu nháy bị escape nên cần grep cẩn thận.
- Flag 2 chỉ phát khi WAF thực sự đang chặn; hãy tự đoán đường dẫn theo quy ước đặt tên flag của bài.

**Khung lệnh (tự điền):**
```bash
# Trên waf:
grep -n "<CHỈ_THỊ_ENGINE>" /etc/coraza/<FILE_CẤU_HÌNH_ENGINE>
sudo sed -i 's/^<CHỈ_THỊ_ENGINE> .*/<CHỈ_THỊ_ENGINE> <GIÁ_TRỊ_CHẶN>/' /etc/coraza/<FILE_CẤU_HÌNH_ENGINE>
sudo systemctl <HÀNH_ĐỘNG_NẠP_LẠI> caddy

# Trên client (gửi lại payload của Nhiệm vụ 1, nhưng qua WAF):
curl -s -o /dev/null -w "%{http_code}\n" "http://<IP_WAF>/<ENDPOINT>?<THAM_SỐ>=<PAYLOAD>"

# Trên waf, đọc audit log để xem rule nào khớp:
sudo tail -n 80 /var/log/coraza/audit.log | grep -oE '<MẪU_ID_RULE>' | sort -u

# Trên client, lấy Flag 2:
curl -s http://<IP_WAF>/<ĐƯỜNG_DẪN_FLAG2> | ... > ~/flag2.txt
```
**Hoàn thành khi:** 3 payload (SQLi, traversal, XSS) qua WAF đều trả **403**, audit log ghi nhận rule CRS, và `~/flag2.txt` chứa Flag 2.

**Câu hỏi:** Vì sao nên chạy `DetectionOnly` một thời gian trước khi bật `On`? Anomaly scoring khác gì "một rule khớp là chặn ngay" và có lợi gì? → ____

<details><summary>Gợi ý mở rộng</summary>

- Chỉ thị: `SecRuleEngine`, file `/etc/coraza/coraza.conf`; giá trị chặn là `On`.
- Lệnh sửa: `sudo sed -i 's/^SecRuleEngine .*/SecRuleEngine On/' /etc/coraza/coraza.conf`.
- Nạp lại: `sudo systemctl restart caddy`.
- Paranoia level (tuỳ chọn): `grep -n "blocking_paranoia_level" /etc/coraza/crs/crs-setup.conf`, bỏ comment và đặt `setvar:tx.blocking_paranoia_level=1` (hoặc `2`).
- Mẫu lọc rule ID trong JSON: `grep -oE 'id \\"[0-9]+\\"'`.
- Flag 2: `curl -s http://172.38.0.20/flag2`; lưu dòng đầu bằng `tr -d '\r' | awk 'NF {print $1; exit}'`.
</details>

---

## Nhiệm vụ 3 — `dast_compare`: Đo hiệu quả WAF bằng DAST
**Mục tiêu:** Quét cùng một công cụ DAST vào `webapp` (trực tiếp) và vào WAF, lưu 2 báo cáo, rồi **so sánh số cảnh báo**.

**Gợi ý tư duy:**
- DAST gửi hàng trăm request thăm dò tới ứng dụng đang chạy; công cụ ở lab này là `nikto`. Cần đọc `-h` (host) và tuỳ chọn xuất file (`-o`, `-Format`).
- Hai lần quét phải cùng công cụ, cùng tham số, chỉ khác **đích**. Nikto quét khá lâu; có thể giới hạn thời gian bằng `-maxtime`.
- Trong báo cáo dạng text, mỗi phát hiện là một dòng bắt đầu bằng `+ `. Đếm số dòng đó ở mỗi file.
- Đối chiếu phía `waf`: audit log đánh dấu giao dịch bị chặn bằng từ khoá `interrupted`.
- Số cảnh báo giảm không đồng nghĩa ứng dụng đã an toàn; hãy nghĩ vì sao (câu hỏi bên dưới).

**Khung lệnh (tự điền):**
```bash
nikto -h http://<ĐÍCH_TRỰC_TIẾP> -o ~/<BÁO_CÁO_KHÔNG_WAF> -Format txt
nikto -h http://<ĐÍCH_QUA_WAF>    -o ~/<BÁO_CÁO_CÓ_WAF>    -Format txt
grep -c '<MẪU_DÒNG_CẢNH_BÁO>' ~/<BÁO_CÁO_KHÔNG_WAF>
grep -c '<MẪU_DÒNG_CẢNH_BÁO>' ~/<BÁO_CÁO_CÓ_WAF>
# Trên waf:
sudo grep -c <TỪ_KHOÁ_BỊ_CHẶN> /var/log/coraza/audit.log
```
**Hoàn thành khi:** có 2 file `~/dast_noWAF.txt` và `~/dast_WAF.txt`; số cảnh báo qua WAF **nhỏ hơn** quét trực tiếp.

**Câu hỏi:** DAST qua WAF ít cảnh báo hơn thì đã "an toàn" chưa? Nêu 2 hạn chế của việc chỉ dựa vào kết quả này. → ____

<details><summary>Gợi ý mở rộng</summary>

- Quét trực tiếp: `nikto -h http://172.38.0.30:8080 -maxtime 120 -o ~/dast_noWAF.txt -Format txt`.
- Quét qua WAF: `nikto -h http://172.38.0.20 -maxtime 120 -o ~/dast_WAF.txt -Format txt`.
- Đếm: `grep -c '^+ ' ~/dast_noWAF.txt` và `grep -c '^+ ' ~/dast_WAF.txt`.
- Trên `waf`: `sudo grep -c interrupted /var/log/coraza/audit.log`.
- Tên file báo cáo phải đúng như trên để chấm điểm đọc được.
</details>

---

## Nhiệm vụ 4 — `tune_falsepositive`: Khử false positive bằng exclusion khoanh vùng
**Mục tiêu:** Chức năng hợp lệ `/feedback` cho phép nhập nội dung kỹ thuật (chứa từ như `UNION`, `SELECT`, `ORDER BY`) nên bị CRS chặn nhầm. Viết **rule exclusion đúng phạm vi** để chức năng này trả **200**, trong khi tấn công thật vẫn trả **403**. Đạt cả hai thì lấy **Flag 3**.

**Gợi ý tư duy:**
- Bước 1: **tái hiện** false positive: gửi comment hợp lệ qua WAF, xác nhận bị 403.
- Bước 2: **tìm đúng rule gây chặn**: lọc giao dịch `/feedback` gần nhất trong audit log và trích các rule ID. Chú ý hai nhóm: rule SQLi `942xxx` (đó là thủ phạm cần loại) và rule cộng dồn anomaly `949110` (**không** được loại, nó chỉ là tổng kết điểm).
- Bước 3: viết exclusion vào `/etc/coraza/custom-rules.conf`. Cơ chế dùng: một `SecRule` bắt theo đường dẫn (`REQUEST_URI`, `@beginsWith`), ở giai đoạn `phase:1`, hành động `pass,nolog`, kèm chỉ thị `ctl:ruleRemoveTargetById=<rule>;ARGS:<tham số>`. Mỗi `SecRule` cần một `id` riêng (dùng dải ID tuỳ chọn, ví dụ số 6 chữ số, không trùng CRS).
- Nếu một request hợp lệ khớp **nhiều** rule, liệt kê nhiều `ctl:` trong cùng một `SecRule`.
- Ba lối tắt **sai**: hạ `SecRuleEngine` xuống `DetectionOnly`/`Off`, dùng `SecRuleRemoveById` trần (tắt rule trên toàn site), hoặc loại nguyên tham số khỏi mọi đường dẫn. Cả ba đều mở lại lỗ hổng ở endpoint khác.
- Cuối cùng kiểm tra **hai điều kiện đồng thời** (200 cho hợp lệ + 403 cho tấn công), rồi mới lấy Flag 3.

**Khung lệnh (tự điền):**
```bash
# 1. client: tái hiện false positive
curl -s -o /dev/null -w "%{http_code}\n" "http://<IP_WAF>/<ENDPOINT_HỢP_LỆ>?<THAM_SỐ>=<NỘI_DUNG_HỢP_LỆ_CÓ_UNION_SELECT>"

# 2. waf: tìm rule ID gây chặn (giao dịch /feedback gần nhất)
sudo grep <TỪ_KHOÁ_ĐƯỜNG_DẪN> /var/log/coraza/audit.log | tail -1 | grep -oE '<MẪU_ID_RULE>' | grep -oE '[0-9]+' | sort -u

# 3. waf: viết exclusion khoanh vùng (chỉ 1 rule, chỉ 1 tham số, chỉ 1 đường dẫn)
sudo tee -a /etc/coraza/custom-rules.conf <<'EOF'
SecRule REQUEST_URI "<TOÁN_TỬ> /<ĐƯỜNG_DẪN>" \
  "id:<ID_TỰ_CHỌN>,phase:<GIAI_ĐOẠN>,pass,nolog,\
   ctl:<CHỈ_THỊ_LOẠI_TARGET>=<RULE_ID>;ARGS:<THAM_SỐ>"
EOF
sudo systemctl restart caddy

# 4. client: kiểm tra 2 điều kiện
curl -s -o /dev/null -w "%{http_code}\n" "<REQUEST_HỢP_LỆ>"      # mong đợi 200
curl -s -o /dev/null -w "%{http_code}\n" "<SQLI_QUA_WAF>"        # mong đợi 403
curl -s -o /dev/null -w "%{http_code}\n" "<XSS_THẬT_TRÊN_ENDPOINT_FEEDBACK>"  # mong đợi 403

# 5. Chỉ khi đủ điều kiện: lấy Flag 3
curl -s http://<IP_WAF>/<ĐƯỜNG_DẪN_FLAG3> | ... > ~/flag3.txt
```
**Hoàn thành khi:** comment hợp lệ ở `/feedback` trả **200**; SQLi trên `/product` và XSS thật trên `/feedback` vẫn trả **403**; exclusion viết khoanh vùng bằng `ctl:ruleRemoveTargetById`; `~/flag3.txt` chứa Flag 3.

**Câu hỏi:** So sánh (a) `SecRuleEngine DetectionOnly`, (b) `SecRuleRemoveById` trần, (c) `ctl:ruleRemoveTargetById` theo đường dẫn + tham số. Cách nào cân bằng tốt nhất giữa an toàn và khả dụng, vì sao hai cách kia làm tăng rủi ro? → ____

<details><summary>Gợi ý mở rộng</summary>

- Request hợp lệ: `curl -s -i "http://172.38.0.20/feedback?comment=Hay%20them%20nut%20UNION%20SELECT%20va%20ORDER%20BY%20price%20cho%20bang%20gia"`.
- Trích rule ID:
  `sudo grep feedback /var/log/coraza/audit.log | grep '"messages"' | tail -1 | grep -oE 'id \\"[0-9]+\\"' | grep -oE '[0-9]+' | sort -u`
  (loại `949110`, giữ các rule `942xxx`, ví dụ `942190`).
- Mẫu exclusion (thay `<RULE_ID>` bằng từng rule `942xxx` bạn tìm được):
  ```apache
  SecRule REQUEST_URI "@beginsWith /feedback" \
    "id:100001,phase:1,pass,nolog,\
     ctl:ruleRemoveTargetById=<RULE_ID>;ARGS:comment"
  ```
  Nhiều rule thì lặp thêm `ctl:ruleRemoveTargetById=<RULE_ID_2>;ARGS:comment`.
- Nạp lại: `sudo systemctl restart caddy`.
- Tấn công thật phải còn bị chặn:
  `curl -s -i "http://172.38.0.20/product?id=1'%20OR%20'1'='1"` và
  `curl -s -i "http://172.38.0.20/feedback?comment=<script>document.location='http://evil'</script>"`.
- Flag 3: `curl -s http://172.38.0.20/flag3`; lưu dòng đầu bằng `tr -d '\r' | awk 'NF {print $1; exit}'`.
</details>

---

## Chấm điểm
```bash
checkwork dso-waf-crs
```
Đạt khi 4 mục tiêu = **Y**: `exploit_direct`, `deploy_waf`, `dast_compare`, `tune_falsepositive`.

**Bằng chứng cần tạo (tên file ở `~` trên `client`):**
- `~/flag1.txt` — Flag 1 (khai thác trực tiếp `webapp`).
- `~/flag2.txt` — Flag 2 (chỉ có khi WAF đang chặn).
- `~/dast_noWAF.txt` và `~/dast_WAF.txt` — 2 báo cáo nikto, bản qua WAF ít cảnh báo hơn.
- `~/flag3.txt` — Flag 3 (chỉ có khi exclusion khoanh vùng đúng: hợp lệ 200, tấn công 403).

> Gợi ý cuối: nếu một mục chưa Y, kiểm tra file bằng chứng tương ứng có tồn tại và không rỗng; nếu `flag2`/`flag3` rỗng hoặc sai, WAF chưa ở trạng thái đúng (Nhiệm vụ 2: engine chưa `On` hay chưa restart caddy; Nhiệm vụ 4: exclusion sai rule ID/phạm vi, hoặc tấn công thật không còn bị chặn).
