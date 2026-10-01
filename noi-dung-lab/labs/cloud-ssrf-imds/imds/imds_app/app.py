#!/usr/bin/env python3
"""
imds-mock - gia lap Instance Metadata Service (IMDS) cho bai lab
cloud-ssrf-imds (SecLab PTIT / Do an DevSecOps 2026).

Trong cloud that, IMDS chi nghe tren dia chi link-local 169.254.169.254 va
CHI truy cap duoc TU BEN TRONG chinh may ao gan IAM role do - khong mot may
nao khac (ke ca may khac trong cung VPC) co the goi toi IMDS cua mot instance
khac. Lab nay mo phong dung tinh chat do: cac duong dan /latest/... CHI chap
nhan request co nguon la container 'web' (dong vai "chinh instance gan
role") hoac tu chinh no (127.0.0.1, dung cho /admin/imdsv2-demo). Sinh vien
(client) khong the goi truc tiep - phai di qua loi SSRF cua webapp (dung
vai tro webapp de "muon" vi tri mang cua no), dung nhu ban chat that cua
su co Capital One 2019.

Cac endpoint /admin/* la cong cu quan tri/demo CUA BAI LAB (khong ton tai
tren AWS that) de sinh vien co the bat IMDSv2 va xem minh hoa quy trinh hop
le MA KHONG can shell tren container nay (TERMINALS -1).
"""
import json
import os
import secrets
import time

from flask import Flask, Response, jsonify, request

APP_DIR = os.path.dirname(os.path.abspath(__file__))
# Hardcode (khong dung os.path.expanduser) vi tien trinh nay co the duoc khoi
# dong qua sudo (de bind cong 80), luc do "~" se tro ve /root chu khong phai
# /home/ubuntu - se lam vo hieu duong dan log ma results.config tham chieu.
HOME_DIR = "/home/ubuntu"
CREDS_PATH = os.path.join(APP_DIR, "creds_template.json")
LOG_PATH = os.path.join(HOME_DIR, "imds_access.log")

ROLE_NAME = "web-imgproxy-role"

# Nguon duoc phep goi cac duong dan /latest/* (mo phong "chi trong pham vi
# instance"): IP cua container 'web' va localhost (dung cho /admin/imdsv2-demo
# tu goi chinh no).
ALLOWED_SOURCES = {"172.34.0.20", "127.0.0.1"}

app = Flask(__name__)

STATE = {
    "imdsv2_required": False,
    # token -> expiry epoch seconds
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
    # Container nay khong nam sau reverse proxy trong lab -> dung remote_addr truc tiep.
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
    """Kiem tra nguon + (neu bat IMDSv2) token hop le cho 1 request toi
    /latest/*. Tra ve (Response|None, status). None nghia la duoc phep di tiep."""
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
    """Bat IMDSv2: moi request GET toi /latest/* tu day ve sau BAT BUOC phai
    kem token hop le lay tu PUT /latest/api/token (mo phong hop_limit=1 +
    yeu cau token cua IMDSv2 that)."""
    STATE["imdsv2_required"] = True
    return jsonify(ok=True, imdsv2_required=True,
                    message="Da bat IMDSv2: GET /latest/* tu day can header X-aws-ec2-metadata-token.")


@app.route("/admin/imdsv2-demo")
def admin_imdsv2_demo():
    """Minh hoa quy trinh IMDSv2 HOP LE (PUT lay token -> GET kem token) thuc
    hien tu 'chinh instance' (goi loopback), dung DU LIEU METADATA VO HAI
    (khong phai credential) de khong tao them duong lo credential ngoai
    chuoi SSRF that."""
    ttl = 21600
    token = secrets.token_hex(16)
    STATE["tokens"][token] = time.time() + ttl
    ts = now_ts()
    # Ghi nhan that vao imds_access.log (khong chi mo phong trong JSON tra
    # ve): day la bang chung "co it nhat 1 lan luong token hop le hoat dong
    # dung" ma instr_config/pregrade.sh doi chieu cho goal harden_ssrf_imds.
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
            "Day la minh hoa quy trinh HOP LE tu chinh instance (khong di qua "
            "loi SSRF cua webapp). Endpoint SSRF /fetch cua webapp CHI lam duoc "
            "GET don gian, khong tao duoc request PUT hay gan header tuy y -> "
            "sau khi bat IMDSv2, chuoi khai thac SSRF co dien (Nhiem vu 2) se "
            "that bai voi loi 401."
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
    return Response("web.imgproxy-portal.internal", mimetype="text/plain")


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
