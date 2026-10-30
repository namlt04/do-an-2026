// Build Bao-cao-tuan-1.docx tu Mau.docx: giu nguyen trang bia + styles, thay noi dung.
// Chay: node build.js   (sau do update-fields.ps1 de Word cap nhat Muc luc / Danh muc hinh)
const fs = require('fs');
const path = require('path');
const JSZip = require('jszip');

const ROOT = path.resolve(__dirname, '..', '..');
const TEMPLATE = path.join(ROOT, 'Mẫu.docx');
const IMG_DIR = process.env.IMG_DIR || path.join(__dirname, '..', 'anh');
const OUT = process.env.OUT || path.join(__dirname, '..', 'Bao-cao-tuan-1.docx');

// ===== So lieu do thuc te (sua tai day neu chup lai) =====
const D = {
  vmIp: '192.168.17.144',
  l1: {
    email: 'namlt.b22at202@stu.ptit.edu.vn',
    baseline: '2 CRITICAL, 10 HIGH, 3 MEDIUM',
    tfsecSummary: '9 passed, 15 potential problem(s) detected',
    trivyBaseline: 'compute.tf: 2, network.tf: 1, storage.tf: 5',
    after: '0 CRITICAL, 0 HIGH (còn 2 MEDIUM, 1 LOW)',
    flag: 'b78b4cdac41c7e8e',
    checkwork: [['baseline_scan', 'Quét baseline IaC', 'Y'], ['fix_network_storage', 'Khắc phục lỗi mạng và lưu trữ', 'Y'],
      ['fix_secret_iam', 'Loại bỏ secret, siết quyền IAM', 'Y'], ['pass_gate', 'Bật logging, vượt CI gate', 'Y']],
  },
  l2: {
    email: 'minhnh.b22at190@stu.ptit.edu.vn',
    key: 'AKIA08c8b88901377b0c02b0',
    trivyOs: 'debian 10.2 — Total: 136 (HIGH: 109, CRITICAL: 27)',
    trivyPy: 'python-pkg — Total: 5 (HIGH: 5, CRITICAL: 0)',
    flag: '4e6b49a23959a1dd2384',
    checkwork: [['inspect_layers', 'Phân tích lịch sử layer', 'Y'], ['extract_secret', 'Trích xuất secret từ layer', 'Y'],
      ['scan_cves', 'Quét CVE bằng Trivy', 'Y'], ['get_flag', 'Lấy flag từ vault-svc', 'Y'],
      ['harden_image', 'Hardening Dockerfile', 'Y'], ['lab_complete', 'Hoàn thành toàn bộ bài', 'Y']],
  },
};

// ===== Noi dung =====
// h1/h2/h3: tieu de (danh so tu dong theo style); p: doan van (`code` inline); b: gach dau dong;
// code: khoi lenh; img: [file, chu thich]; table: {cols, widths, rows}
const C = [];
const h1 = t => C.push({ t: 'h1', v: t }), h2 = t => C.push({ t: 'h2', v: t }), h3 = t => C.push({ t: 'h3', v: t });
const p = t => C.push({ t: 'p', v: t }), b = (...a) => a.forEach(v => C.push({ t: 'b', v }));
const code = t => C.push({ t: 'code', v: t }), img = (f, cap) => C.push({ t: 'img', f, cap });
const table = (cols, widths, rows) => C.push({ t: 'table', cols, widths, rows });

