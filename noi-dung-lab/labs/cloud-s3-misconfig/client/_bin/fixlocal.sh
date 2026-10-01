#!/bin/bash
#
# client/_bin/fixlocal.sh - cloud-s3-misconfig
#
# Chay SAU KHI parameterization hoan tat: ~/hardening-admin.env da duoc thay
# placeholder HARDENACCESSKEY/HARDENSECRETKEY bang credential hardening rieng
# cho sinh vien nay (giong het gia tri fixlocal.sh ben storage da dung de tao
# MinIO user tuong ung - xem config/parameter.config).
#
# $1 = mat khau user container, $2 = uid
#
set -u

# Chi cho chinh sinh vien doc duoc credential hardening cua minh
chmod 600 "$HOME/hardening-admin.env" 2>/dev/null || true

# Thu muc de SV tai/giai nen backup lay tu bucket public
mkdir -p "$HOME/loot"

# Vung nho tam cho vung ket qua/goi y mac dinh AWS CLI (tranh loi thieu region)
mkdir -p "$HOME/.aws"
if [ ! -f "$HOME/.aws/config" ]; then
  cat > "$HOME/.aws/config" <<'EOF'
[default]
region = us-east-1
output = json
EOF
fi
