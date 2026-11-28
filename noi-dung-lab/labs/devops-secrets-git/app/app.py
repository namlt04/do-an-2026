#!/usr/bin/env python3
import json
import os
import secrets
import subprocess
from pathlib import Path

from flask import Flask, jsonify, request

app = Flask(__name__)

HOME = Path(os.environ.get("HOME", "/home/ubuntu"))
STATE_DIR = HOME / "state"
STATE_FILE = STATE_DIR / "creds_state.json"
FLAG_API_FILE = HOME / "flag_api.txt"
FLAG_ROTATE_FILE = HOME / "flag_rotate.txt"

LEAKED_DB_USER = "appuser"
LEAKED_DB_PASSWORD = "S3cr3t-DB-Pw-2024!"
LEAKED_API_TOKEN = "app_tok_5f4e3d2c1b0a9988776655443322110f"
LEAKED_AWS_ACCESS_KEY_ID = "AKIAZ7Q2X8VNK4RPDLW3"
LEAKED_AWS_SECRET_ACCESS_KEY = "wWw0kQfZ9pL3xR7bN2sV6yH1tG4mD8cU5aJ0eKqP"

MINIO_ROOT_USER = "miniolabadmin"
MINIO_ROOT_PASSWORD = "Lab-Adm1n-R00t-2024-DoNotShare"
MINIO_ENDPOINT = os.environ.get("STORAGE_ENDPOINT", "http://storage:9000")
MC_ADMIN_ALIAS = "labadmin"


def _default_state():
    return {
        "db_password": LEAKED_DB_PASSWORD,
        "api_token": LEAKED_API_TOKEN,
        "rotated": False,
    }


def _load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except Exception:
            pass
    return _default_state()


def _save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state))


def _read_flag(path):
    try:
        return path.read_text().strip()
    except Exception:
        return None


@app.route("/", methods=["GET"])
def index():
    return jsonify({"service": "corp-backend internal API", "status": "up"})


@app.route("/flag", methods=["GET"])
def get_flag():
    state = _load_state()

    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):].strip()
        if token and secrets.compare_digest(token, state.get("api_token", "")):
            return jsonify({
                "status": "ok",
                "auth_method": "bearer",
                "flag": _read_flag(FLAG_API_FILE),
            })
        return jsonify({"error": "invalid bearer token"}), 401

    auth = request.authorization
    if auth and auth.username == LEAKED_DB_USER and \
            secrets.compare_digest(auth.password or "", state.get("db_password", "")):
        return jsonify({
            "status": "ok",
            "auth_method": "basic",
            "flag": _read_flag(FLAG_API_FILE),
        })

    resp = jsonify({"error": "unauthorized"})
    resp.status_code = 401
    resp.headers["WWW-Authenticate"] = 'Basic realm="corp-backend"'
    return resp


@app.route("/admin/rotate", methods=["POST"])
def admin_rotate():
    body = request.get_json(silent=True) or {}
    proven = (
        body.get("aws_access_key_id") == LEAKED_AWS_ACCESS_KEY_ID
        and body.get("aws_secret_access_key") == LEAKED_AWS_SECRET_ACCESS_KEY
        and body.get("db_password") == LEAKED_DB_PASSWORD
        and body.get("api_token") == LEAKED_API_TOKEN
    )
    if not proven:
        return jsonify({
            "error": "credentials do not match the known leaked set; rotate refused"
        }), 403

    state = _load_state()
    if not state.get("rotated"):
        state["db_password"] = secrets.token_urlsafe(18)
        state["api_token"] = secrets.token_hex(20)
        state["rotated"] = True
        _save_state(state)
        _disable_leaked_minio_key()

    return jsonify({"status": "rotated", "rotate_flag": _read_flag(FLAG_ROTATE_FILE)})


def _disable_leaked_minio_key():
    try:
        subprocess.run(
            ["mc", "alias", "set", MC_ADMIN_ALIAS, MINIO_ENDPOINT,
             MINIO_ROOT_USER, MINIO_ROOT_PASSWORD],
            check=False, capture_output=True, timeout=15,
        )
        result = subprocess.run(
            ["mc", "admin", "user", "disable", MC_ADMIN_ALIAS, LEAKED_AWS_ACCESS_KEY_ID],
            check=False, capture_output=True, timeout=15,
        )
        if result.returncode != 0:
            app.logger.warning(
                "mc admin user disable rc=%s stderr=%s",
                result.returncode, result.stderr.decode(errors="replace"),
            )
    except Exception as exc:
        app.logger.warning("cannot disable key on storage: %s", exc)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
