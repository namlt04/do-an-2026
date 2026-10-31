# Rà soát GUI (vai trò sinh viên) - Lab 3 → 10 - 2026-11-01

Thực hiện lab theo **đúng hướng dẫn trong guide**, thao tác qua **noVNC** trên
terminal học viên (không chạy solver), chạy `checkwork` sau mỗi bài để xác nhận
"sinh viên làm theo guide có thực sự làm được không".

Máy lab: VMware Labtainer VM, hiển thị qua noVNC (x11vnc + websockify :6080).

## Tổng kết

| # | Lab | checkwork | Ghi chú |
|---|-----|-----------|---------|
| 3 | dso-secrets-git     | 16/16 Y | OK. Fix storage systemd (commit 7930161) sống lại sau restart - đã xác nhận |
| 4 | dso-supplychain-sca | 5/5 Y   | OK. Chạy offline hoàn toàn (syft, trivy --offline-scan, npm install từ cache) |
| 5 | cloud-s3-misconfig  | 5/5 Y   | OK |
| 6 | dso-waf-crs         | 5/5 Y   | PASS chức năng, NHƯNG có lỗi guide (xem bên dưới) |
| 7 | cloud-ssrf-imds     | 10/10 Y | OK (ERROR CreateSubnets lúc start vô hại) |
| 8 | dso-cicd-jenkins    | 6/6 Y   | OK. Jenkins thật 2.462.3, RCE Script Console thật |
| 9 | dso-docker-escape   | 6/6 Y   | OK |
| 10| cloud-k8s-rbac      | 5/5 Y   | OK. k3s thật v1.29.6+k3s2, flag hash per-student |

Flag minh chứng lấy được (sinh viên namlt.b22at202@stu.ptit.edu.vn):
- Lab 3: storage `9196d3bf1fca04c42eeb`, API `99dd917cc01739de0884`
- Lab 4: `b920868a213641b084fd` (EJS CVE-2022-29078 RCE)
- Lab 5: `daec4f9f6f053222fb55d99c`
- Lab 6: flag2 `0b9bc41358207e95`, flag3 `3d78090ce6ff1e9a`
- Lab 7: `1abf1851b680c989`
- Lab 8: flag_ci `9b2c723ecd6344d3`, flag_pivot `5e622307a8d09bec`
- Lab 9: hostmarker `bf06603e0be2471146c3`, flag `1d5cd1864f434e4a`
- Lab 10: `e200a6d4d36d0165`

## LỖI CẦN SỬA

### Lab 6 (dso-waf-crs) - NGHIÊM TRỌNG: lệnh đọc audit log sai format

Guide viết lệnh đọc audit log theo format **ModSecurity native**
(`id "9xxxxx"`, `Access denied`, `anomaly`, grep `"403"`), nhưng sau khi chuyển
sang **Caddy + Coraza**, audit log là **JSON** (`SecAuditLogFormat JSON`).
Rule ID nằm trong `messages[].error_message` dưới dạng chuỗi **có escape**:
`[id \"942190\"]`. Vì vậy các lệnh grep trong guide **không khớp gì cả**.

Ảnh hưởng:
- NV2 Bước 7: `grep -E 'id "9[0-9]{5}"|Access denied|anomaly'` -> rỗng.
- NV3 Bước 4: `grep -c "Access denied\|403"` -> 0.
- NV4 Bước 2: tìm RULE_ID để viết exclusion -> **sinh viên không lấy được rule ID**,
  không hoàn thành được NV4 theo đúng guide (dù cơ chế flag3 vẫn chấm đúng qua
  hành vi thật, nên lab vẫn PASS nếu đoán đúng rule).

Lệnh ĐÚNG cho Coraza JSON (đã kiểm chứng, không cần jq):
```bash
# Lấy rule ID đã khớp (ví dụ với /feedback):
sudo grep feedback /var/log/coraza/audit.log | grep '"messages"' | tail -1 \
  | grep -oE 'id \"[0-9]+\"' | grep -oE '[0-9]+' | sort -u
```
Kết quả thực tế với benign feedback (UNION/SELECT/ORDER BY): `920350 942190 949110`
(942190 = SQLi, cần loại cho ARGS:comment; 949110 = anomaly blocker, giữ nguyên).

Exclusion khoanh vùng đã kiểm chứng (benign->200, XSS->403, flag3 ra):
```apache
SecRule REQUEST_URI "@beginsWith /feedback" \
  "id:100001,phase:1,pass,nolog,ctl:ruleRemoveTargetById=942190;ARGS:comment"
```

### Lab 6 - phụ

- Mô tả trong `goals.config` còn chữ **"ModSecurity"** (deploy_waf: "bat ModSecurity
  blocking...") - nên đổi thành Coraza (hiện ra trong output checkwork).
- `dast_compare`: biên độ mỏng (nikto noWAF=4 vs WAF=3). Qua được nhờ `c_waf < c_direct`,
  nhưng nikto có yếu tố ngẫu nhiên + timeout -> có lần có thể không chênh. Cân nhắc
  thêm điều kiện chắc hơn (đếm 403 trong report WAF).

### Lab 10 (cloud-k8s-rbac) - robustness inotify

k8s-node (systemd PID 1) **crash lúc init** với lỗi
`Failed to create control group inotify object: Too many open files` khi
`fs.inotify.max_user_instances` của VM thấp (mặc định VM này = **128**) và/hoặc
chạy đồng thời nhiều container systemd.

Hậu quả dây chuyền: k8s-node chết -> framework **không chạy HASH_REPLACE** ->
`/opt/host-secrets/flag.txt` giữ nguyên seed `K8SFLAGSEED` (giá trị cố định,
đoán được, lộ trong repo) thay vì hash per-student -> phá cơ chế chống bypass,
và `escape_node` sẽ fail do flag không khớp parameter.k8sflag.

Khắc phục đã làm trên VM: `sudo sysctl -w fs.inotify.max_user_instances=1024
fs.inotify.max_user_watches=1048576`. Sau đó lab chạy đúng (flag hash
`e200a6d4d36d0165`, checkwork 5/5).

Đề xuất: đặt sysctl inotify trong init của lab (hoặc tài liệu prerequisite của VM),
vì default 128 là rủi ro khi lab dùng systemd-in-container.

### Lab 10 - phụ

- NV2 (`loot_secrets`): hướng dẫn "Lưu kết quả vào ~/loot.txt" chỉ nằm ở phần
  **văn xuôi**, không có trong code block. Grader yêu cầu `~/loot.txt` chứa
  `legacy_api_key` + password -> nên thêm redirect `| tee ~/loot.txt` vào code block.

## Lưu ý vận hành (không phải lỗi lab)

- `labtainer -r <lab>` **không tự dừng** các lab đã mở trước đó -> container tích lũy,
  ăn hết RAM/inotify. Nên `stoplab <lab>` giữa các bài khi test nhiều lab liên tiếp.
- VM chỉ có ~2.9GB RAM; chạy đồng thời nhiều lab gây OOM/thiếu inotify. Test từng lab một.
