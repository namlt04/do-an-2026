#!/usr/bin/env python3
import re
import subprocess

from flask import Flask, Response

CORAZA_CONF = "/etc/coraza/coraza.conf"
EXCL_CONF = "/etc/coraza/custom-rules.conf"

EXCLUSION_BLOCK = """# wafctl: scoped exclusion for /feedback?comment
SecRule REQUEST_URI "@beginsWith /feedback" \
  "id:100001,phase:1,pass,nolog,\
   ctl:ruleRemoveTargetById=942100;ARGS:comment,\
   ctl:ruleRemoveTargetById=942110;ARGS:comment,\
   ctl:ruleRemoveTargetById=942150;ARGS:comment,\
   ctl:ruleRemoveTargetById=942190;ARGS:comment,\
   ctl:ruleRemoveTargetById=942200;ARGS:comment,\
   ctl:ruleRemoveTargetById=942260;ARGS:comment,\
   ctl:ruleRemoveTargetById=942270;ARGS:comment,\
   ctl:ruleRemoveTargetById=942280;ARGS:comment,\
   ctl:ruleRemoveTargetById=942430;ARGS:comment,\
   ctl:ruleRemoveTargetById=942431;ARGS:comment,\
   ctl:ruleRemoveTargetById=942440;ARGS:comment,\
   ctl:ruleRemoveTargetById=942450;ARGS:comment"
"""

app = Flask(__name__)


def restart_waf():
    r = subprocess.run(["systemctl", "restart", "caddy.service"],
                       capture_output=True, text=True)
    import time, urllib.request, urllib.error
    for _ in range(30):
        try:
            urllib.request.urlopen("http://localhost:80/", timeout=2)
            break
        except urllib.error.HTTPError:
            break
        except Exception:
            time.sleep(1)
    return r.returncode == 0, r.stderr


def set_engine(mode):
    with open(CORAZA_CONF) as handle:
        data = handle.read()
    data = re.sub(r"(?m)^SecRuleEngine .*$", "SecRuleEngine %s" % mode, data)
    with open(CORAZA_CONF, "w") as handle:
        handle.write(data)


@app.route("/health")
def health():
    return Response("ok\n", mimetype="text/plain")


@app.route("/engine-on", methods=["POST", "GET"])
def engine_on():
    set_engine("On")
    ok, err = restart_waf()
    return Response("engine=On restarted=%s\n%s" % (ok, err), mimetype="text/plain")


@app.route("/apply-exclusion", methods=["POST", "GET"])
def apply_exclusion():
    with open(EXCL_CONF, "w") as handle:
        handle.write(EXCLUSION_BLOCK)
    ok, err = restart_waf()
    return Response("exclusion=applied restarted=%s\n%s" % (ok, err), mimetype="text/plain")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9091)
