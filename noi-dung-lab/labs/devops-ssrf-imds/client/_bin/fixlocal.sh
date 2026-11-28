#!/bin/bash

HOME_DIR="/home/ubuntu"
touch "$HOME_DIR/loot.txt"
touch "$HOME_DIR/creds.txt"
touch "$HOME_DIR/remediation.txt"
chown ubuntu:ubuntu "$HOME_DIR/loot.txt" "$HOME_DIR/creds.txt" "$HOME_DIR/remediation.txt" 2>/dev/null

mkdir -p "$HOME_DIR/.aws"
cat > "$HOME_DIR/.aws/config" <<'EOF'
[default]
region = us-east-1
s3 =
    addressing_style = path
EOF
chown -R ubuntu:ubuntu "$HOME_DIR/.aws" 2>/dev/null

exit 0
