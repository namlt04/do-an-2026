# BUILD-NOTES — cloud-s3-misconfig

Ghi chú build/test, quyết định thiết kế và rủi ro. Viết bởi subagent xây lab,
**chưa build/chưa chạy trên VM** (nhiệm vụ này chỉ yêu cầu viết file nguồn).
Người build thật (trên `student@192.168.17.139`, xem LAB-BUILD-RULES.md) cần
đi qua checklist §8 của LAB-BUILD-RULES.md trước khi coi bài là "xong".

## 1. File đã tạo / cập nhật

```
labs/cloud-s3-misconfig/
├── config/
│   ├── start.config          [ghi đè scaffold] mạng 172.33.0.0/24 gw .101, client .10
│   │                          TERMINALS 1 (GRADE_CONTAINER), storage .30 TERMINALS -1
│   │                          SCRIPT NONE, LAB_MASTER_SEED cloud-s3-misconfig_ptit_seed
│   ├── parameter.config      [ghi đè scaffold] 5 dòng HASH_REPLACE (xem mục 3)
│   ├── about.txt             [mới]
│   └── keywords.txt          [mới]
├── dockerfiles/
│   ├── Dockerfile.cloud-s3-misconfig.client.student   [điền] aws-cli v1 (pip) + mc + jq/curl
│   └── Dockerfile.cloud-s3-misconfig.storage.student  [điền] minio + mc binary, /data/minio
├── client/
│   ├── hardening-admin.env   [mới] credential hardening cấp sẵn cho NV4 (token HASH_REPLACE)
│   └── _bin/fixlocal.sh      [điền] chmod credential, mkdir loot/, ~/.aws/config mặc định
├── storage/
│   ├── seed/*.token          [mới] 5 file placeholder cho HASH_REPLACE (xem mục 3)
│   ├── _system/etc/systemd/system/minio.service  [mới] unit systemd chạy MinIO
│   └── _bin/fixlocal.sh      [điền] start MinIO, tạo 2 bucket, seed dữ liệu/policy/user, seed flag
├── instr_config/
│   ├── results.config        [điền] 7 result (whole-file) trên client
│   ├── goals.config           [điền] 5 goal: enum_anonymous, exfiltrate_backup,
│   │                          access_secure_bucket, harden_public_denied,
│   │                          harden_versioning_enabled
│   └── pregrade.sh            [điền] chuẩn hoá (trim CRLF/space) các file bằng chứng trên client
├── docs/
│   ├── cloud-s3-misconfig-guide.md  [mới] hướng dẫn PTIT đầy đủ — CHỈ .md theo yêu cầu
│   │                                 (không sinh .docx trong lượt này, xem mục 6)
│   └── read_first.txt         [cập nhật] trỏ tới guide .md + nhắc endpoint MinIO
├── solver.sh                  [mới] lời giải mẫu end-to-end (không phát cho SV)
└── BUILD-NOTES.md             [mới] file này
```

Scaffold gốc (build-glue) được giữ nguyên cấu trúc ARG/ADD/USER/CMD như
`new_lab_setup.py` sinh ra; chỉ chèn thêm các dòng `RUN` cài gói trước dòng
`USER $user_name`, đúng quy tắc §3.

## 2. Mạng & container

Dùng đúng dải mạng đã "chốt" trong LAB-BUILD-RULES.md §2 (bảng phân bổ) và theo
yêu cầu của người giao việc: `172.33.0.0/24` gw `172.33.0.101`, mạng tên
`LAB_NET`. `client` `172.33.0.10` (TERMINALS 1, GRADE_CONTAINER), `storage`
`172.33.0.30` (TERMINALS -1, `SCRIPT NONE` vì chạy systemd thật cho
`minio.service`, theo đúng mẫu đã dùng ở `dso-secrets-git/storage`).

**Lưu ý:** file spec gốc `06-cloud-s3-misconfig.md` (mục "Sơ đồ mạng") dùng dải
`172.60.2.0/24` — đây là bản nháp minh hoạ nội dung, đã bị **ghi đè** bởi bảng
phân bổ mạng chính thức trong LAB-BUILD-RULES.md §2 và theo đúng yêu cầu tường
minh của người giao việc (172.33.0.0/24). `docs/cloud-s3-misconfig-guide.md` và
`solver.sh` đã được viết lại theo địa chỉ 172.33.0.10 / 172.33.0.30.

`client` có `WAIT_FOR storage` để đảm bảo MinIO đã seed xong (bucket/policy/
credential/flag) trước khi sinh viên mở terminal.

## 3. Cơ chế flag + credential lộ (2 bucket)

Thiết kế đúng 2 bucket theo yêu cầu (thay vì 3 bucket như một biến thể trong
spec): `public-assets` (public, chứa cả file tĩnh lẫn backup) và `secure-data`
(private, chứa flag). Đây là biến thể "gộp backup vào public-assets" mà chính
spec gốc đã liệt kê là lựa chọn hợp lệ.

