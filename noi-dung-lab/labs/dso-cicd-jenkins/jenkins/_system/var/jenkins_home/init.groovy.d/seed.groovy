import jenkins.model.*
import hudson.security.*
import hudson.model.*
import hudson.tasks.Shell
import jenkins.install.InstallState

def j = Jenkins.instance

// Intentional misconfiguration (for the lesson): no authentication, anonymous full access.
// NO_AUTHENTICATION + UNSECURED + InstallState.RUNNING => skip setup wizard, home
// page returns 200 with the X-Jenkins header, /api/json and /scriptText open to anonymous.
j.setSecurityRealm(SecurityRealm.NO_AUTHENTICATION)
j.setAuthorizationStrategy(AuthorizationStrategy.UNSECURED)
j.setInstallState(InstallState.RUNNING)
try { j.setCrumbIssuer(null) } catch (e) {}
j.save()

def seedFile = new File("/var/jenkins_home/regpass_seed.txt")
def regpass = seedFile.exists() ? seedFile.text.trim() : "changeme"

def name = "build-app"
if (j.getItem(name) == null) {
    def p = j.createProject(FreeStyleProject, name)
    p.setDescription("Build & push image noi bo ACME")
    p.buildersList.add(new Shell(
        "echo '[deploy] dang dang nhap registry noi bo...'\n" +
        "echo 'docker login -u deployer -p ${regpass} registry:5000'\n" +
        "echo '[deploy] docker push registry:5000/acme/app:1.0'\n" +
        "echo '[deploy] hoan tat.'"))
    p.save()
    p.scheduleBuild2(0)
}