h1('TỔNG QUAN NỘI DUNG TUẦN 1');
h2('Mục tiêu');
p('Trong tuần 1, nhóm thực hiện hai bài thực hành đầu tiên theo lộ trình kịch bản đã sắp xếp lại (từ cơ bản đến chuyên sâu) trên môi trường Labtainer, đóng vai trò sinh viên làm bài từ đầu đến cuối: khởi động bài lab, thực hiện lần lượt các nhiệm vụ theo hướng dẫn, lấy flag và chấm điểm tự động bằng `checkwork`. Toàn bộ quá trình được chụp ảnh màn hình làm minh chứng.');
h2('Phân công thực hiện');
table(['STT', 'Bài thực hành', 'Mã lab', 'Người thực hiện'], [700, 3700, 2000, 3068], [
  ['1', 'Bảo mật hạ tầng dưới dạng mã (IaC) — shift-left', 'dso-iac-scan', 'Lê Thành Nam — B22DCAT202'],
  ['2', 'Bảo mật Docker image — secret trong layer & CVE', 'dso-image-scan', 'Nguyễn Hồng Minh — B22DCAT190'],
]);
h2('Môi trường thực hiện');
b('Máy ảo Labtainer (VMware): Ubuntu 18.04, Docker 20.10.7, khoảng 3 GB RAM; các bài lab chạy trong các container cô lập, offline khi làm bài.',
  `Truy cập giao diện đồ họa của máy ảo trực tiếp trên trình duyệt web qua noVNC: x11vnc chia sẻ màn hình :0, websockify phục vụ noVNC tại cổng 6080 (\`http://${D.vmIp}:6080/vnc.html\`).`,
  'Mỗi sinh viên khởi động lab bằng email riêng; Labtainer dùng email này để sinh flag/khóa cá thể hóa (HASH_REPLACE), nên kết quả của mỗi người là khác nhau và không thể chép flag của nhau.');
img('l0_novnc.png', 'Màn hình máy ảo Labtainer hiển thị trên trình duyệt qua noVNC');

// ---------------- LAB 1 ----------------
h1('BÀI THỰC HÀNH 1: BẢO MẬT HẠ TẦNG DƯỚI DẠNG MÃ (DSO-IAC-SCAN)');
p('Người thực hiện: Lê Thành Nam — B22DCAT202 (email khởi động lab: ' + D.l1.email + ').');
h2('Mục đích');
b('Hiểu triết lý shift-left security: phát hiện và sửa lỗi cấu hình hạ tầng ngay ở giai đoạn viết mã Terraform, trước khi triển khai lên cloud.',
  'Nhận diện các misconfiguration kinh điển trong IaC: Security Group mở 0.0.0.0/0, S3 công khai/không mã hóa, secret hardcode, IAM policy quá rộng, thiếu logging.',
  'Sử dụng công cụ quét tĩnh `tfsec`, `trivy config` để phân loại rủi ro theo mức độ nghiêm trọng và kiểm chứng kết quả khắc phục.');
h2('Môi trường bài lab');
b('Container `devsecops` (172.31.0.10, có terminal): chứa thư mục `~/iac-project` (mã Terraform cần review) và script `~/gate.sh`; cài sẵn tfsec, trivy, terraform, git, jq.',
  'Container `ci` (172.31.0.20, không có terminal): dịch vụ quality gate tại cổng 8000, tự quét lại độc lập mã Terraform nhận được và chỉ trả flag khi số lỗi HIGH/CRITICAL bằng 0.',
  'Bài lab là phân tích tĩnh, offline: không chạy `terraform apply`, không kết nối cloud thật.');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
