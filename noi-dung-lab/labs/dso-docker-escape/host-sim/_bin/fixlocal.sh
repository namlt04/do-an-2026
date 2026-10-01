#!/bin/bash
#
#  fixlocal.sh (host-sim) - dso-docker-escape
#
#  Chay SAU khi parameterization da hoan tat (flag.txt / .hostmarker da duoc thay
#  bang gia tri hash per-student). $1 = mat khau user, $2 = uid.
#
#  Nhiem vu:
#   1) Bat dockerd THAT (dockerd-hostsim.service) - mo phong Docker Engine cua "host".
#   2) Doi dockerd san sang.
#   3) Build offline anh "escimg" (FROM scratch, khong pull mang) de sinh vien dung
#      lam anh container moi khi khai thac qua docker.sock (Nhiem vu 2 cua bai).
#
set -u
PW="$1"

log() { echo "[host-sim fixlocal] $*"; }

log "enable + (re)start dockerd-hostsim.service"
echo "$PW" | sudo -S systemctl daemon-reload
echo "$PW" | sudo -S systemctl enable dockerd-hostsim.service >/tmp/dockerd-hostsim.enable.log 2>&1
echo "$PW" | sudo -S systemctl restart dockerd-hostsim.service

# Doi dockerd san sang (toi da ~60s). Khong chan vo han de tranh treo lab neu moi
# truong Docker/VM ben duoi khong ho tro dind on dinh (xem BUILD-NOTES.md).
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

# Cho phep tien trinh socat tren container 'app' (chay voi user khac) ket noi duoc
# toi socket unix cuc bo (chi dung khi co ai do chon noi socket thay vi TCP; duong
# TCP :2375 la duong chinh duoc dung xuyen mang giua 2 container).
sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

log "xong."
