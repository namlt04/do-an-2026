#!/usr/bin/env python3
import urllib.error
import urllib.request

from flask import Flask, Response

WAF = "http://waf"
FLAG2_FILE = "/opt/issuer/flag2.txt"
FLAG3_FILE = "/opt/issuer/flag3.txt"

SQLI = "/product?id=1'%20OR%20'1'='1"
BENIGN = "/search?q=blue-shirt"
BENIGN_FEEDBACK = (
    "/feedback?comment=Please%20add%20UNION%20SELECT%20and%20ORDER%20BY%20price%20to%20the%20price%20list"
)
XSS_FEEDBACK = "/feedback?comment=%3Cscript%3Edocument.location%3D%27http://evil%27%3C/script%3E"

app = Flask(__name__)


def probe(path):
    import time
    for attempt in range(4):
        try:
            resp = urllib.request.urlopen(urllib.request.Request(WAF + path), timeout=6)
            return resp.getcode()
        except urllib.error.HTTPError as exc:
            return exc.code
        except Exception:  # noqa: BLE001
            time.sleep(1.5)
    return 0


def read_flag(path):
    with open(path) as handle:
        return handle.read().strip()


@app.route("/health")
def health():
    return Response("ok\n", mimetype="text/plain")


@app.route("/flag2")
def flag2():
    sqli = probe(SQLI)
    benign = probe(BENIGN)
    if sqli == 403 and benign == 200:
        return Response(read_flag(FLAG2_FILE) + "\n", mimetype="text/plain")
    msg = (
        "WAF is not in effective blocking mode. Required: SQLi through the WAF must return 403 "
        "and a valid request must return 200.\n"
        "Current observation: sqli=%d benign=%d\n" % (sqli, benign)
    )
    return Response(msg, status=409, mimetype="text/plain")


@app.route("/flag3")
def flag3():
    benign_fb = probe(BENIGN_FEEDBACK)
    sqli = probe(SQLI)
    xss = probe(XSS_FEEDBACK)
    if benign_fb == 200 and sqli == 403 and xss == 403:
        return Response(read_flag(FLAG3_FILE) + "\n", mimetype="text/plain")
    msg = (
        "False-positive tuning conditions not met. Required: valid /feedback=200, "
        "SQLi /product=403, XSS /feedback=403.\n"
        "Current observation: feedback_valid=%d sqli=%d xss=%d\n"
        % (benign_fb, sqli, xss)
    )
    return Response(msg, status=409, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8099)
