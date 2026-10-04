#!/bin/bash
set -u

chmod 600 "$HOME/hardening-admin.env" 2>/dev/null || true

mkdir -p "$HOME/loot"

mkdir -p "$HOME/.aws"
if [ ! -f "$HOME/.aws/config" ]; then
  cat > "$HOME/.aws/config" <<'EOF'
[default]
region = us-east-1
output = json
EOF
fi
