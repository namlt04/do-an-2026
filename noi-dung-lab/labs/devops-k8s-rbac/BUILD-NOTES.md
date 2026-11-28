# BUILD NOTES - cloud-k8s-rbac

Hai container, net 172.40.0.0/24: attacker (terminal SV: kubectl/jq/base64/curl,
mo phong shell trong pod bi chiem) va k8s-node (khong terminal, k3s 1 node that,
cong 6443, container privileged mac dinh cua Labtainer).

**Xac thuc:** dung token-auth-file tinh (/opt/k3s/tokens.csv) thay vi SA token
runtime (de ca the hoa qua HASH_REPLACE va chia se cross-container de dang):
  - WEBTOKENSEED -> user web-user (RoleBinding toi Role web-app-role: get/list
    secrets, create pods, pods/exec, get configmaps trong ns app) -> ca the hoa.
  - ADMINTOKENSEED -> admin-user (group system:masters = cluster-admin) de lam
    buoc hardening (NV4), kubeconfig admin ship o ~/.kube/admin-config.
Token web ship o attacker:/var/run/secrets/.../token + ~/.kube/config (HASH_REPLACE
cung 1 gia tri vao ca 3 file, khop voi tokens.csv tren node).

**Cum:** auto-deploy manifest /var/lib/rancher/k3s/server/manifests/lab.yaml dung
san ns app, Role/RoleBinding qua rong, Secret db-credentials, ConfigMap app-config
co secret bi de lan (legacy_api_key). Flag o /opt/host-secrets/flag.txt tren node
(= filesystem cua container k8s-node) -> pod hostPath mount / doc duoc.

**Pod escape offline:** busybox:1.36 keo bang crane luc build -> /opt/k3s/busybox.tar;
fixlocal `k3s ctr images import`; pod escape dung imagePullPolicy: Never.

**k3s trong container (RUI RO CHINH):** chay `k3s server --snapshotter=native`
(tranh overlayfs long nhau), disable traefik/servicelb/metrics. Neu k3s KHONG len
duoc tren VM 3GB/cgroup cua Labtainer -> phuong an du phong: thay k8s-node bang mock
HTTP API (python) tra loi cac endpoint kubectl can + kubectl shim; grading giu nguyen.
Can test tren VM; day la lab nang nhat.

Grader chi grep/sed/awk. Flag HASH_REPLACE BARE.
