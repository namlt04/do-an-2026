#!/bin/bash
# Chay sau parameterization (flag da duoc bom vao /flag1.txt, /opt/issuer/flag*.txt).
# $1 = mat khau sudo.
set -u
PASS="${1:-}"

# Quyen doc cho tien trinh dich vu (chay bang user ubuntu).
echo "$PASS" | sudo -S chmod 644 /flag1.txt 2>/dev/null
echo "$PASS" | sudo -S chmod 644 /opt/issuer/flag2.txt /opt/issuer/flag3.txt 2>/dev/null
echo "$PASS" | sudo -S chmod 755 /opt/issuer 2>/dev/null

echo "$PASS" | sudo -S systemctl daemon-reload
echo "$PASS" | sudo -S systemctl enable webapp.service issuer.service
echo "$PASS" | sudo -S systemctl restart webapp.service issuer.service

for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://127.0.0.1:8080/health"; then
        break
    fi
    sleep 0.5
done
for i in $(seq 1 30); do
    if curl -s -o /dev/null "http://127.0.0.1:8099/health"; then
        break
    fi
    sleep 0.5
done

exit 0
