#!/usr/bin/env python3
import os

from flask import Flask, Response, request

APP_DIR = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(APP_DIR, "files")

app = Flask(__name__)


@app.route("/")
def index():
    return Response(
        "<html><body>"
        "<h1>imgshop - internal portal</h1>"
        "<p>Features: "
        "<a href='/product?id=1'>/product</a>, "
        "<a href='/download?file=catalog.txt'>/download</a>, "
        "<a href='/search?q=shirt'>/search</a>, "
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
    pid = request.args.get("id", "")
    query = "SELECT id,name,price FROM products WHERE id='%s'" % pid
    body = "Executed query: %s\nProduct lookup result for id=%s\n" % (query, pid)
    return Response(body, mimetype="text/plain")


@app.route("/download")
def download():
    name = request.args.get("file", "")
    target = os.path.join(BASE, name)
    try:
        with open(target, "rb") as fh:
            return Response(fh.read(), mimetype="text/plain")
    except Exception as exc:  # noqa: BLE001
        return Response("error: %s\n" % exc, status=404, mimetype="text/plain")


@app.route("/search")
def search():
    q = request.args.get("q", "")
    return Response(
        "<html><body><h2>Search results</h2>"
        "<p>You searched for: %s</p></body></html>" % q,
        mimetype="text/html",
    )


@app.route("/feedback")
def feedback():
    comment = request.args.get("comment", "")
    return Response(
        "<html><body><h2>Thank you for your feedback</h2>"
        "<p>Content: %s</p></body></html>" % comment,
        mimetype="text/html",
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
