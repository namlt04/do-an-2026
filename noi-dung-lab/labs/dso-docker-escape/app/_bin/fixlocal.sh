#!/bin/bash
set -u
PW="${1:-}"

log() { echo "[app fixlocal] $*"; }

# App container chay NO_PRIVILEGE -> systemd KHONG activate unit (khong co bus).
# Vi vay socat forward (/var/run/docker.sock -> host-sim:2375) duoc khoi dong
# NGAY TRONG CMD cua container (xem Dockerfile), chay moi lan start/restart/reboot.
# fixlocal chi doi socket san sang de xac nhan.

log "doi /var/run/docker.sock (socat forward tu CMD) san sang..."
ok=0
for i in $(seq 1 20); do
    if docker -H unix:///var/run/docker.sock version >/dev/null 2>&1; then
        ok=1
        break
    fi
    sleep 1
done

if [ "$ok" -eq 1 ]; then
    log "da ket noi dockerd cua host-sim qua /var/run/docker.sock (OK)."
else
    log "CANH BAO: chua ket noi duoc qua /var/run/docker.sock sau ~20s."
    log "  Kiem tra log: /var/log/docker-sock-forward.log; duong du phong: docker -H tcp://172.35.0.5:2375 version"
fi

exit 0
