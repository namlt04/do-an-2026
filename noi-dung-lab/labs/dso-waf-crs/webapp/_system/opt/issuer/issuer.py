#!/usr/bin/env python3
# Flag issuer service for the dso-waf-crs lab. Runs on webapp:8099 (the container
# has NO terminal for the student -> they cannot cat the flag). The flag is only
# issued when the service SELF-VERIFIES the REAL RUNTIME state of the WAF by sending
# a request THROUGH the "waf" reverse proxy and observing the returned code.
#
#   /flag2 : issues Flag 2 when (SQLi through WAF -> 403) AND (valid request -> 200).
#            => ModSecurity is in blocking mode (On) and the proxy works.
#   /flag3 : issues Flag 3 when (valid feedback -> 200) AND (SQLi /product -> 403)
#            AND (real XSS on /feedback -> 403).
#            => the exclusion was written SCOPED (engine not disabled, rules not
#               removed globally): valid functionality works again while attacks stay blocked.
#
# Anti-bypass design: only compares the WAF's real end-state, does not trust any
# file the student self-declares. The flag value is per-student (HASH_REPLACE).
import urllib.error
import urllib.request

from flask import Flask, Response

WAF = "http://waf"  # resolved via ADD-HOST -> 172.38.0.20:80
FLAG2_FILE = "/opt/issuer/flag2.txt"
FLAG3_FILE = "/opt/issuer/flag3.txt"

# Reference payloads. MAY BE TUNED at build time (see BUILD-NOTES) to match the
# real behavior of CRS: benign_feedback must be blocked (403) BEFORE the exclusion and
# allowed (200) AFTER the exclusion; xss_feedback must ALWAYS be blocked (403).
SQLI = "/product?id=1'%20OR%20'1'='1"
BENIGN = "/search?q=ao-thun-mau-xanh"
BENIGN_FEEDBACK = (
    "/feedback?comment=Hay%20them%20nut%20UNION%20SELECT%20va%20ORDER%20BY%20price%20cho%20bang%20gia"
)
XSS_FEEDBACK = "/feedback?comment=%3Cscript%3Edocument.location%3D%27http://evil%27%3C/script%3E"

app = Flask(__name__)


def probe(path):
    """Gui request qua WAF, tra ve ma HTTP (0 neu khong ket noi duoc). Thu lai
    vai lan vi WAF co the dang khoi dong lai sau khi sinh vien doi cau hinh."""
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
        "WAF chua o che do chan hieu luc. Dieu kien: SQLi qua WAF phai tra 403 "
        "va request hop le phai tra 200.\n"
        "Quan sat hien tai: sqli=%d benign=%d\n" % (sqli, benign)
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
        "Dieu kien khu false positive chua thoa. Can: /feedback hop le=200, "
        "SQLi /product=403, XSS /feedback=403.\n"
        "Quan sat hien tai: feedback_hople=%d sqli=%d xss=%d\n"
        % (benign_fb, sqli, xss)
    )
    return Response(msg, status=409, mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8099)
