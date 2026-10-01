#!/usr/bin/env python3
"""
gate_server.py -- dich vu "CI quality gate" mo phong cho bai dso-iac-scan.

Chay tren container `ci` (172.31.0.20, TERMINALS -1 -> sinh vien KHONG co
shell tren container nay). Lang nghe HTTP tren cong 8000.

Co che chong bypass: khi sinh vien goi ~/gate.sh (chay tren container
`devsecops`), script do dong goi CAC FILE *.tf HIEN TAI trong ~/iac-project
va gui len day qua POST multipart (truong "project"). Dich vu nay:
  1) Giai nen goi tin vao thu muc tam (co chong path traversal/symlink).
  2) TU CHAY tfsec (binary cai san trong image nay, khong can mang) tren ma
     Terraform nhan duoc -- khong tin bat ky "ket qua quet" nao do phia
     sinh vien tu gui len.
  3) Dem so finding muc HIGH/CRITICAL tu ket qua tfsec cua CHINH SERVER.
  4) Chi khi tong = 0, doc gia tri flag tu /opt/gate/flag.env (da duoc
     framework Labtainer thay the bang hash rieng cho tung sinh vien luc
     parameterize -- xem config/parameter.config, HASH_REPLACE) va tra ve
     trong dong "FLAG=<gia_tri>".
  5) Neu > 0, tra ve so loi con lai va danh sach rule vi pham, KHONG co
     dong FLAG=.

Vi sinh vien khong co shell tren container nay, ho khong the:
  - cat truc tiep /opt/gate/flag.env,
  - gia mao "ket qua quet" de gate tu tin,
  - hay sua doi gate_server.py de bo qua kiem tra.
Duong khai thac duy nhat la thuc su sua ma Terraform cho den khi HIGH/
CRITICAL = 0 that su (theo tfsec chay ngay tai day).
"""
import json
import os
import shutil
import subprocess
import tarfile
import tempfile

from flask import Flask, Response, request

app = Flask(__name__)

FLAG_FILE = "/opt/gate/flag.env"
TFSEC_BIN = "/usr/local/bin/tfsec"
MAX_UPLOAD_BYTES = 5 * 1024 * 1024  # 5MB - goi tin chi gom vai file .tf van ban
SCAN_TIMEOUT_SEC = 60


def read_flag():
    """Doc gia tri flag tu FLAG_FILE. Dong dau tien khong rong/khong phai
    comment (#) duoc coi la gia tri flag, da strip khoang trang."""
    try:
        with open(FLAG_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                return line
    except OSError:
        pass
    return ""


def safe_extract(tar, dest_dir):
    """Chan path traversal (../) va symlink/hardlink doc hai khi giai nen
    tar do sinh vien gui len."""
    dest_abs = os.path.abspath(dest_dir)
    for member in tar.getmembers():
        member_path = os.path.abspath(os.path.join(dest_dir, member.name))
        if not (member_path == dest_abs or member_path.startswith(dest_abs + os.sep)):
            raise ValueError("unsafe tar member (path traversal): %s" % member.name)
        if member.issym() or member.islnk():
            raise ValueError("symlink/hardlink not allowed: %s" % member.name)
        if not (member.isfile() or member.isdir()):
            raise ValueError("unsupported tar entry type: %s" % member.name)
    tar.extractall(dest_dir)


def count_high_crit(report_path):
    """Doc bao cao JSON cua tfsec (do CHINH SERVER nay tao ra) va dem so
    finding muc HIGH/CRITICAL. Tra ve (high, crit, results_list)."""
    if not os.path.exists(report_path):
        return 0, 0, []
    try:
        with open(report_path) as f:
            data = json.load(f)
    except (ValueError, OSError):
        return 0, 0, []
    results = data.get("results") or []
    high = sum(1 for r in results if (r.get("severity") or "").upper() == "HIGH")
    crit = sum(1 for r in results if (r.get("severity") or "").upper() == "CRITICAL")
    return high, crit, results


@app.route("/healthz", methods=["GET"])
def healthz():
    return Response("ok\n", status=200, mimetype="text/plain")


@app.route("/gate", methods=["POST"])
def gate():
    if "project" not in request.files:
        return Response(
            "GATE ERROR: thieu truong 'project' (multipart form voi file tar.gz).\n",
            status=400, mimetype="text/plain",
        )

    upload = request.files["project"]
    workdir = tempfile.mkdtemp(prefix="iacgate-")
    try:
        tar_path = os.path.join(workdir, "project.tar.gz")
        upload.save(tar_path)

        if os.path.getsize(tar_path) > MAX_UPLOAD_BYTES:
            return Response("GATE ERROR: goi tin qua lon.\n", status=400, mimetype="text/plain")

        extract_dir = os.path.join(workdir, "proj")
        os.makedirs(extract_dir, exist_ok=True)
        try:
            with tarfile.open(tar_path) as tar:
                safe_extract(tar, extract_dir)
        except Exception as exc:  # noqa: BLE001 - tra loi ro rang cho client
            return Response(
                "GATE ERROR: khong giai nen duoc goi tin: %s\n" % exc,
                status=400, mimetype="text/plain",
            )

        tf_files = [f for f in os.listdir(extract_dir) if f.endswith(".tf")]
        if not tf_files:
            return Response(
                "GATE ERROR: khong tim thay file .tf nao trong goi tin.\n",
                status=400, mimetype="text/plain",
            )

        report_path = os.path.join(workdir, "report.json")
        try:
            subprocess.run(
                [
                    TFSEC_BIN, extract_dir,
                    "--format", "json",
                    "--out", report_path,
                    "--no-color",
                    "--soft-fail",
                ],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=SCAN_TIMEOUT_SEC,
            )
        except Exception as exc:  # noqa: BLE001
            return Response(
                "GATE ERROR: quet that bai tren server: %s\n" % exc,
                status=500, mimetype="text/plain",
            )

        high, crit, results = count_high_crit(report_path)
        total = high + crit

        lines = [
            "CI QUALITY GATE - dso-iac-scan",
            "Ket qua quet DOC LAP tren server 'ci' (tfsec, %d file .tf nhan duoc)" % len(tf_files),
            "HIGH=%d CRITICAL=%d" % (high, crit),
        ]

        if total == 0:
            flag = read_flag()
            lines.append("GATE PASSED: 0 loi muc HIGH/CRITICAL. Ha tang du dieu kien trien khai.")
            lines.append("FLAG=%s" % flag)
            return Response("\n".join(lines) + "\n", status=200, mimetype="text/plain")

        lines.append(
            "GATE FAILED: con %d loi muc HIGH/CRITICAL. Sua tiep roi chay lai ~/gate.sh." % total
        )
        violations = []
        for r in results:
            sev = (r.get("severity") or "").upper()
            if sev not in ("HIGH", "CRITICAL"):
                continue
            rule = r.get("rule_id") or r.get("long_id") or "?"
            loc = r.get("location") or {}
            fname = os.path.basename(str(loc.get("filename", "?")))
            violations.append("  - [%s] %s (%s)" % (sev, rule, fname))
        lines.extend(sorted(set(violations))[:50])
        return Response("\n".join(lines) + "\n", status=200, mimetype="text/plain")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
