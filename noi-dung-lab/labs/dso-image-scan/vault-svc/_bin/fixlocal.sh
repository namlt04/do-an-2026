#!/bin/bash
set -u
echo "$1" | sudo -S systemctl daemon-reload
echo "$1" | sudo -S systemctl enable dso-image-vault.service
echo "$1" | sudo -S systemctl restart dso-image-vault.service