5 giá trị `HASH_REPLACE` (per-student, sinh từ `LAB_MASTER_SEED` +
email SV + seed_string riêng mỗi tham số):

| Param | Vị trí token (trước khi thay) | Dùng để |
|---|---|---|
| `leak_access_key` | `storage:/home/ubuntu/seed/leaked_access_key.token` | Access key **bị lộ** qua backup trong `public-assets` |
| `leak_secret_key` | `storage:/home/ubuntu/seed/leaked_secret_key.token` | Secret key **bị lộ** qua backup trong `public-assets` |
| `s3flag` | `storage:/home/ubuntu/seed/flag.token` | Flag — nội dung object `secure-data/confidential/flag.txt` |
| `harden_access_key` | `client:...hardening-admin.env` **và** `storage:...harden_access_key.token` (cùng 1 token, cú pháp multi-file của HASH_REPLACE) | Access key **cấp sẵn** cho NV4 (hardening) |
| `harden_secret_key` | tương tự, 2 file (client + storage) | Secret key cấp sẵn cho NV4 |

`storage/_bin/fixlocal.sh` chạy SAU khi parameterization thay token xong: đọc 5
file `~/seed/*.token` đã có giá trị thật, dùng để (a) tạo user MinIO ứng với
credential lộ (chỉ có quyền `GetObject`/`ListBucket` trên `secure-data`), (b)
nhúng đúng cặp key đó vào `backup/app-config.env` trong `public-assets`, (c)
tạo object flag trong `secure-data`, (d) tạo user MinIO thứ hai ứng với
credential hardening (chỉ có quyền sửa bucket policy/versioning trên 2 bucket
của bài — không phải root, không đọc được object). Sau khi seed xong, các file
`.token` bị xoá khỏi đĩa `storage` (dù sinh viên vốn cũng không có shell ở đó).

**Vì sao không cat/`.bash_history` ra flag được:** flag nằm trong object trên
`storage` (TERMINALS -1). Muốn tải object đó, MinIO đòi hỏi access/secret key
hợp lệ — chỉ có được bằng cách thực sự tải + giải nén backup từ bucket public
rồi trích đúng 2 giá trị. Goal `access_secure_bucket` so khớp CHÍNH XÁC
(`string_equal`) nội dung `~/loot.txt` với `parameter.s3flag` (giá trị hash
thật, không đoán được); goal `exfiltrate_backup` so khớp chính xác 2 file
credential trích xuất với `parameter.leak_access_key`/`leak_secret_key` — sinh
viên không thể "gõ bừa" một chuỗi vì phải khớp tuyệt đối với giá trị ngẫu
nhiên riêng của mình.

