#!/bin/bash

HOME_DIR="/home/ubuntu"
touch "$HOME_DIR/loot.txt"
touch "$HOME_DIR/creds.txt"
touch "$HOME_DIR/remediation.txt"
chown ubuntu:ubuntu "$HOME_DIR/loot.txt" "$HOME_DIR/creds.txt" "$HOME_DIR/remediation.txt" 2>/dev/null

exit 0
