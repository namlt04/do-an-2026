#!/usr/bin/env python3
# Internal web app "imgshop" - DELIBERATELY vulnerable (SQLi / reflected XSS /
# path traversal) for the dso-waf-crs lab. Runs on webapp:8080, placed
# behind the waf reverse proxy. NOT for real-world use.
import os

from flask import Flask, Response, request

APP_DIR = os.path.dirname(os.path.abspath(__file__))
# The "product documents" directory - starting point of the download feature.
BASE = os.path.join(APP_DIR, "files")

app = Flask(__name__)


@app.route("/")
def index():
    return Response(
        "<html><body>"
        "<h1>imgshop - cong noi bo</h1>"
        "<p>Cac chuc nang: "
        "<a href='/product?id=1'>/product</a>, "
        "<a href='/download?file=catalog.txt'>/download</a>, "
        "<a href='/search?q=ao'>/search</a>, "
        "<a href='/feedback?comment=hi'>/feedback</a>, "
        "<a href='/health'>/health</a></p>"
        "</body></html>",
        mimetype="text/html",
    )


@app.route("/health")
def health():
    return Response("ok\n", mimetype="text/plain")


@app.route("/product")
def product():
    # SQLi VULNERABILITY (demo): concatenates the parameter straight into the query,
    # reflected back to the user. No real DB; the goal is to craft a payload for the WAF to block.
    pid = request.args.get("id", "")
    query = "SELECT id,name,price FROM products WHERE id='%s'" % pid
    body = "Truy van thuc thi: %s\nKet qua tra cuu san pham id=%s\n" % (query, pid)
    return Response(body, mimetype="text/plain")


@app.route("/download")
def download():
    # Path Traversal VULNERABILITY: joins the user-supplied filename straight onto BASE,
    # no validation/normalization -> allows reading files outside scope (e.g. ../../../flag1.txt).
    name = request.args.get("file", "")
    target = os.path.join(BASE, name)
    try:
        with open(target, "rb") as fh:
            return Response(fh.read(), mimetype="text/plain")
    except Exception as exc:  # noqa: BLE001
        return Response("error: %s\n" % exc, status=404, mimetype="text/plain")


@app.route("/search")
def search():
    # Reflected XSS VULNERABILITY: reflects the q parameter into HTML without escaping.
    q = request.args.get("q", "")
    return Response(
        "<html><body><h2>Ket qua tim kiem</h2>"
        "<p>Ban da tim: %s</p></body></html>" % q,
        mimetype="text/html",
    )


@app.route("/feedback")
def feedback():
    # LEGITIMATE feature: the user submits feedback (which may contain technical
    # keywords resembling a payload). At the app layer it ALWAYS returns 200; any wrong
    # blocking (false positive) comes from the WAF/CRS, and is removed with a scoped exclusion rule.
    comment = request.args.get("comment", "")
    return Response(
        "<html><body><h2>Cam on ban da gui phan hoi</h2>"
        "<p>Noi dung: %s</p></body></html>" % comment,
        mimetype="text/html",
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
