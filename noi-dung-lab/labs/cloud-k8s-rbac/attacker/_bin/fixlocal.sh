#!/bin/bash
set -u
echo "$1" | sudo -S chown -R ubuntu:ubuntu /home/ubuntu
exit 0
