#!/bin/bash
set -u
PW="$1"
echo "$PW" | sudo -S chmod 644 /opt/host-secrets/flag.txt
echo "$PW" | sudo -S chmod 600 /opt/k3s/tokens.csv
echo "$PW" | sudo -S systemctl daemon-reload
echo "$PW" | sudo -S systemctl enable k3s.service
echo "$PW" | sudo -S systemctl restart k3s.service
# cho API server san sang
for i in $(seq 1 90); do
    [ "$(echo "$PW" | sudo -S k3s kubectl get --raw=/readyz 2>/dev/null)" = "ok" ] && break
    sleep 3
done
# nap image busybox cho pod escape (offline)
echo "$PW" | sudo -S k3s ctr images import /opt/k3s/busybox.tar >/dev/null 2>&1 || true
# ap manifest cum (du phong neu auto-deploy chua chay)
echo "$PW" | sudo -S k3s kubectl apply -f /var/lib/rancher/k3s/server/manifests/lab.yaml --validate=false >/dev/null 2>&1 || true
