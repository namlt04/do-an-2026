#!/usr/bin/env python3
# Dich vu phat flag cua bai lab dso-waf-crs. Chay tren webapp:8099 (container
# KHONG co terminal cho sinh vien -> khong the cat flag). Flag chi duoc phat khi
# dich vu TU KIEM CHUNG trang thai RUNTIME THAT cua WAF bang cach gui request
# QUA reverse proxy "waf" va quan sat ma tra ve.
#
#   /flag2 : phat Flag 2 khi (SQLi qua WAF -> 403) VA (request hop le -> 200).
#            => ModSecurity dang o che do chan (On) va proxy hoat dong.
#   /flag3 : phat Flag 3 khi (feedback hop le -> 200) VA (SQLi /product -> 403)
#            VA (XSS that tren /feedback -> 403).
#            => exclusion da duoc viet KHOANH VUNG (khong tat engine, khong bo
#               rule toan cuc): chuc nang hop le hoat dong lai ma tan cong van bi chan.
#
# Thiet ke chong bypass: chi so sanh end-state that cua WAF, khong tin bat ky
# file nao sinh vien tu khai. Gia tri flag la per-student (HASH_REPLACE).
import urllib.error
import urllib.request

from flask import Flask, Response

WAF = "http://waf"  # resolve qua ADD-HOST -> 172.38.0.20:80
FLAG2_FILE = "/opt/issuer/flag2.txt"
FLAG3_FILE = "/opt/issuer/flag3.txt"

# Cac payload tham chieu. CO THE TINH CHINH luc build (xem BUILD-NOTES) de khop
# hanh vi thuc te cua CRS: benign_feedback phai bi chan (403) TRUOC exclusion va
# duoc phep (200) SAU exclusion; xss_feedback phai LUON bi chan (403).
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
