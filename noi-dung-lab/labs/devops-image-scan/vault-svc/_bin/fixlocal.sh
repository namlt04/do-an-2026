#!/bin/bash
set -u
echo "$1" | sudo -S systemctl daemon-reload
echo "$1" | sudo -S systemctl enable devops-image-vault.service
echo "$1" | sudo -S systemctl restart devops-image-vault.service
