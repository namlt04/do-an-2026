#!/bin/bash
set -u
PW="$1"

log() { echo "[host-sim fixlocal] $*"; }

log "enable + (re)start dockerd-hostsim.service"
echo "$PW" | sudo -S systemctl daemon-reload
echo "$PW" | sudo -S systemctl enable dockerd-hostsim.service >/tmp/dockerd-hostsim.enable.log 2>&1
echo "$PW" | sudo -S systemctl restart dockerd-hostsim.service

ready=0
for i in $(seq 1 30); do
    if sudo docker version >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done

if [ "$ready" -eq 1 ]; then
    log "dockerd da san sang."

    log "build anh offline 'escimg' tu /opt/escimg-build (khong can Internet)"
    if echo "$PW" | sudo -S docker build -t escimg:latest /opt/escimg-build \
            >/tmp/escimg-build.log 2>&1; then
        log "da build xong anh escimg:latest"
    else
        log "CANH BAO: build anh escimg that bai, xem /tmp/escimg-build.log"
    fi
else
    log "CANH BAO: dockerd KHONG san sang sau ~60s."
    log "  Kiem tra: sudo systemctl status dockerd-hostsim.service"
    log "            sudo journalctl -u dockerd-hostsim.service --no-pager | tail -n 100"
fi

sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

log "xong."
