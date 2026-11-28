#!/usr/bin/env python3
import json
import os
import secrets
import time

from flask import Flask, Response, jsonify, request

APP_DIR = os.path.dirname(os.path.abspath(__file__))
HOME_DIR = "/home/ubuntu"
CREDS_PATH = os.path.join(APP_DIR, "creds_template.json")
LOG_PATH = os.path.join(HOME_DIR, "imds_access.log")

ROLE_NAME = "finportal-import-role"

ALLOWED_SOURCES = {"172.34.0.20", "127.0.0.1"}

app = Flask(__name__)

STATE = {
    "imdsv2_required": False,
    "tokens": {},
}


def log_access(entry):
    ordered = {
        "ts": entry.get("ts"),
        "path": entry.get("path"),
        "src_ip": entry.get("src_ip"),
        "imdsv2_required": entry.get("imdsv2_required"),
        "has_valid_token": entry.get("has_valid_token"),
        "status": entry.get("status"),
    }
    with open(LOG_PATH, "a") as f:
        f.write(json.dumps(ordered) + "\n")


def now_ts():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load_creds():
    with open(CREDS_PATH, "r") as f:
        return json.load(f)


def client_ip():
    return request.remote_addr


def check_source_allowed():
    return client_ip() in ALLOWED_SOURCES


def check_token_header():
    tok = request.headers.get("X-aws-ec2-metadata-token")
    if not tok:
        return False
    expiry = STATE["tokens"].get(tok)
    if expiry is None:
        return False
    if time.time() > expiry:
        del STATE["tokens"][tok]
        return False
    return True


def metadata_guard(path):
    ts = now_ts()
    if not check_source_allowed():
        log_access(
            {
                "ts": ts,
                "path": path,
                "src_ip": client_ip(),
                "imdsv2_required": STATE["imdsv2_required"],
                "has_valid_token": False,
                "status": 403,
            }
        )
        return (
            jsonify(error="forbidden: metadata service only reachable from the instance itself"),
            403,
        )
    has_token = check_token_header()
    if STATE["imdsv2_required"] and not has_token:
        log_access(
            {
                "ts": ts,
                "path": path,
                "src_ip": client_ip(),
                "imdsv2_required": True,
                "has_valid_token": False,
                "status": 401,
            }
        )
        return (
            jsonify(error="IMDSv2 token required: PUT /latest/api/token first"),
            401,
        )
    log_access(
        {
            "ts": ts,
            "path": path,
            "src_ip": client_ip(),
            "imdsv2_required": STATE["imdsv2_required"],
            "has_valid_token": has_token,
            "status": 200,
        }
    )
    return None


@app.route("/health")
def health():
    return jsonify(status="ok", service="imds-mock")


@app.route("/admin/status")
def admin_status():
    return jsonify(imdsv2_required=STATE["imdsv2_required"])


@app.route("/admin/enable-imdsv2", methods=["POST"])
def admin_enable_imdsv2():
    if not check_source_allowed():
        return jsonify(error="forbidden: admin endpoint only reachable from the instance itself"), 403
    STATE["imdsv2_required"] = True
    return jsonify(ok=True, imdsv2_required=True,
                    message="IMDSv2 enabled: GET /latest/* now requires the X-aws-ec2-metadata-token header.")


@app.route("/admin/imdsv2-demo")
def admin_imdsv2_demo():
    ttl = 21600
    token = secrets.token_hex(16)
    STATE["tokens"][token] = time.time() + ttl
    ts = now_ts()
    log_access(
        {
            "ts": ts,
            "path": "/latest/meta-data/instance-id (imdsv2-demo)",
            "src_ip": client_ip(),
            "imdsv2_required": STATE["imdsv2_required"],
            "has_valid_token": True,
            "status": 200,
        }
    )
    return jsonify(
        step1_put="PUT /latest/api/token  (header X-aws-ec2-metadata-token-ttl-seconds)",
        step1_result={"token": token, "ttl_seconds": ttl},
        step2_get="GET /latest/meta-data/instance-id  (header X-aws-ec2-metadata-token: <token>)",
        step2_result={"instance-id": "i-labtainer0ssrfimds", "status": 200},
        note=(
            "This demonstrates the LEGITIMATE flow from the instance itself (not "
            "through the webapp SSRF bug). The webapp SSRF endpoint /import can ONLY "
            "issue plain GET requests; it cannot send PUT or set arbitrary headers -> "
            "once IMDSv2 is enforced, the classic SSRF exploit chain (Task 2) "
            "fails with a 401 error."
        ),
    )


@app.route("/latest/meta-data/")
@app.route("/latest/meta-data")
def meta_data_root():
    guard = metadata_guard(request.path)
    if guard is not None:
        return guard
    listing = "ami-id\nhostname\niam/\ninstance-id\ninstance-type\nlocal-ipv4\n"
    return Response(listing, mimetype="text/plain")


@app.route("/latest/meta-data/instance-id")
def meta_data_instance_id():
    guard = metadata_guard(request.path)
    if guard is not None:
        return guard
    return Response("i-labtainer0ssrfimds", mimetype="text/plain")


@app.route("/latest/meta-data/hostname")
def meta_data_hostname():
    guard = metadata_guard(request.path)
    if guard is not None:
        return guard
    return Response("finportal.web.internal", mimetype="text/plain")


@app.route("/latest/meta-data/iam/security-credentials/")
@app.route("/latest/meta-data/iam/security-credentials")
def security_credentials_list():
    guard = metadata_guard(request.path)
    if guard is not None:
        return guard
    return Response(ROLE_NAME + "\n", mimetype="text/plain")


@app.route("/latest/meta-data/iam/security-credentials/<role>")
def security_credentials_role(role):
    guard = metadata_guard(request.path)
    if guard is not None:
        return guard
    if role != ROLE_NAME:
        return jsonify(error="role not found"), 404
    return jsonify(load_creds())


@app.route("/latest/api/token", methods=["PUT"])
def api_token():
    ts = now_ts()
    if not check_source_allowed():
        log_access(
            {
                "ts": ts,
                "path": request.path,
                "src_ip": client_ip(),
                "imdsv2_required": STATE["imdsv2_required"],
                "has_valid_token": False,
                "status": 403,
            }
        )
        return (
            jsonify(error="forbidden: metadata service only reachable from the instance itself"),
            403,
        )
    ttl = request.headers.get("X-aws-ec2-metadata-token-ttl-seconds")
    if not ttl:
        return jsonify(error="missing X-aws-ec2-metadata-token-ttl-seconds header"), 400
    try:
        ttl_seconds = min(int(ttl), 21600)
    except ValueError:
        return jsonify(error="invalid ttl"), 400
    token = secrets.token_hex(16)
    STATE["tokens"][token] = time.time() + ttl_seconds
    log_access(
        {
            "ts": ts,
            "path": request.path,
            "src_ip": client_ip(),
            "imdsv2_required": STATE["imdsv2_required"],
            "has_valid_token": True,
            "status": 200,
        }
    )
    return Response(token, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
