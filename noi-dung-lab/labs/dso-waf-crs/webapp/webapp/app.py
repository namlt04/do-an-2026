#!/usr/bin/env python3
# Ung dung web noi bo "imgshop" - CO Y de lo hong (SQLi / reflected XSS /
# path traversal) phuc vu bai lab dso-waf-crs. Chay tren webapp:8080, dat
# sau reverse proxy waf. KHONG dung trong thuc te.
import os

from flask import Flask, Response, request

APP_DIR = os.path.dirname(os.path.abspath(__file__))
# Thu muc "tai lieu san pham" - diem xuat phat cua chuc nang download.
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
    # LO HONG SQLi (minh hoa): ghep thang tham so vao cau truy van, phan chieu
    # lai cho nguoi dung. Khong co CSDL that; muc tiC la tao payload de WAF chan.
    pid = request.args.get("id", "")
    query = "SELECT id,name,price FROM products WHERE id='%s'" % pid
    body = "Truy van thuc thi: %s\nKet qua tra cuu san pham id=%s\n" % (query, pid)
    return Response(body, mimetype="text/plain")


@app.route("/download")
def download():
    # LO HONG Path Traversal: noi thang ten file nguoi dung nhap vao BASE, khong
    # kiem tra/chuan hoa -> cho phep doc file ngoai pham vi (vd ../../../flag1.txt).
    name = request.args.get("file", "")
    target = os.path.join(BASE, name)
    try:
        with open(target, "rb") as fh:
            return Response(fh.read(), mimetype="text/plain")
    except Exception as exc:  # noqa: BLE001
        return Response("error: %s\n" % exc, status=404, mimetype="text/plain")


@app.route("/search")
def search():
    # LO HONG Reflected XSS: phan chieu tham so q vao HTML khong escape.
    q = request.args.get("q", "")
    return Response(
        "<html><body><h2>Ket qua tim kiem</h2>"
        "<p>Ban da tim: %s</p></body></html>" % q,
        mimetype="text/html",
    )


@app.route("/feedback")
def feedback():
    # Chuc nang HOP LE: nguoi dung gui gop y (co the chua tu khoa ky thuat giong
    # payload). Tai tang ung dung LUON tra 200; viec chan nham (false positive)
    # neu co la do WAF/CRS, va duoc khu bang rule exclusion khoanh vung.
    comment = request.args.get("comment", "")
    return Response(
        "<html><body><h2>Cam on ban da gui phan hoi</h2>"
        "<p>Noi dung: %s</p></body></html>" % comment,
        mimetype="text/html",
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
