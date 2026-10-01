#!/bin/bash
#
#  This script will be run after parameterization has completed, e.g., 
#  use this to compile source code that has been parameterized.
#  The container user password will be passed as the first argument,
#  (the user ID is the second parameter)
#  If this script is to use sudo and the sudoers for the lab
#  does not permit nopassword, then use:
#  echo $1 | sudo -S the-command
#
#  If you issue commands herein to start services, and those services
#  have unit files prescribing their being started after the
#  waitparam.service, then first create the flag directory that
#  waitparam sleeps on:
#
#   PERMLOCKDIR=/var/labtainer/did_param
#   echo $1 | sudo -S mkdir -p "$PERMLOCKDIR"
#
# --- dso-iac-scan / ci ---------------------------------------------------
# Chay SAU khi parameterization da xong, tuc /opt/gate/flag.env luc nay DA
# CHUA gia tri hash flag rieng cua sinh vien (thay cho token IACGATEFLAG,
# xem config/parameter.config - HASH_REPLACE). Bat dich vu quality gate
# (iacgate.service) lang nghe cong 8000. Sinh vien khong co terminal tren
# container nay (TERMINALS -1) nen khong the tu tay chinh sua/khoi dong lai
# dich vu hay doc truc tiep flag.env.

PASSWD=$1

# Sieet quyen file flag/service truoc khi bat dich vu.
echo "$PASSWD" | sudo -S chown root:root /opt/gate/gate_server.py /opt/gate/flag.env 2>/dev/null
echo "$PASSWD" | sudo -S chmod 750 /opt/gate 2>/dev/null
echo "$PASSWD" | sudo -S chmod 600 /opt/gate/flag.env 2>/dev/null
echo "$PASSWD" | sudo -S chmod 755 /opt/gate/gate_server.py 2>/dev/null

echo "$PASSWD" | sudo -S systemctl daemon-reload
echo "$PASSWD" | sudo -S systemctl enable iacgate.service
echo "$PASSWD" | sudo -S systemctl restart iacgate.service