**Credential hardening (NV4) tách biệt khỏi credential lộ:** đúng như gợi ý
trong mục "Ghi chú triển khai" của spec gốc ("cấp riêng cho Nhiệm vụ 4 qua một
user hardening có quyền PutBucketPolicy/DeleteBucketPolicy") — tránh việc NV4
phải dùng lại credential chỉ có quyền đọc (không đủ quyền sửa policy), đồng
thời mỗi sinh viên có một cặp key hardening khác nhau (không thể chia sẻ lệnh
nguyên văn cho nhau).

**"Rotate" credential đã lộ:** theo yêu cầu, đã đưa vào goal hardening đo được
(`harden_public_denied`, `harden_versioning_enabled`); việc "rotate" cụ thể
được đặt ở mức Bước 5 (khuyến nghị) + Câu hỏi 4 (tư duy), KHÔNG chấm điểm tự
động bằng MinIO admin API (`mc admin user disable`) — quyết định có chủ đích
để tránh phụ thuộc vào các action `admin:*` của MinIO (khác cơ chế IAM S3
chuẩn dùng cho phần còn lại của bài) chưa được kiểm chứng khi không thể build/
test trong nhiệm vụ này. Có thể bổ sung sau nếu build-test xác nhận ổn.

## 4. Rủi ro cần build-test xác nhận (KHÔNG build trong nhiệm vụ này)

1. **Cú pháp `instr_config/goals.config` / `results.config`:** tài liệu tham
   khảo có sẵn trong repo (`_ref-labtainer-designer.txt`) bị cắt trước mục 6
   (Automated assessment), nên không có ví dụ "chính thức" đầy đủ cho từ khoá
   `<field>` trong dạng `name = <container>:<file> : <field> : <OP> : <value>`
   của results.config, hay từ khoá khai báo goal (có cần tiền tố như `GOAL`
   không). Đã thiết kế để **né hoàn toàn** phần chưa chắc chắn này: chỉ dùng
   dạng "toàn bộ nội dung file" (`name = container:file`, độ tin cậy cao) kết
   hợp `matchany : string_equal` / `boolean` — đúng y nguyên các ví dụ có
   trong LAB-BUILD-RULES.md §5. Trước khi `rebuild` thật, đối chiếu lại với
   `labs/telnetlab`, `labs/nmap-ssh`, `labs/capabilities` trên máy build (như
   rule §5 khuyến nghị) và sửa nếu khác.
2. **Khớp newline khi so sánh:** để tránh trật vì `\n` cuối file, mọi giá trị
   nhạy cảm được ghi bằng `printf '%s'`/`echo -n` (không xuống dòng) — cả phía
   MinIO seed (`printf '%s' "$FLAG_VALUE"`) lẫn hướng dẫn sinh viên trong
   `docs/*.md` và `solver.sh`. `pregrade.sh` còn trim CR/khoảng trắng thừa như
   một lớp phòng vệ bổ sung.
3. **`mc admin policy create/attach` vs `mc admin policy add/set`:** cú pháp
   MinIO Client đổi tên giữa các phiên bản; script dùng `||` để fallback sang
   cú pháp cũ. Vì `mc`/`minio` được tải bản **mới nhất** lúc build (URL
   `.../release/linux-amd64/mc`), nhánh mới (`create`/`attach`) nhiều khả năng
   sẽ chạy, nhưng cần xác nhận thực tế trên VM build.
4. **`mc anonymous set download`:** giả định set policy cho phép anonymous
   `ListBucket` + `GetObject` (đúng ý cấu hình sai cần mô phỏng). Cần xác nhận
   hành vi đúng như vậy với bản `mc` tải về, và rằng `aws s3api get-bucket-
   policy --no-sign-request` đọc được policy JSON đó (một số phiên bản MinIO
   có thể chặn đọc policy ẩn danh dù cho phép đọc object — nếu vậy, thay bước
   này trong docs bằng `mc anonymous get local/public-assets` là đủ để nhiệm
   vụ 1 vẫn có bằng chứng, cần chỉnh `goals.config`/`docs` tương ứng).
5. **`aws-cli` v1 qua pip trên base `labtainer.network`:** image base có thể
   dùng Python hệ thống khá cũ; nếu `pip3 install awscli<2` lỗi do
   dependency, cân nhắc dùng `mc` làm công cụ chính (bảng cú pháp trong docs
   đã có sẵn cột `mc` thay thế cho hầu hết thao tác) hoặc pin rõ một version
   `awscli` cụ thể còn khả dụng trên PyPI tại thời điểm build.
6. **Kích thước ảnh / RAM:** `client` cài thêm Python + awscli + mc (~vài chục
   MB); `storage` chỉ thêm 2 binary Go tĩnh (`minio` ~80–100MB, `mc` ~30–40MB).
   Vẫn trong ngân sách VM ~3GB miễn không build song song nhiều lab (theo
   khuyến cáo §3/§7 của LAB-BUILD-RULES.md).
7. **`pregrade.sh` mới xử lý phía `client`:** chưa có bước kiểm tra "end-state"
   độc lập phía `storage` (vd đọc trực tiếp config bucket policy còn sót lại
   trên đĩa MinIO) như gợi ý ở §4.4 của rule, vì không thể xác định chắc chắn
   cấu trúc file nội bộ `.minio.sys/...` của đúng phiên bản MinIO sẽ tải khi
   không build-test được. Cơ chế chấm điểm HIỆN TẠI dựa hoàn toàn vào bằng
   chứng phía `client` (đã thiết kế để không thể giả mạo bằng cách gõ tay —
   xem mục 3), được coi là đủ chặt; bổ sung kiểm tra phía `storage` là một cải
   tiến khả thi cho vòng sau nếu cần.
8. **Không sinh `docs/cloud-s3-misconfig.docx`:** theo yêu cầu tường minh của
   người giao việc ("CHỈ .md"), lượt này chỉ có `docs/cloud-s3-misconfig-guide.md`
   (đầy đủ nội dung format PTIT, không có mục "Ghi chú triển khai", không lộ
   flag). Việc chuyển sang `.docx` bằng skill `docx` (theo LAB-BUILD-RULES.md
   §6) cần thực hiện ở một lượt riêng trước khi coi bài là "hoàn thiện" theo
   Definition of Done (§0.5) của rule.

## 5. Việc cần làm khi build thật trên VM

1. `new_lab_setup.py`/`rebuild cloud-s3-misconfig` → theo dõi `labtainer.log`,
   đặc biệt log tải `minio`/`mc`/`awscli` (VM cần internet lúc build).
2. Vào terminal `client`, chạy `bash ~/../solver.sh` (hoặc copy nội dung
   `solver.sh` vào container) → phải in đủ 7 giá trị bằng chứng hợp lệ.
3. `stoplab cloud-s3-misconfig` → `checkwork`/gradelab: verify cả 5 goal PASS.
4. Chấm lại một lần "không làm gì" (mở lab rồi dừng ngay) → verify cả 5 goal
   FAIL.
5. Rà lại checklist §8 LAB-BUILD-RULES.md, rồi sinh `docs/cloud-s3-misconfig.docx`
   bằng skill `docx` (nội dung lấy từ `docs/cloud-s3-misconfig-guide.md`) và
   cập nhật `docs/read_first.txt` trỏ về file `.docx` theo đúng mẫu chuẩn.
