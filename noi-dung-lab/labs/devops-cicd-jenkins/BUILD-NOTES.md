# BUILD NOTES - dso-cicd-jenkins

Ba container, net 172.39.0.0/24: client (terminal SV: curl/jq), jenkins
(khong terminal, Jenkins LTS 2.462.3 that tren OpenJDK 17, cong 8080),
registry (khong terminal, Docker Registry v2 binary that, cong 5000).

**Jenkins THAT nhung KHONG plugin** (tranh phai nap plugin offline): chay voi
`-Djenkins.install.runSetupWizard=false`; init.groovy.d/seed.groovy dat
AuthorizationStrategy.UNSECURED (an danh toan quyen -> /scriptText RCE an danh),
tao job freestyle `build-app` co shell step in ra `docker login -u deployer -p
<regpass>` nen credential lo ca trong config.xml lan consoleText, va trigger 1
build. flag_ci o /var/jenkins_home/flag_ci.txt (doc qua Groovy RCE).

**Registry**: binary distribution v2.8.3, Basic Auth htpasswd (bcrypt) tao luc
fixlocal tu regpass per-student. `regseed.py` (python stdlib) dung san storage
v2 (blobs + manifest schema2 + tag links) cho image acme/app:1.0, layer tar.gz
chua flag_pivot per-student -> digest tinh dung tu noi dung that. SV: curl -u
deployer:<pass> /v2/acme/app/manifests/1.0 -> lay layer digest -> GET blob ->
giai nen -> flag_pivot.

**Hardening** (NV5): SV dung chinh RCE gui Groovy dat HudsonPrivateSecurityRealm
+ FullControlOnceLoggedInAuthorizationStrategy (setAllowAnonymousRead(false)) -
deu la API core, khong can plugin matrix-auth. Sau do an danh -> 403. Verify
tu client, luu harden_verify.txt.

Offline: jenkins.war + registry binary + openjdk tai luc build. Flag HASH_REPLACE
BARE. RAM: JVM Jenkins ~0.6-1GB, test rieng lab nay. Grader chi grep/sed/awk.
