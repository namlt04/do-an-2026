# BUILD-NOTES.md — dso-docker-escape

> Ghi chú build/test + quyết định thiết kế + rủi ro triển khai. Bài này được đánh giá
> là **rủi ro triển khai cao nhất** trong bộ 10 lab (dind + privileged), nên mọi quyết
> định dưới đây ưu tiên **ổn định** hơn là "đúng y hệt kịch bản gốc" khi hai mục tiêu
> xung đột. File này KHÔNG được đưa vào `docs/dso-docker-escape-guide.md` phát cho
> sinh viên (đúng §6 LAB-BUILD-RULES.md).

Trạng thái tại thời điểm viết: **CHƯA build/CHƯA chạy `rebuild` trên VM thật** (nhiệm
vụ này chỉ viết file nguồn theo yêu cầu — không SSH, không build). Mọi nhận định về
"sẽ chạy được" dưới đây là suy luận từ tài liệu Labtainer + kiến thức Docker/dind, cần
**kiểm chứng thực tế** theo quy trình ở LAB-BUILD-RULES.md §7 trước khi coi là DONE.

---

## 1. Cách nối `app` ↔ `host-sim`

Chọn **Phương án A (docker.sock)** làm đường khai thác BẮT BUỘC/duy nhất được cham
điểm đầy đủ, đúng khuyến nghị trong `01-dso-docker-escape.md` §5 "Ghi chú triển khai".

- **`host-sim`** cài Docker Engine thật qua gói apt `docker.io` (KHÔNG dùng image
  upstream `docker:dind` vì image đó dựa trên Alpine, không có apt/systemd — sẽ phá vỡ
  toàn bộ build-glue chuẩn của Labtainer mà `LAB-BUILD-RULES.md` §3 yêu cầu giữ
  nguyên). dockerd được tự chạy bằng **systemd unit riêng**
  `host-sim/_system/etc/systemd/system/dockerd-hostsim.service`, lắng nghe ĐỒNG THỜI:
  - `unix:///var/run/docker.sock` (socket cục bộ trên host-sim)
  - `tcp://0.0.0.0:2375` (KHÔNG xác thực — đây chính là misconfig được mô phỏng)

  Unit mặc định `docker.service` do gói `docker.io` cài kèm bị **mask** bằng
  `ln -sf /dev/null /etc/systemd/system/docker.service` ngay trong Dockerfile, tránh 2
  tiến trình dockerd tranh nhau `/var/run/docker.sock`.

- **`app`** cài `docker.io` chỉ để lấy **CLI `docker`** (không dùng dockerd đi kèm —
  cũng bị mask theo cách tương tự). Một systemd unit riêng
  `app/_system/etc/systemd/system/docker-sock-forward.service` chạy
  `socat UNIX-LISTEN:/var/run/docker.sock,...  TCP:172.35.0.5:2375`, tức là **tạo ra
  `/var/run/docker.sock` trên app bằng cách forward sang cổng TCP của host-sim**. Nhờ
  vậy lệnh sinh viên gõ đúng y hệt đề bài (`docker -H unix:///var/run/docker.sock ...`)
  hoạt động thật, đồng thời `ls -la /var/run/docker.sock` ở Nhiệm vụ 1 cũng cho kết quả
  đúng như mô tả. Đường dự phòng `docker -H tcp://172.35.0.5:2375` được nêu trong tài
  liệu hướng dẫn phòng khi socat/host-sim khởi động chưa kịp.

- **Trình tự khởi động**: `app` khai báo `WAIT_FOR host-sim` trong `start.config`, nên
  `host-sim/_bin/fixlocal.sh` (bật dockerd, đợi sẵn sàng, build image `escimg`) chạy
  xong TRƯỚC KHI `app/_bin/fixlocal.sh` bật socat forwarder. Cả hai fixlocal.sh đều có
  vòng lặp poll (tối đa ~60s) thay vì giả định service lên ngay lập tức.

