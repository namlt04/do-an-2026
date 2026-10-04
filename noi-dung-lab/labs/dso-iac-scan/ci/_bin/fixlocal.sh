#!/bin/bash

PASSWD=$1

echo "$PASSWD" | sudo -S chown root:root /opt/gate/gate_server.py /opt/gate/flag.env 2>/dev/null
echo "$PASSWD" | sudo -S chmod 750 /opt/gate 2>/dev/null
echo "$PASSWD" | sudo -S chmod 600 /opt/gate/flag.env 2>/dev/null
echo "$PASSWD" | sudo -S chmod 755 /opt/gate/gate_server.py 2>/dev/null

echo "$PASSWD" | sudo -S systemctl daemon-reload
echo "$PASSWD" | sudo -S systemctl enable iacgate.service
echo "$PASSWD" | sudo -S systemctl restart iacgate.service
