#!/bin/bash
set -u
echo "$1" | sudo -S systemctl start docker
for i in $(seq 1 30); do docker version >/dev/null 2>&1 && break; sleep 2; done
if ! docker image inspect internal-app:1.0 >/dev/null 2>&1; then "$HOME/_bin/build_sample_image.sh"; fi
