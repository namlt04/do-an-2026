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
# --- dso-iac-scan / devsecops ---------------------------------------------
# Chay SAU khi parameterization da xong. Dam bao ~/gate.sh thuc thi duoc, va
# khoi tao mot git repo LOCAL cho ~/iac-project (git init + 1 commit
# baseline) de sinh vien dung duoc `git diff` khi remediation (Nhiem vu 2/3),
# dung nhu mo ta trong bai (khong can mang, git repo chi ton tai cuc bo
# trong container).

PROJ="$HOME/iac-project"

chmod +x "$HOME/gate.sh" 2>/dev/null

if [ -d "$PROJ" ] && [ ! -d "$PROJ/.git" ]; then
    (
        cd "$PROJ" || exit 0
        git init -q
        git config user.email "dev-team@example.local"
        git config user.name "Dev Team (baseline)"
        git add -A
        git commit -q -m "baseline: ha tang Terraform ban dau tu doi dev (chua qua review bao mat)"
    )
fi

mkdir -p "$HOME/.local/result" 2>/dev/null

