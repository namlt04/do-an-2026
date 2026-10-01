#
# minio_env.sh - bien moi truong cho MinIO root credential.
#
# GIA TRI DUOI DAY DUOC PARAMETERIZE (HASH_REPLACE) BOI KHUNG LABTAINER va
# TRUNG KHOP CHINH XAC voi AccessKeyId/SecretAccessKey ma dich vu 'imds' cap
# phat cho sinh vien (xem config/parameter.config). Day la cach lab bao dam
# "credential tam thoi danh cap qua SSRF phai dung de dang nhap storage".
#
# File nay duoc 'source' boi storage/_bin/fixlocal.sh (bash), KHONG phai
# duoc systemd doc truc tiep, nen giu cu phap export/bash binh thuong.
#
export MINIO_ROOT_USER="AKIAIMDSRUNKEYID"
export MINIO_ROOT_PASSWORD="SECRETRUNSECRETKEY"
