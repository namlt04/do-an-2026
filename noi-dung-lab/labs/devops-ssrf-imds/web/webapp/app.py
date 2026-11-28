#!/usr/bin/env python3
import ipaddress
import json
import os
import socket
import time
import urllib.parse

import requests
import yaml
from flask import Flask, Response, jsonify, request

APP_DIR = os.path.dirname(os.path.abspath(__file__))
HOME_DIR = "/home/ubuntu"
CONFIG_PATH = os.path.join(APP_DIR, "config.yaml")
LOG_PATH = os.path.join(HOME_DIR, "fetch.log")

IMDS_IP = "172.34.0.40"
IMDS_BASE = "http://imds"

IMDS_HOSTNAMES = {"imds", "169.254.169.254", IMDS_IP}
IMDS_IPS = {"169.254.169.254", IMDS_IP}
LOOPBACK_HOSTNAMES = {"127.0.0.1", "localhost", "::1"}

app = Flask(__name__)


def load_config():
    with open(CONFIG_PATH, "r") as f:
        return yaml.safe_load(f) or {}


def save_config(cfg):
    with open(CONFIG_PATH, "w") as f:
        yaml.safe_dump(cfg, f, default_flow_style=False)


def log_fetch(entry):
    ordered = {
        "ts": entry.get("ts"),
        "url": entry.get("url"),
        "host": entry.get("host"),
        "path": entry.get("path"),
        "internal": entry.get("internal"),
        "allowed": entry.get("allowed"),
        "reason": entry.get("reason"),
        "status": entry.get("status"),
    }
    with open(LOG_PATH, "a") as f:
        f.write(json.dumps(ordered) + "\n")


def resolve_host(hostname):
    try:
        ipaddress.ip_address(hostname)
        return [hostname]
    except ValueError:
        pass
    try:
        infos = socket.getaddrinfo(hostname, None)
        return sorted({info[4][0] for info in infos})
    except socket.gaierror:
        return []


def is_internal_target(hostname, resolved_ips):
    host_l = (hostname or "").lower()
    if host_l in LOOPBACK_HOSTNAMES or host_l in IMDS_HOSTNAMES:
        return True
    for ip_str in resolved_ips:
        if ip_str in IMDS_IPS:
            return True
        try:
            ip = ipaddress.ip_address(ip_str)
        except ValueError:
            continue
        if ip.is_loopback or ip.is_link_local or ip.is_private or ip.is_reserved:
            return True
    return False


def matches_deny_cidrs(resolved_ips, deny_cidrs):
    for ip_str in resolved_ips:
        try:
            ip = ipaddress.ip_address(ip_str)
        except ValueError:
            continue
        for cidr in deny_cidrs:
            try:
                if ip in ipaddress.ip_network(cidr, strict=False):
                    return cidr
            except ValueError:
                continue
    return None


PAGE_CSS = (
    "body{font-family:system-ui,Arial,sans-serif;max-width:760px;margin:40px auto;"
    "padding:0 16px;color:#1b2733}h1{color:#0b5}header{border-bottom:2px solid #0b5;"
    "padding-bottom:8px;margin-bottom:20px}input{width:100%;padding:10px;font-size:15px;"
    "box-sizing:border-box}button{padding:10px 18px;font-size:15px;background:#0b5;"
    "color:#fff;border:0;border-radius:4px;cursor:pointer;margin-top:10px}"
    ".muted{color:#64748b;font-size:13px}pre{background:#0f172a;color:#e2e8f0;padding:12px;"
    "border-radius:6px;overflow:auto}a{color:#0b5}"
)


@app.route("/")
def index():
    return (
        "<html><head><meta charset='utf-8'><title>FinPortal</title>"
        "<style>%s</style></head><body>"
        "<header><h1>FinPortal</h1>"
        "<div class='muted'>Financial operations portal &middot; Document Import</div></header>"
        "<p>Paste a <b>link to a document file</b> (invoice/statement) provided by a partner; "
        "the system will download it and display its contents for reconciliation.</p>"
        "<form action='/import' method='get'>"
        "<input name='document_url' placeholder='http://files.partner.example/invoice-2026-01.txt'>"
        "<br><button type='submit'>Import document</button></form>"
        "<p class='muted'>Service: <a href='/health'>/health</a> &middot; "
        "Admin: <a href='/admin'>/admin</a></p>"
        "</body></html>" % PAGE_CSS
    )


@app.route("/health")
def health():
    return jsonify(status="ok", service="finportal")


