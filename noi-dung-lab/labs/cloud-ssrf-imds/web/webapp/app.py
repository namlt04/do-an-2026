#!/usr/bin/env python3
"""
imgproxy-portal - ung dung web mo phong chuc nang "xem truoc anh theo URL"
cua mot cong ty tai chinh gia dinh. Duoc CO Y dinh loi SSRF (Server-Side
Request Forgery) o endpoint /fetch khi cau hinh ssrf_protection=false (mac
dinh luc khoi dong lab).

Day la MA NGUON CUA BAI LAB cloud-ssrf-imds (SecLab PTIT / Do an DevSecOps
2026), dung de tai hien chuoi su co Capital One 2019 (SSRF -> IMDS ->
credential tam thoi -> object storage). KHONG dung lam tham khao cho ma
nguon san xuat thuc te - endpoint /admin/* o day KHONG co xac thuc, chi
phuc vu muc dich "cong tac hardening" ma sinh vien goi truc tiep qua curl
(container nay khong cap terminal/shell cho sinh vien - TERMINALS -1).
"""
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
# Hardcode (khong dung os.path.expanduser) de tranh sai lech neu tien trinh
# duoc khoi dong duoi ngu canh khac ubuntu (vd qua sudo).
HOME_DIR = "/home/ubuntu"
CONFIG_PATH = os.path.join(APP_DIR, "config.yaml")
LOG_PATH = os.path.join(HOME_DIR, "fetch.log")

# Cac "bi danh" cua dich vu IMDS gia trong lab nay. Dia chi that cua IMDS
# tren cloud la link-local 169.254.169.254; trong moi truong Labtainer,
# duong dan CHAC CHAN hoat dong la ten DNS noi bo "imds" (172.34.0.40, xem
# BUILD-NOTES.md). Ca hai deu duoc coi la "dich noi bo/nhay cam" khi ghi log.
IMDS_HOSTNAMES = {"imds", "169.254.169.254", "172.34.0.40"}
IMDS_IPS = {"169.254.169.254", "172.34.0.40"}
LOOPBACK_HOSTNAMES = {"127.0.0.1", "localhost", "::1"}

app = Flask(__name__)


def load_config():
    with open(CONFIG_PATH, "r") as f:
        return yaml.safe_load(f) or {}


def save_config(cfg):
    with open(CONFIG_PATH, "w") as f:
        yaml.safe_dump(cfg, f, default_flow_style=False)


def log_fetch(entry):
    """Ghi 1 dong JSON (thu tu truong CO DINH) vao fetch.log. day la bang
    chung chinh de cham diem discover_ssrf / steal_credentials / hardening -
    sinh vien khong co shell tren container web nen khong the sua file nay."""
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
    """Tra ve danh sach IP (string) ma hostname phan giai toi. Neu hostname
    da la mot literal IP thi tra ve chinh no (khong qua DNS/hosts)."""
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
    """True neu dich la loopback cua webapp, la IMDS gia (duoi bat ky bi
    danh nao), hoac roi vao dai IP rieng/link-local noi chung."""
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


@app.route("/")
def index():
    return (
        "<html><body>"
        "<h1>imgproxy-portal</h1>"
        "<p>Dan URL anh de xem truoc, he thong se tai ho (server-side fetch).</p>"
        "<form action='/fetch' method='get'>"
        "<input name='url' style='width:420px' "
        "placeholder='http://images.trusted.example/pic.jpg'>"
        "<button type='submit'>Preview</button></form>"
        "<p><a href='/health'>/health</a></p>"
        "</body></html>"
    )


@app.route("/health")
def health():
    return jsonify(status="ok", service="imgproxy-portal")


@app.route("/admin/status")
def admin_status():
    cfg = load_config()
    return jsonify(
        ssrf_protection=bool(cfg.get("ssrf_protection", False)),
        allow_hosts=cfg.get("allow_hosts", []),
        deny_cidrs=cfg.get("deny_cidrs", []),
    )


@app.route("/admin/harden", methods=["POST"])
def admin_harden():
    """Ap dung ban va chong SSRF: bat allowlist host + chan cac dai IP noi
    bo/link-local (bao gom IMDS gia). Mo phong thao tac push cau hinh qua
    kenh quan tri/CI-CD (khong can SSH vao webapp de sua file va restart
    thu cong, vi container nay khong cap shell cho sinh vien)."""
    cfg = load_config()
    cfg["ssrf_protection"] = True
    cfg.setdefault("allow_hosts", ["images.trusted.example"])
    cfg.setdefault(
        "deny_cidrs",
        [
            "127.0.0.0/8",
            "169.254.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
        ],
    )
    save_config(cfg)
    return jsonify(
        ok=True,
        ssrf_protection=True,
        message="Da bat ssrf_protection: chi allow_hosts duoc fetch, moi dich khac (ke ca IMDS) bi chan.",
    )


@app.route("/fetch")
def fetch():
    target = request.args.get("url", "")
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    if not target:
        return Response("missing url parameter", status=400)

    parsed = urllib.parse.urlsplit(target)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        log_fetch(
            {
                "ts": ts,
                "url": target,
                "host": parsed.hostname,
                "path": parsed.path,
                "internal": None,
                "allowed": False,
                "reason": "bad_scheme_or_host",
                "status": 400,
            }
        )
        return Response("invalid url (chi ho tro http/https)", status=400)

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
            log_fetch(
                {
                    "ts": ts,
                    "url": target,
                    "host": parsed.hostname,
                    "path": parsed.path,
                    "internal": internal,
                    "allowed": False,
                    "reason": reason,
                    "status": 403,
                }
            )
            return Response("blocked host (ssrf_protection): %s" % reason, status=403)

    # --- hanh vi cot loi (co y dinh loi): server tai ho URL, khong kiem tra dich ---
    try:
        upstream = requests.get(target, timeout=5)
        body = upstream.text
        status = upstream.status_code
    except requests.RequestException as exc:
        log_fetch(
            {
                "ts": ts,
                "url": target,
                "host": parsed.hostname,
                "path": parsed.path,
                "internal": internal,
                "allowed": True,
                "reason": "fetch_error:%s" % exc.__class__.__name__,
                "status": 502,
            }
        )
        return Response("upstream fetch error: %s" % exc, status=502)

    log_fetch(
        {
            "ts": ts,
            "url": target,
            "host": parsed.hostname,
            "path": parsed.path,
            "internal": internal,
            "allowed": True,
            "reason": None,
            "status": status,
        }
    )
    return Response(body, status=status, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