p('Tại terminal Labtainer trên máy ảo, chạy lệnh khởi động và nhập email của sinh viên. Labtainer tạo 2 container và mở terminal của container `devsecops`.');
code('labtainer -r dso-iac-scan');
img('l1_01_start.png', 'Khởi động bài lab dso-iac-scan với email sinh viên');
h3('Nhiệm vụ 1 — Quét baseline và phân loại rủi ro');
p('Khởi tạo Terraform (offline, dùng provider mirror có sẵn), kiểm tra cú pháp, sau đó quét toàn bộ dự án bằng tfsec và trivy để lấy báo cáo ban đầu.');
code('cd ~/iac-project\nterraform init -backend=false\nterraform validate');
img('l1_02_init.png', 'Khởi tạo và kiểm tra cấu hình Terraform');
code('tfsec .');
img('l1_03_tfsec.png', `Kết quả quét baseline bằng tfsec: ${D.l1.tfsecSummary}`);
code(`tfsec . --format json --out ~/baseline.json\ngrep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/baseline.json | sort | uniq -c`);
img('l1_04_baseline.png', 'Thống kê số lỗi baseline theo mức độ nghiêm trọng');
p(`Baseline ghi nhận ${D.l1.baseline}. Quét bổ sung bằng trivy cho kết quả theo từng file (${D.l1.trivyBaseline} lỗi), trong đó có AWS-0028 (EC2 chưa bắt buộc IMDSv2).`);
code('trivy config --severity HIGH,CRITICAL .');
img('l1_05_trivy.png', 'Kết quả quét cấu hình bằng trivy config');
h3('Nhiệm vụ 2 — Khắc phục lỗi mạng và lưu trữ');
p('Tìm các rule mở toàn bộ Internet và cấu hình S3 không an toàn:');
code('grep -rniE "0.0.0.0/0" ~/iac-project\ngrep -rniE "acl|public|encryption|versioning" ~/iac-project/storage.tf');
img('l1_06_net_storage_findings.png', 'Phát hiện Security Group mở 0.0.0.0/0 và S3 public');
p('Sửa `network.tf`: SSH (22) và MySQL (3306) chỉ cho phép từ dải quản trị nội bộ 10.0.0.0/16, egress giới hạn trong VPC. Sửa `storage.tf`: bật đủ 4 cờ `aws_s3_bucket_public_access_block` = true, mã hóa phía máy chủ AES256, bật versioning và access logging. Bổ sung `logging.tf`: bucket log riêng, CloudWatch log group và VPC flow log.');
img('l1_07_fix_network_diff.png', 'git diff thể hiện thay đổi Security Group');
code('terraform validate\ntfsec . --minimum-severity HIGH');
img('l1_08_after_task2.png', 'Quét lại sau khi khắc phục nhóm lỗi mạng và lưu trữ');
h3('Nhiệm vụ 3 — Loại bỏ secret hardcode và siết quyền IAM');
code('grep -rniE "password|secret|access_key|private_key|token" ~/iac-project');
img('l1_09_secret_findings.png', 'Phát hiện mật khẩu và secret key hardcode trong variables.tf');
p('Trong `variables.tf`, bỏ giá trị mặc định của `db_password` và `aws_secret_key`, đánh dấu `sensitive = true` (giá trị được cấp lúc chạy qua biến môi trường/secret manager). Trong `iam.tf`, thay policy `Action = "*"`, `Resource = "*"` bằng quyền tối thiểu `s3:GetObject`, `s3:PutObject` trên đúng bucket ứng dụng. Đồng thời sửa `compute.tf`: bắt buộc IMDSv2 (`http_tokens = "required"`) và mã hóa ổ đĩa gốc.');
img('l1_10_fix_secret_iam_diff.png', 'git diff thể hiện việc loại bỏ secret và áp dụng least-privilege IAM');
h3('Nhiệm vụ 4 — Quét lại toàn diện và vượt cổng chặn CI');
code(`terraform validate\ntfsec . --format json --out ~/after.json\ngrep -oE '"severity":[[:space:]]*"[A-Z]+"' ~/after.json | sort | uniq -c`);
img('l1_11_after_scan.png', 'So sánh số lỗi trước và sau khi khắc phục');
p(`Sau khi khắc phục: ${D.l1.after}. Gửi mã tới cổng chặn CI; dịch vụ ci tự quét lại độc lập, xác nhận HIGH=0, CRITICAL=0, trả về GATE PASSED và flag cá thể hóa.`);
code('~/gate.sh\ncat ~/flag.txt');
img('l1_12_gate_flag.png', `Vượt CI quality gate và nhận flag ${D.l1.flag}`);
h2('Kết quả thực hiện');
p('Chạy `checkwork dso-iac-scan` tại terminal Labtainer để chấm điểm tự động:');
img('l1_13_checkwork.png', 'Kết quả chấm điểm tự động bài dso-iac-scan');
table(['Mục tiêu (goal)', 'Nội dung', 'Kết quả'], [3000, 5000, 1468], D.l1.checkwork);
p(`Kết quả: hoàn thành ${D.l1.checkwork.filter(r => r[2] === 'Y').length}/${D.l1.checkwork.length} mục tiêu; số lỗi HIGH/CRITICAL giảm từ 12 xuống 0; flag ${D.l1.flag}.`);