- **Ảnh Docker offline "escimg"**: thay vì phải `docker pull` một image (alpine/...)
  lúc runtime — vi phạm yêu cầu offline và không đáng tin cậy nếu VM lab không có
  mạng lúc sinh viên làm bài — `host-sim` tự **`docker build` một image tối giản cục
  bộ** ngay trong `fixlocal.sh` (sau khi dockerd sẵn sàng), từ context có sẵn trong
  image tại `/opt/escimg-build/` (`Dockerfile FROM scratch` + binary `busybox-static`
  đã tải lúc BUILD image host-sim, không cần mạng lúc runtime). Image `escimg` này chỉ
  chứa `sh`/`chroot`/`cat`/`ls`/... đủ để chạy đúng cú pháp đề bài
  (`docker run -v /:/host escimg chroot /host sh`).

---

## 2. Rủi ro dind / privileged trên Labtainer — checklist cần kiểm chứng khi build thật

1. **Labtainer container mặc định chạy privileged** (theo yêu cầu nhiệm vụ). `host-sim`
   KHÔNG đặt `NO_PRIVILEGE` trong `start.config` nên vẫn ở chế độ privileged mặc định —
   đây là điều dind cần để hoạt động (tạo network namespace, cgroup, mount overlay...).
   **Cần kiểm chứng**: Docker Engine của VM Labtainer thật sự cấp đủ quyền
   (`--privileged` tương đương) cho container khi build/run, không bị một lớp giới hạn
   nào khác (ví dụ AppArmor/seccomp profile riêng của Labtainer) chặn `mount`/`clone`
   bên trong.
2. **Storage driver**: dockerd trong `host-sim` được cấu hình cứng
   `--storage-driver=vfs` (không dùng `overlay2`) để tránh lỗi overlay-trên-overlay khi
   chạy dind lồng trong một container đã dùng overlay2 ở lớp ngoài — vfs chậm hơn/tốn
   đĩa hơn nhưng ổn định hơn nhiều cho use-case "build 1 image bé + chạy vài container
   ngắn hạn" của bài này.
3. **iptables/NAT**: dockerd chạy với `--iptables=false` để không phụ thuộc kernel
   module `iptable_nat`/`br_netfilter` (có thể không sẵn có hoặc bị chặn thao tác bên
   trong container nested-privileged trên một số kernel VM). Hệ quả: container do
   `escimg` tạo ra không có NAT ra ngoài — CHẤP NHẬN ĐƯỢC vì bài không cần mạng bên
   trong container escape (chỉ cần đọc file qua bind-mount `-v /:/host`). Docker vẫn
   tạo được bridge `docker0` mặc định để `docker run` không cần cờ `--network` đặc
   biệt.
4. **cgroup v1/v2**: nếu VM/kernel dùng cgroup v2 thuần và docker.io (bản cũ trên
   Ubuntu 18.04 base của Labtainer) không tương thích tốt, dockerd trong host-sim có
   thể không khởi động được. **Fallback nếu gặp lỗi cgroup**: thêm
   `--exec-opt native.cgroupdriver=cgroupfs` vào `ExecStart` của
   `dockerd-hostsim.service`, hoặc kiểm tra `/sys/fs/cgroup` bên trong host-sim
   (`mount | grep cgroup`) khi debug.
5. **Tài nguyên**: dind tốn thêm RAM/đĩa so với container thường (dockerd + containerd
   + runc + image escimg vài MB). Khuyến nghị VM Labtainer có **≥ 4GB RAM** khi chạy
   riêng lab này (đúng ghi chú trong spec gốc). Vì `LAB-BUILD-RULES.md` §3 nhắc
   "không chạy 5 lab cùng lúc" — với bài này nên khuyến nghị **chỉ chạy 1 mình** khi
   test, không song song với lab khác.
6. **Thời gian khởi động**: dockerd thật cần vài giây tới vài chục giây để sẵn sàng
   lần đầu (khởi tạo `/var/lib/docker`). Cả hai `fixlocal.sh` đã có vòng lặp đợi (poll)
   thay vì giả định tức thời — nhưng nếu build/test cho thấy cần lâu hơn 60s, tăng số
   vòng lặp (`seq 1 30` × `sleep 2`) trong `host-sim/_bin/fixlocal.sh` và
   `app/_bin/fixlocal.sh`.

### Nếu dind KHÔNG chạy được ổn định trên VM Labtainer (fallback)

Nếu sau khi `rebuild` + test thấy `dockerd-hostsim.service` liên tục lỗi (không phải
lỗi cấu hình có thể sửa nhanh như mục 2–4 ở trên, mà là giới hạn cứng của lớp Docker
VM bên dưới), hai hướng dự phòng theo thứ tự ưu tiên:

