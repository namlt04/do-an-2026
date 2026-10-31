#!/bin/bash
# Chay o container client (noi sinh vien thao tac va noi cham diem gom artifact).
set -u
HOME_DIR="/home/ubuntu"
touch "$HOME_DIR/flag1.txt" "$HOME_DIR/flag2.txt" "$HOME_DIR/flag3.txt"
touch "$HOME_DIR/dast_noWAF.txt" "$HOME_DIR/dast_WAF.txt"
chown ubuntu:ubuntu "$HOME_DIR/flag1.txt" "$HOME_DIR/flag2.txt" "$HOME_DIR/flag3.txt" \
    "$HOME_DIR/dast_noWAF.txt" "$HOME_DIR/dast_WAF.txt" 2>/dev/null
exit 0
