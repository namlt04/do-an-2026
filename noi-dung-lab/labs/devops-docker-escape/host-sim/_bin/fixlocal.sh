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
    log "dockerd is ready."

    log "build the offline image 'escimg' from /opt/escimg-build (no Internet needed)"
    if echo "$PW" | sudo -S docker build -t escimg:latest /opt/escimg-build \
            >/tmp/escimg-build.log 2>&1; then
        log "finished building image escimg:latest"
    else
        log "WARNING: building the escimg image failed, see /tmp/escimg-build.log"
    fi
else
    log "WARNING: dockerd is NOT ready after ~60s."
    log "  Check: sudo systemctl status dockerd-hostsim.service"
    log "            sudo journalctl -u dockerd-hostsim.service --no-pager | tail -n 100"
fi

sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

log "done."