1. **Giảm phạm vi dind**: bỏ hẳn việc `host-sim` tự chạy container con (`escimg`) —
   thay vào đó viết một **shim HTTP giả lập tối thiểu** (Python/Flask, không phải
   dockerd thật) chỉ trả lời đúng 3-4 API Docker Engine mà lab dùng
   (`GET /version`, `GET /images/json`, `POST /containers/create` + `/start` +
   `/attach`) đủ để lệnh `docker -H ...` của sinh viên "tưởng" đang nói chuyện với một
   daemon thật và đọc được file định sẵn trên host-sim. Mất tính "thật" của dind nhưng
   loại bỏ hoàn toàn rủi ro nested-privileged.
2. **Chuyển hẳn sang Phương án B** (privileged/CAP_SYS_ADMIN như minh hoạ trong
   Nhiệm vụ 3) làm đường bắt buộc — KHÔNG khuyến nghị vì như phân tích ở mục 3 dưới
   đây, đường này trong Labtainer không dẫn thẳng tới rootfs của `host-sim` (2
   container độc lập, không chia sẻ PID namespace/block device), nên sẽ cần thiết kế
   lại hoàn toàn cách "mô phỏng host" (ví dụ gộp app+host-sim làm một container có 2
   phần) — thay đổi lớn, không nằm trong phạm vi bản build này.

---

## 3. Vì sao Nhiệm vụ 3 (`escape_via_privileged`) là TUỲ CHỌN, không bắt buộc

Thiết kế gốc trong `01-dso-docker-escape.md` mô tả 2 đường escape độc lập
(docker.sock VÀ privileged/nsenter), cả hai đều dẫn tới `/root` của "host". Trong
Labtainer, `app` và `host-sim` là **hai container tách biệt hoàn toàn** — không có cơ
chế chuẩn nào trong `start.config` (xem `_ref-labtainer-designer.txt` §4.2) để chia sẻ
PID namespace hay block device thật giữa hai container. Hệ quả:

- **`nsenter --target 1 ...`** trên `app` chỉ nhảy vào namespace của chính `app`
  (PID 1 của app), KHÔNG bao giờ chạm tới `host-sim` — vô nghĩa nếu build như một
  bước "bắt buộc" để lấy flag.
- **`mount /dev/sda1 ...`**: nếu `app` được đặt privileged, `/dev` mà nó thấy là
  `/dev` thật của **máy ảo Labtainer** (không phải của `host-sim`) — mount thiết bị đó
  sẽ cho thấy đĩa thật của VM Labtainer chứ không phải nội dung mô phỏng của
  `host-sim`/không có flag ở đó. Ngoài việc vô nghĩa với mục tiêu bài học, việc để
  sinh viên mount/ghi vào đĩa thật của VM còn là rủi ro vận hành không cần thiết.

**Quyết định**: `app` được đặt `NO_PRIVILEGE YES` (xem `config/start.config`) — vừa
giảm rủi ro triển khai (không phụ thuộc lớp Docker của VM có cho container con chạy
privileged ổn định hay không), vừa tránh tình huống sinh viên vô tình mount đĩa thật
của VM. Nhiệm vụ 3 trong tài liệu hướng dẫn được ghi rõ là **tuỳ chọn/minh hoạ khái
niệm**, không bắt buộc để lấy flag; goal `escape_via_privileged` trong
`instr_config/goals.config` được chấm **lenient** (dùng lại bằng chứng trinh sát của
Nhiệm vụ 1) và không nằm trong goal tổng hợp `lab_complete`.

Nếu về sau muốn làm Nhiệm vụ 3 "thật" 100%, hướng khả thi nhất là gộp `app` +
`host-sim` thành 1 container duy nhất chạy 2 network namespace ảo (phức tạp hơn nhiều,
ngoài phạm vi bản build hiện tại).

---

## 4. Flag & chống bypass — tóm tắt cơ chế

- `dockerflag` (flag chính, `PTIT{...}`) và `hostmarker` (canary riêng) đều là
  `HASH_REPLACE` **per-student**, đặt trong `host-sim:/root/flag.txt` và
  `host-sim:/root/.hostmarker` — `app` không có shell trên `host-sim` nên không thể
  `cat`/đoán được nếu chưa escape thật.