// ---------------- LAB 2 ----------------
h1('BÀI THỰC HÀNH 2: BẢO MẬT DOCKER IMAGE (DSO-IMAGE-SCAN)');
p('Người thực hiện: Nguyễn Hồng Minh — B22DCAT190 (email khởi động lab: ' + D.l2.email + ').');
h2('Mục đích');
b('Hiểu tính bất biến của layer Docker: lệnh `RUN rm` ở layer sau chỉ che file, dữ liệu ở layer trước vẫn còn trong image.',
  'Trích xuất secret bị lộ từ layer bằng `docker save`, quét lỗ hổng (CVE) của image bằng Trivy ở chế độ offline.',
  'Chứng minh tác động: dùng secret lộ để truy cập dịch vụ nội bộ; sau đó hardening image bằng multi-stage build, `.dockerignore` và user không phải root.');
h2('Môi trường bài lab');
b('Container `workstation` (172.36.0.10, có terminal): chạy Docker daemon lồng bên trong, chứa image mẫu `internal-app:1.0` (được build lúc khởi động từ mã có secret cá thể hóa, sau đó thư mục build bị xóa để sinh viên chỉ có thể lấy secret từ layer).',
  'Container `vault-svc` (172.36.0.20:8080, không có terminal): API nội bộ trả flag khi nhận đúng API key.',
  'Trivy có sẵn cơ sở dữ liệu lỗ hổng, base image `python:3.8.0-slim` được nạp sẵn để build offline.');
h2('Nội dung thực hành');
h3('Khởi động bài lab');
code('labtainer -r dso-image-scan\ndocker images');
img('l2_01_start.png', 'Khởi động bài lab dso-image-scan và liệt kê image');
h3('Nhiệm vụ 1 — Phân tích lịch sử layer');
code('docker history --no-trunc internal-app:1.0 | tee ~/findings.txt');
img('l2_02_history.png', 'Lịch sử layer: COPY .env, COPY secrets/aws-credentials.txt rồi RUN rm');
p('Lịch sử cho thấy hai layer COPY đưa `.env` và `secrets/aws-credentials.txt` vào image, sau đó một layer `RUN rm -f ...` xóa chúng. Do layer là bất biến, nội dung file vẫn nằm trong layer COPY.');
h3('Nhiệm vụ 2 — Trích xuất secret từ layer');
code(`docker save internal-app:1.0 -o ~/image.tar\nmkdir -p ~/layers && tar -xf ~/image.tar -C ~/layers\ncd ~/layers && for l in blobs/sha256/*; do tar -tf $l 2>/dev/null | grep -E '\\.env|secrets' && echo "  <- $l"; done`);
p(`Image được xuất theo định dạng OCI (các layer nằm trong \`blobs/sha256/\`). Giải nén layer chứa \`app/secrets/aws-credentials.txt\` thu được khóa \`${D.l2.key}\` (bắt đầu bằng AKIA, cá thể hóa theo sinh viên) và lưu vào \`~/secret.txt\`.`);
img('l2_03_extract_secret.png', 'Trích xuất credential còn sót trong layer image');
h3('Nhiệm vụ 3 — Quét CVE bằng Trivy');
code('trivy image --offline-scan --severity HIGH,CRITICAL internal-app:1.0 | tee ~/cve-report.txt');
img('l2_04_trivy.png', 'Kết quả quét lỗ hổng image bằng Trivy (offline)');
p(`Kết quả: hệ điều hành ${D.l2.trivyOs}; thư viện ${D.l2.trivyPy}. Base image cũ (python:3.8.0-slim, Debian 10.2) là nguồn chính của các lỗ hổng.`);
h3('Nhiệm vụ 4 — Dùng secret lấy flag từ vault-svc');
code('curl -s -H "Authorization: Bearer $(cat ~/secret.txt)" http://vault-svc:8080/flag | jq -r .flag | tee ~/flag_result.txt');
img('l2_05_flag.png', `Dùng khóa bị lộ để lấy flag ${D.l2.flag} từ vault-svc`);
p('Chuỗi tấn công: image phân phối nội bộ → secret còn trong layer → gọi API nội bộ bằng khóa hợp lệ → lấy được dữ liệu bí mật. Gửi khóa sai, dịch vụ trả về lỗi 403.');
h3('Nhiệm vụ 5 — Hardening image');
p('Viết lại `~/Dockerfile.secure` theo multi-stage build (2 lệnh FROM), chỉ copy mã nguồn sạch từ `~/app-src`, tạo và chạy bằng user `appuser` (không phải root); tạo `~/.dockerignore` loại `.env` và `secrets/`. Build lại offline và kiểm tra lịch sử layer không còn bước COPY secret.');
code('FROM python:3.8.0-slim AS build\nWORKDIR /src\nCOPY app-src/ /src/\n\nFROM python:3.8.0-slim\nWORKDIR /app\nCOPY --from=build /src/app.py /src/requirements.txt /app/\nRUN useradd -r -u 10001 appuser && chown -R appuser /app\nUSER appuser\nCMD ["python", "app.py"]');
code('docker build --network none -f Dockerfile.secure -t internal-app:secure .\ndocker history internal-app:secure');
img('l2_06_harden.png', 'Build image đã hardening và kiểm tra lịch sử layer');
h2('Kết quả thực hiện');
p('Chạy `checkwork dso-image-scan` tại terminal Labtainer để chấm điểm tự động:');
img('l2_07_checkwork.png', 'Kết quả chấm điểm tự động bài dso-image-scan');
table(['Mục tiêu (goal)', 'Nội dung', 'Kết quả'], [3000, 5000, 1468], D.l2.checkwork);
p(`Kết quả: hoàn thành ${D.l2.checkwork.filter(r => r[2] === 'Y').length}/${D.l2.checkwork.length} mục tiêu; flag ${D.l2.flag}.`);

