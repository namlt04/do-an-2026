#!/bin/bash
set -u
PW="$1"

log() { echo "[app fixlocal] $*"; }

log "dam bao dockerd cuc bo (neu co) khong chiem /var/run/docker.sock"
echo "$PW" | sudo -S systemctl disable --now docker.service docker.socket >/dev/null 2>&1 || true
echo "$PW" | sudo -S rm -f /var/run/docker.sock

log "enable + (re)start docker-sock-forward.service (socat -> host-sim:2375)"
echo "$PW" | sudo -S systemctl daemon-reload
echo "$PW" | sudo -S systemctl enable docker-sock-forward.service >/tmp/docker-sock-forward.enable.log 2>&1
echo "$PW" | sudo -S systemctl restart docker-sock-forward.service

ok=0
for i in $(seq 1 15); do
    if docker -H unix:///var/run/docker.sock version >/dev/null 2>&1; then
        ok=1
        break
    fi
    sleep 2
done

if [ "$ok" -eq 1 ]; then
    log "da ket noi duoc toi dockerd cua host-sim qua /var/run/docker.sock"
else
    log "CANH BAO: chua ket noi duoc toi dockerd cua host-sim sau ~30s."
    log "  Service se tu dong thu lai. Kiem tra: sudo systemctl status docker-sock-forward.service"
    log "  Duong du phong: docker -H tcp://172.35.0.5:2375 version"
fi

log "xong."