- `pregrade.sh` không chỉ so nội dung file mà còn **grep `.bash_history`** của sinh
  viên để xác nhận có một lệnh `docker ... -H ... run ... -v /:...` THẬT (chống việc
  echo tay một chuỗi đoán được vào `~/host_evidence.txt`). Kết quả trung gian được ghi
  ra `.local/result/*.txt` ("OK"/"NO") để `goals.config` chỉ cần so sánh chuỗi đơn
  giản — tránh phụ thuộc cú pháp AND/NOT phức tạp/chưa kiểm chứng được của
  `goals.config` (xem mục 5).
- Không đặt bất kỳ flag/canary nào trên `app` (kể cả file chỉ root đọc được) — đúng
  nguyên tắc §4.1.2 của `LAB-BUILD-RULES.md` (sinh viên có sudo trên máy của họ).

---

## 5. Điểm CẦN KIỂM CHỨNG khi build thật lần đầu (chưa test được trong nhiệm vụ này)

- [ ] Cú pháp `boolean : (_a and _b)` trong `goals.config` — dùng đúng 2 chỗ
      (`escape_via_socket`, `lab_complete`); các goal còn lại cố tình dùng
      `string_start`/`string_equal` đơn giản để giảm phụ thuộc vào cú pháp chưa được
      xác nhận 100% từ tài liệu sẵn có trong repo này.
- [ ] `dockerd-hostsim.service` khởi động thành công trong container privileged của
      Labtainer (xem mục 2).
- [ ] `docker build -t escimg /opt/escimg-build` chạy được trong `fixlocal.sh` (không
      cần mạng, chỉ cần dockerd cục bộ đã lên).
- [ ] `socat` forward từ `app` sang `host-sim:2375` không bị network policy nào của
      Labtainer chặn (2 container cùng `LAB_NET` nên về lý thuyết thông với nhau).
- [ ] Gói `docker.io`, `busybox-static`, `socat`, `libcap2-bin`, `util-linux` đều có
      sẵn qua apt mirror mà `apt-source.sh` của Labtainer trỏ tới (không cần thêm repo
      ngoài — xem cách các lab khác trong repo, vd `dso-secrets-git`, đã dùng chung cơ
      chế này thành công cho các gói tương tự).
- [ ] Test 2 chiều theo LAB-BUILD-RULES.md §0/§7: chạy `solver.sh` → toàn bộ goal bắt
      buộc PASS; chấm khi "không làm gì" → toàn bộ goal FAIL.

## 6. Kích thước / tài nguyên image

- `app`: base `labtainer.network` + `docker.io` (kéo theo containerd/runc dù không
  dùng — chấp nhận đánh đổi để dùng chung apt mirror sẵn có, xem lý do ở mục 1) +
  `libcap2-bin`, `util-linux`, `socat`. Nếu sau này cần giảm dung lượng, có thể thay
  bằng gói `docker-ce-cli` (client-only) từ repo apt chính thức của Docker — nhưng
  cần thêm 1 apt repo ngoài, rủi ro kết nối mạng lúc build cao hơn nên KHÔNG chọn làm
  mặc định.
- `host-sim`: base `labtainer.network` + `docker.io` (bắt buộc, cần dockerd thật) +
  `busybox-static` (vài trăm KB) — không cần preload image nặng nào khác nhờ cơ chế
  `escimg` build cục bộ.

## Cập nhật test thật (2026-10-04)
- **PASS 6/6 goal** với đường khai thác qua **TCP `tcp://172.60.2.5:2375`** (dockerd host-sim lắng nghe TCP — chính là lỗi "Docker daemon API lộ không TLS", CIS Docker 2.x; cũng nguy hiểm tương đương mount docker.sock).
- Lưu ý kỹ thuật: forward `/var/run/docker.sock` bằng `socat UNIX-LISTEN...TCP` chỉ hoạt động cho các API đơn giản (version/ps/images); **`docker run` bị mất output stream** qua socat (lỗi HTTP hijack kinh điển). Vì vậy đường khai thác tin cậy (solver + chấm) dùng `docker -H tcp://<host-sim>:2375`. `solver.sh` tự thử docker.sock trước rồi fallback sang TCP.