// ---------------- KET LUAN ----------------
h1('KẾT LUẬN');
h2('Kết quả đạt được');
b('Cài đặt noVNC trên máy ảo Labtainer, cho phép thao tác và trình chiếu bài lab trực tiếp trên trình duyệt web.',
  'Hoàn thành bài 1 (dso-iac-scan): checkwork 4/4 mục tiêu đạt, vượt CI quality gate với 0 lỗi HIGH/CRITICAL.',
  'Hoàn thành bài 2 (dso-image-scan): checkwork 6/6 mục tiêu đạt, trích xuất được secret từ layer, quét CVE offline, lấy flag và hardening image.');
h2('Khó khăn và cách khắc phục');
p('Bản nháp bài 2 khi build và chạy thử phát sinh một số lỗi, đã được sửa và kiểm thử lại (rebuild sạch, chấm điểm khi chưa làm ra N, làm xong ra Y):');
b('Phiên bản Trivy v0.57.1 không còn bản phát hành (404) → chuyển sang v0.74.0, nạp sẵn CSDL lỗ hổng để chạy offline; thư mục cache cấp quyền ghi cho sinh viên.',
  '`str.removeprefix` không có trên Python 3.8 của vault-svc → thay bằng xử lý chuỗi tương thích.',
  'File `.env` chưa được cá thể hóa khóa → bổ sung vào HASH_REPLACE để khớp với credential.',
  'Thư mục build chứa secret nằm ngay trong home của sinh viên (có thể đọc trực tiếp, bỏ qua bài) → xóa sau khi build image; build offline bằng base image nạp sẵn.',
  'Script trong `_bin` nằm ở `~/.local/bin` chứ không phải `~/_bin`; thiếu file placeholder cho goal flag khiến grader lỗi khi chưa làm bài; file có ký tự xuống dòng CRLF → đã sửa toàn bộ.',
  '`docker save` trên Docker mới xuất định dạng OCI; terminal sinh viên của Labtainer đặt `IFS=\' \'` nên vòng lặp `for l in $(...)` không tách dòng → hướng dẫn duyệt layer bằng glob `blobs/sha256/*`.',
  'Lệnh `su -` mở terminal sinh viên xóa biến môi trường của Dockerfile khiến Trivy tự tải CSDL từ Internet → khai báo biến `TRIVY_*` trong `/etc/profile.d/trivy.sh` để chạy offline.');

