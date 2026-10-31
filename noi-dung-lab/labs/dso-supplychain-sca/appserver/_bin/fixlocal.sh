#!/bin/bash
set -u
echo "$1" | sudo -S chmod 644 /flag.txt
echo "$1" | sudo -S chown -R ubuntu:ubuntu /home/ubuntu/app/public
echo "$1" | sudo -S systemctl daemon-reload
echo "$1" | sudo -S systemctl enable vuln-notes.service
echo "$1" | sudo -S systemctl restart vuln-notes.service