@app.route("/admin")
def admin_page():
    return (
        "<html><head><meta charset='utf-8'><title>FinPortal - Admin</title>"
        "<style>%s</style></head><body>"
        "<header><h1>FinPortal &middot; Admin</h1></header>"
        "<p>Infrastructure hardening controls (DevOps):</p>"
        "<button onclick=\"call('POST','/admin/enable-imdsv2')\">Enable IMDSv2 for metadata</button> "
        "<button onclick=\"call('POST','/admin/harden')\">Enable SSRF protection (allowlist)</button> "
        "<button onclick=\"call('GET','/admin/status')\">View status</button>"
        "<h3>Result</h3><pre id='out'>(click a button above)</pre>"
        "<p class='muted'><a href='/'>&larr; Back to home</a></p>"
        "<script>"
        "function call(m,u){fetch(u,{method:m}).then(r=>r.json())"
        ".then(j=>{document.getElementById('out').textContent="
        "JSON.stringify(j,null,2);}).catch(e=>{document.getElementById('out')"
        ".textContent='Error: '+e;});}"
        "</script></body></html>" % PAGE_CSS
    )


@app.route("/admin/status")
def admin_status():
    cfg = load_config()
    imds_state = None
    try:
        r = requests.get("%s/admin/status" % IMDS_BASE, timeout=3)
        imds_state = r.json()
    except requests.RequestException:
        imds_state = {"error": "cannot query imds"}
    return jsonify(
        ssrf_protection=bool(cfg.get("ssrf_protection", False)),
        allow_hosts=cfg.get("allow_hosts", []),
        deny_cidrs=cfg.get("deny_cidrs", []),
        imds=imds_state,
    )


@app.route("/admin/harden", methods=["POST"])
def admin_harden():
    cfg = load_config()
    cfg["ssrf_protection"] = True
    cfg.setdefault("allow_hosts", ["files.partner.example"])
    cfg.setdefault(
        "deny_cidrs",
        ["127.0.0.0/8", "169.254.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
    )
    save_config(cfg)
    return jsonify(
        ok=True, ssrf_protection=True,
        message="ssrf_protection enabled: only allow_hosts can be fetched; all other targets (including IMDS) are blocked.",
    )


@app.route("/admin/enable-imdsv2", methods=["POST"])
def admin_enable_imdsv2():
    try:
        r = requests.post("%s/admin/enable-imdsv2" % IMDS_BASE, timeout=5)
        return Response(r.text, status=r.status_code, mimetype="application/json")
    except requests.RequestException as exc:
        return jsonify(ok=False, error="cannot reach imds: %s" % exc), 502


@app.route("/admin/imdsv2-demo")
def admin_imdsv2_demo():
    try:
        r = requests.get("%s/admin/imdsv2-demo" % IMDS_BASE, timeout=5)
        return Response(r.text, status=r.status_code, mimetype="application/json")
    except requests.RequestException as exc:
        return jsonify(ok=False, error="cannot reach imds: %s" % exc), 502


@app.route("/import")
def do_import():
    target = request.args.get("document_url", "")
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    if not target:
        return Response("missing document_url parameter", status=400)

    parsed = urllib.parse.urlsplit(target)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        log_fetch({
            "ts": ts, "url": target, "host": parsed.hostname, "path": parsed.path,
            "internal": None, "allowed": False, "reason": "bad_scheme_or_host", "status": 400,
        })
        return Response("invalid link (only http/https is supported)", status=400)

    cfg = load_config()
    ssrf_protection = bool(cfg.get("ssrf_protection", False))
    allow_hosts = cfg.get("allow_hosts", []) or []
    deny_cidrs = cfg.get("deny_cidrs", []) or []

    resolved_ips = resolve_host(parsed.hostname)
    internal = is_internal_target(parsed.hostname, resolved_ips)

    if ssrf_protection:
        if parsed.hostname in allow_hosts:
            allowed, reason = True, None
        else:
            allowed = False
            hit = matches_deny_cidrs(resolved_ips, deny_cidrs)
            reason = ("deny_cidr:%s" % hit) if hit else "not_in_allow_hosts"
        if not allowed:
            log_fetch({
                "ts": ts, "url": target, "host": parsed.hostname, "path": parsed.path,
                "internal": internal, "allowed": False, "reason": reason, "status": 403,
            })
            return Response("fetch refused (ssrf_protection): %s" % reason, status=403)

    try:
        upstream = requests.get(target, timeout=5)
        body = upstream.text
        status = upstream.status_code
    except requests.RequestException as exc:
        log_fetch({
            "ts": ts, "url": target, "host": parsed.hostname, "path": parsed.path,
            "internal": internal, "allowed": True,
            "reason": "fetch_error:%s" % exc.__class__.__name__, "status": 502,
        })
        return Response("document download error: %s" % exc, status=502)

    log_fetch({
        "ts": ts, "url": target, "host": parsed.hostname, "path": parsed.path,
        "internal": internal, "allowed": True, "reason": None, "status": status,
    })
    return Response(body, status=status, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
