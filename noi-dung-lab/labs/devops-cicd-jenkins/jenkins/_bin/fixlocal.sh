#!/bin/bash
set -u
echo "$1" | sudo -S chown -R ubuntu:ubuntu /var/jenkins_home
echo "$1" | sudo -S systemctl daemon-reload
echo "$1" | sudo -S systemctl enable jenkins.service
echo "$1" | sudo -S systemctl restart jenkins.service
for i in $(seq 1 60); do curl -s -o /dev/null http://localhost:8080/login && break; sleep 3; done