// ===== XML helpers =====
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const MONO = '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>';
const run = (t, rpr = '') => `<w:r>${rpr ? `<w:rPr>${rpr}</w:rPr>` : ''}<w:t xml:space="preserve">${esc(t)}</w:t></w:r>`;
const inline = t => t.split(/(`[^`]+`)/).filter(Boolean).map(s =>
  s.startsWith('`') ? run(s.slice(1, -1), MONO + '<w:sz w:val="24"/>') : run(s)).join('');
const para = (style, inner, extra = '') => `<w:p><w:pPr><w:pStyle w:val="${style}"/>${extra}</w:pPr>${inner}</w:p>`;
const NEWPAGE = '<w:pageBreakBefore/>';
const field = (style, instr, ppr = '') =>
  `<w:p><w:pPr><w:pStyle w:val="${style}"/>${ppr}</w:pPr><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve">${instr}</w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>${run('Nhấn chuột phải → Update Field để cập nhật.')}<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>`;

const TEXT_W_EMU = Math.round((11907 - 1021 - 1418) / 1440 * 914400) - 60000;
function pngSize(buf) { return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) }; }

async function main() {
  const zip = await JSZip.loadAsync(fs.readFileSync(TEMPLATE));
  let doc = await zip.file('word/document.xml').async('string');
  let rels = await zip.file('word/_rels/document.xml.rels').async('string');

  const bodyStart = doc.indexOf('<w:body>') + '<w:body>'.length;
  const tocTitle = doc.indexOf('MỤC LỤC</w:t>');
  const cut = doc.lastIndexOf('<w:p ', tocTitle);
  const lastSect = doc.lastIndexOf('<w:sectPr');
  const head = doc.slice(0, cut), tail = doc.slice(lastSect);
  if (!head.includes('<w:sectPr') || cut < bodyStart) throw new Error('Khong tim thay ranh gioi trang bia');

  let rid = 900, docPr = 5000, figs = 0, missing = [];
  const media = [];
  const out = [];
  out.push(para('BTL-H0', run('MỤC LỤC')));
  out.push(field('TOC1', ' TOC \\h \\z \\u \\t "BTL-H1,1,BTL-H2,2,BTL-H3,3,BTL-H0,1" '));
  out.push(para('BTL-H0', run('DANH MỤC CÁC HÌNH VẼ'), NEWPAGE));
  out.push(field('TableofFigures', ' TOC \\f F \\h \\z \\t "BTL-Hinh" \\c ', '<w:tabs><w:tab w:val="right" w:leader="dot" w:pos="9458"/></w:tabs>'));

  for (const c of C) {
    if (c.t === 'h1') out.push(para('BTL-H1', run(c.v), NEWPAGE));
    else if (c.t === 'h2') out.push(para('BTL-H2', run(c.v)));
    else if (c.t === 'h3') out.push(para('BTL-H3', run(c.v)));
    else if (c.t === 'p') out.push(para('BTL-Text', inline(c.v)));
    else if (c.t === 'b') out.push(para('BTL-Bullet1', inline(c.v)));
    else if (c.t === 'code') {
      const lines = c.v.split('\n');
      const inner = lines.map((l, i) => (i ? '<w:r><w:br/></w:r>' : '') + run(l, MONO + '<w:sz w:val="20"/>')).join('');
      out.push(para('BTL-Text', inner, '<w:keepNext/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/><w:spacing w:before="60" w:after="120" w:line="240" w:lineRule="auto"/><w:ind w:left="284" w:firstLine="0"/><w:jc w:val="left"/>'));
    } else if (c.t === 'img') {
      const fp = path.join(IMG_DIR, c.f);
      const center = '<w:keepNext/><w:spacing w:before="120" w:after="0"/><w:ind w:firstLine="0"/><w:jc w:val="center"/>';
      if (fs.existsSync(fp)) {
        const buf = fs.readFileSync(fp), { w, h } = pngSize(buf);
        const cx = TEXT_W_EMU, cy = Math.round(cx * h / w), id = 'rId' + (++rid), n = ++docPr;
        const name = `rpt_${c.f}`;
        media.push({ name, buf, id });
        out.push(para('BTL-Text', `<w:r><w:rPr><w:noProof/></w:rPr><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="${cx}" cy="${cy}"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="${n}" name="${esc(c.f)}"/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="${n}" name="${esc(c.f)}"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="${id}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>`, center));
      } else {
        missing.push(c.f);
        out.push(para('BTL-Text', run(`[Chèn ảnh: ${c.f}]`, '<w:color w:val="C00000"/><w:b/>'), center));
      }
      figs++;
      out.push(para('BTL-Hinh', run(c.cap)));
    } else if (c.t === 'table') {
      const total = c.widths.reduce((a, x) => a + x, 0);
      const cell = (txt, w, hdr) => `<w:tc><w:tcPr><w:tcW w:w="${w}" w:type="dxa"/>${hdr ? '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>' : ''}<w:vAlign w:val="center"/></w:tcPr>${para('BTL-Text', hdr ? run(txt, '<w:b/>') : inline(txt), '<w:spacing w:before="40" w:after="40"/><w:ind w:firstLine="0"/><w:jc w:val="' + (hdr ? 'center' : 'left') + '"/>')}</w:tc>`;
      const row = (r, hdr) => `<w:tr>${r.map((x, i) => cell(x, c.widths[i], hdr)).join('')}</w:tr>`;
      out.push(`<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="${total}" w:type="dxa"/><w:jc w:val="center"/><w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr><w:tblGrid>${c.widths.map(x => `<w:gridCol w:w="${x}"/>`).join('')}</w:tblGrid>${row(c.cols, true)}${c.rows.map(r => row(r, false)).join('')}</w:tbl>`);
      out.push(para('BTL-Text', ''));
    }
  }
  out.push(para('BTL-H0', run('TÀI LIỆU THAM KHẢO'), NEWPAGE));
  for (const r of [
    'Labtainers — Lab Designer User Guide, Naval Postgraduate School (https://github.com/mfthomps/Labtainers).',
    'Aqua Security — tfsec documentation (https://aquasecurity.github.io/tfsec/).',
    'Aqua Security — Trivy documentation (https://trivy.dev/).',
    'Docker Docs — Dockerfile best practices, multi-stage builds (https://docs.docker.com/build/building/best-practices/).',
    'CIS Docker Benchmark; OWASP Infrastructure as Code Security Cheat Sheet; MITRE ATT&CK T1552 — Unsecured Credentials.',
  ]) out.push(para('BTL-NumerRef', run(r), '<w:jc w:val="left"/>'));

  doc = head + out.join('') + tail;

  // anh moi: them rels + media; bo anh mau khong con dung
  for (const m of media) {
    zip.file(`word/media/${m.name}`, m.buf);
    rels = rels.replace('</Relationships>', `<Relationship Id="${m.id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${m.name}"/></Relationships>`);
  }
  const used = new Set([...doc.matchAll(/r:(?:embed|id|link)="([^"]+)"/g)].map(m => m[1]));
  rels = rels.replace(/<Relationship [^>]*Type="[^"]*\/image"[^>]*\/>/g, rel => {
    const id = rel.match(/Id="([^"]+)"/)[1], tgt = rel.match(/Target="([^"]+)"/)[1];
    if (used.has(id)) return rel;
    zip.remove('word/' + tgt);
    return '';
  });
  zip.file('word/document.xml', doc);
  zip.file('word/_rels/document.xml.rels', rels);
  const ct = await zip.file('[Content_Types].xml').async('string');
  if (!/Extension="png"/i.test(ct)) zip.file('[Content_Types].xml', ct.replace('<Default ', '<Default Extension="png" ContentType="image/png"/><Default '));

  fs.writeFileSync(OUT, await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
  console.log(`OK ${OUT}\n  hinh: ${figs}, da chen: ${media.length}, thieu: ${missing.length ? missing.join(', ') : 'khong'}`);
}
main().catch(e => { console.error(e); process.exit(1); });
