#!/bin/bash
set -u
echo "$1" | sudo -S systemctl start docker
for i in $(seq 1 30); do docker version >/dev/null 2>&1 && break; sleep 2; done
if ! docker image inspect python:3.8.0-slim >/dev/null 2>&1; then
    docker load -i /opt/base-images/python-3.8.0-slim.tar
fi
if ! docker image inspect internal-app:1.0 >/dev/null 2>&1; then
    docker build --network none -t internal-app:1.0 "$HOME/sample-image"
fi
if docker image inspect internal-app:1.0 >/dev/null 2>&1; then
    mkdir -p "$HOME/app-src"
    cp "$HOME/sample-image/app.py" "$HOME/sample-image/requirements.txt" "$HOME/app-src/" 2>/dev/null
    rm -rf "$HOME/sample-image"
fi
