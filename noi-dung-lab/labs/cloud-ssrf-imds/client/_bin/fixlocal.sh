#!/bin/bash
#
#  cloud-ssrf-imds : client - fixlocal
#
#  Chay sau khi parameterization hoan tat. Tao san (rong) cac file quy uoc
#  ma sinh vien se ghi ket qua khai thac vao, de khung cham diem luon co
#  artifact de doc (rong -> khong khop flag -> FAIL dung nhu ky vong khi
#  sinh vien chua lam gi).
#
#  $1 = mat khau user container, $2 = uid (xem huong dan mau cua framework)

HOME_DIR="/home/ubuntu"
touch "$HOME_DIR/loot.txt"
touch "$HOME_DIR/creds.txt"
touch "$HOME_DIR/remediation.txt"
chown ubuntu:ubuntu "$HOME_DIR/loot.txt" "$HOME_DIR/creds.txt" "$HOME_DIR/remediation.txt" 2>/dev/null

exit 0
