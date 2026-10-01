#!/usr/bin/env python3
"""
dso-secrets-git : app — HTTP API muc tieu (cong 8080)
------------------------------------------------------------------------------
GET  /flag
    Yeu cau xac thuc bang MOT trong hai cach:
      - Header "Authorization: Bearer <API_TOKEN>", HOAC
      - HTTP Basic Auth voi <DB_USER>:<DB_PASSWORD>
    Neu credential dung voi trang thai HIEN TAI (chua rotate hoac da rotate
    deu duoc, mien la dung), tra ve flag rieng cho tung sinh vien (da duoc
    framework Labtainer thay the qua co che HASH_REPLACE truoc khi container
    nay khoi dong dich vu).

POST /admin/rotate
    Nhan JSON {aws_access_key_id, aws_secret_access_key, db_password,
    api_token}. Day la buoc "chung minh da phat hien dung su co ro ri" truoc
    khi duoc phep rotate — cac gia tri gui len phai khop CHINH XAC voi bo
    credential GOC tung bi lo trong lich su Git tren may dev. Neu dung:
      - Sinh DB password / API token MOI, ghi de trang thai hien tai (gia tri
        CU tren chinh dich vu nay het hieu luc ngay lap tuc).
      - Goi sang storage (MinIO) de VO HIEU HOA AWS access key gia (thong qua
        tai khoan admin NOI BO cua rieng app, khong lien quan gi den Git
        history hay may dev).
      - Tra ve "rotate proof" — flag thu ba, rieng cho tung sinh vien.

Sinh vien KHONG co shell tren container nay (TERMINALS -1 trong start.config)
nen khong the doc truc tiep source file nay hay cac file flag_*.txt; chi co
the lay du lieu qua dung 2 endpoint noi tren, va chi khi xac thuc thanh cong.
------------------------------------------------------------------------------
"""
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

# ---- Gia tri "goc" tung bi lo trong lich su Git tren may dev ----------------
# PHAI KHOP CHINH XAC voi dev/_bin/fixlocal.sh va storage/_bin/fixlocal.sh.
LEAKED_DB_USER = "appuser"
LEAKED_DB_PASSWORD = "S3cr3t-DB-Pw-2024!"
LEAKED_API_TOKEN = "app_tok_5f4e3d2c1b0a9988776655443322110f"
LEAKED_AWS_ACCESS_KEY_ID = "AKIAZ7Q2X8VNK4RPDLW3"
LEAKED_AWS_SECRET_ACCESS_KEY = "wWw0kQfZ9pL3xR7bN2sV6yH1tG4mD8cU5aJ0eKqP"

# ---- Tai khoan admin NOI BO de dieu phoi MinIO -----------------------------
# KHONG bao gio nhung vao Git history hay bat ky noi nao sinh vien co the doc
# duoc (dev khong co shell tren app/storage). Dung de rotate AWS key gia.
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
    """Vo hieu hoa AWS key gia tren MinIO (storage) bang tai khoan admin noi bo."""
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
    except Exception as exc:  # best-effort: khong duoc lam sap API vi loi phia MinIO
        app.logger.warning("khong the vo hieu hoa key tren storage: %s", exc)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
