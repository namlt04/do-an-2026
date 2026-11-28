#!/bin/bash
set -u
PW="${1:-}"

log() { echo "[app fixlocal] $*"; }

log "waiting for /var/run/docker.sock to be ready..."
ok=0
for i in $(seq 1 20); do
    if docker -H unix:///var/run/docker.sock version >/dev/null 2>&1; then
        ok=1
        break
    fi
    sleep 1
done

if [ "$ok" -eq 1 ]; then
    log "connected to host-sim's dockerd via /var/run/docker.sock (OK)."
else
    log "WARNING: could not connect via /var/run/docker.sock after ~20s."
    log "  Check the log: /var/log/docker-sock-forward.log; fallback: docker -H tcp://172.35.0.5:2375 version"
fi

exit 0
