#!/usr/bin/env python3
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

AUDIT_LOG = os.environ.get("AUDIT_LOG", "/home/ubuntu/minio_audit.log")
SINK_PORT = int(os.environ.get("SINK_PORT", "9100"))


class Handler(BaseHTTPRequestHandler):
    def _ok(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok\n")

    def do_GET(self):
        self._ok()

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b""
            try:
                event = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                event = {"raw": raw.decode("utf-8", "replace")}
            api = event.get("api") or {} if isinstance(event, dict) else {}
            summary = {
                "time": event.get("time") if isinstance(event, dict) else None,
                "api_name": api.get("name"),
                "bucket": api.get("bucket"),
                "object": api.get("object"),
                "status": api.get("statusCode"),
                "remotehost": event.get("remotehost") if isinstance(event, dict) else None,
            }
            with open(AUDIT_LOG, "a") as f:
                f.write(json.dumps(summary) + "\n")
        except Exception:
            pass
        self._ok()

    def log_message(self, *args):
        return


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", SINK_PORT), Handler).serve_forever()
