# HƯỚNG DẪN THỰC HÀNH — Lab 10: Leo thang đặc quyền Kubernetes (RBAC)

- **Mã lab:** `cloud-k8s-rbac`
- **Mức độ:** 4/4 (Chuyên sâu)
- **Công cụ:** `kubectl`, `base64`, `jq`
- **Kiến thức cần:** RBAC (ServiceAccount, Role/RoleBinding, verbs/resources), Secret vs ConfigMap, Pod spec, `hostPath` volume, Pod Security Standards

> Guide này mức **4/4**: chỉ cho **mục tiêu + hướng tiếp cận + tài liệu tham khảo**, **không cho câu lệnh sẵn**. Bạn phải tự tra cú pháp `kubectl` và tự dựng lệnh/manifest. Mục đích: rèn tư duy tấn công–phòng thủ thật sự. (Nếu bí, xem phần "Gợi ý mở rộng" ở cuối mỗi nhiệm vụ.)

## Bối cảnh
Bạn đang có chỗ đứng trong một pod với **ServiceAccount bị cấp quyền quá rộng**. Mục tiêu: lạm dụng RBAC để đọc secret và **thoát ra node**, đọc flag trên host; sau đó vá tận gốc.

Sơ đồ: máy `attacker` (có terminal, `kubectl` + 2 kubeconfig: của SA bị chiếm `~/.kube/config` và admin `~/.kube/admin-config`) ↔ `k8s-node` (node k3s thật). Namespace `app` chứa `Secret db-credentials`, `ConfigMap app-config` (có secret để lẫn), và flag trên host tại `/opt/host-secrets/flag.txt`.

## Khởi động
```bash
imodule https://github.com/namlt04/do-an-2026/raw/refs/heads/master/imodule/cloud-k8s-rbac.tar
labtainer cloud-k8s-rbac
```

---

## Câu lệnh tham khảo (cú pháp chung — tự ghép, tự điền `<...>`)

| Mục đích | Cú pháp chung |
|---|---|
| Tự kiểm tra quyền của mình | `kubectl auth can-i <VERB> <RESOURCE> -n <NAMESPACE>` |
| Đọc & giải mã Secret | `kubectl get secret <TÊN> -n <NS> -o jsonpath='{.data.<KEY>}' \| base64 -d` |
| Xem toàn bộ ConfigMap | `kubectl get configmap <TÊN> -n <NS> -o yaml` |
| Tạo & chờ pod, exec lệnh | `kubectl apply -f <FILE>.yaml` · `kubectl wait --for=condition=Ready pod/<TÊN> -n <NS>` · `kubectl exec <TÊN> -n <NS> -- <CMD>` |
| Chuyển sang kubeconfig admin | `export KUBECONFIG=~/.kube/admin-config` |
| Gắn nhãn Pod Security | `kubectl label ns <NS> pod-security.kubernetes.io/enforce=restricted --overwrite` |

> Đây chỉ là "từ vựng" lệnh. Bài mức 4/4: bạn tự tra tài liệu `kubectl`, tự dựng manifest Pod hostPath và tự ghép chuỗi khai thác.

---

## Nhiệm vụ 1 & 2 — Trinh sát RBAC và moi secret
**Mục tiêu:**
- Xác định ServiceAccount hiện có **những quyền gì** trong namespace `app` (đặc biệt: có list được `secrets` và create được `pods` không?).
- Đọc **mật khẩu DB** trong Secret `db-credentials`, và phát hiện **secret bị để lẫn trong ConfigMap** `app-config`.

**Hướng tiếp cận (tự dựng lệnh):**
- `kubectl` có lệnh chuyên để **tự kiểm tra quyền của chính mình** (gợi ý: nhóm `auth`).
- Dữ liệu trong Secret được mã hoá **base64** — phải giải mã sau khi đọc.
- ConfigMap là nơi *không* nên chứa secret; hãy xem toàn bộ nội dung nó (dạng yaml) và tìm field khả nghi.

**Hoàn thành khi:** ghi được quyền (list secrets / create pods) và trích được mật khẩu DB + khoá lạ trong ConfigMap vào file bằng chứng ở `~` (xem phần Chấm điểm để biết tên file & nội dung cần có).

**Câu hỏi:** Vì sao cấp `list secrets` cho một SA ứng dụng web là nguy hiểm? → ____

<details><summary>Gợi ý mở rộng</summary>

- Kiểm tra quyền: `kubectl auth can-i <verb> <resource> -n app`.
- Giải mã Secret: lấy field `.data.<key>` rồi `base64 -d`.
- Xem ConfigMap: `kubectl get configmap <ten> -n app -o yaml`.
</details>

---

## Nhiệm vụ 3 — Thoát ra node qua pod hostPath
**Mục tiêu:** Lợi dụng quyền **tạo pod** để triển khai một pod **mount toàn bộ filesystem của node** (`hostPath: /`) rồi đọc flag trên host (`/opt/host-secrets/flag.txt`).

**Hướng tiếp cận (tự viết manifest):**
- Viết một Pod manifest (YAML) có **`volumes` kiểu `hostPath`** trỏ `path: /`, mount vào container tại `/host`.
- Chọn image nhẹ **có sẵn trên node** (không kéo mạng — chú ý `imagePullPolicy`).
- Sau khi pod `Ready`, dùng `kubectl exec` để đọc file flag qua đường `/host/...`.

**Hoàn thành khi:** đọc được flag và lưu vào `~/flag.txt`.

**Câu hỏi:** Vì sao `hostPath` + quyền tạo pod ≈ quyền root trên node? → ____

<details><summary>Gợi ý mở rộng</summary>

- Pod cần: `spec.volumes[].hostPath.path: /` và `containers[].volumeMounts[].mountPath: /host`.
- Image nên dùng loại đã có sẵn trên node, đặt `imagePullPolicy: Never`.
- `kubectl apply -f <file>.yaml` → `kubectl wait --for=condition=Ready pod/<ten> -n app` → `kubectl exec <ten> -n app -- cat /host/opt/host-secrets/flag.txt`.
</details>

---

## Nhiệm vụ 4 — Khắc phục (least privilege + Pod Security)
**Mục tiêu:** Dùng **kubeconfig admin** để thay Role quá rộng bằng **Role tối thiểu** (chỉ cho phép đọc đúng ConfigMap cần thiết) **và** bật **Pod Security Standards** mức `restricted` cho namespace. Kiểm chứng SA **không còn** quyền list secrets / create pods.

**Hướng tiếp cận:**
- Chuyển sang dùng `~/.kube/admin-config`.
- Định nghĩa một `Role` mới: chỉ `get` trên `configmaps` với `resourceNames` giới hạn; áp cho namespace `app` (thay binding cũ).
- Gắn nhãn Pod Security `restricted` cho namespace (`pod-security.kubernetes.io/enforce=restricted`).
- Quay lại kubeconfig của SA và **chứng minh** quyền đã bị thu hẹp.

**Hoàn thành khi:** `kubectl auth can-i list secrets -n app` trả về **no**, và ghi bằng chứng vào `~/harden_verify.txt`.

**Câu hỏi:** Least privilege và Pod Security Standards mỗi cái chặn bước tấn công nào ở trên? → ____

<details><summary>Gợi ý mở rộng</summary>

- `export KUBECONFIG=~/.kube/admin-config` trước khi vá; đổi lại `~/.kube/config` khi kiểm chứng.
- Role tối thiểu: `rules: [{apiGroups:[""], resources:["configmaps"], resourceNames:["app-config"], verbs:["get"]}]`.
- `kubectl label ns app pod-security.kubernetes.io/enforce=restricted --overwrite`.
</details>

---

## Chấm điểm
```bash
checkwork cloud-k8s-rbac
```
Đạt khi 4 mục tiêu = **Y**: `recon_rbac`, `loot_secrets`, `escape_node`, `harden_cluster`.

**Bằng chứng cần tạo (tên file ở `~`):**
- `~/recon.txt` — chứa `list_secrets=yes` và `create_pods=yes`.
- `~/loot.txt` — chứa mật khẩu DB (bắt đầu bằng `S3cureDbP...`) và `legacy_api_key` lấy từ ConfigMap.
- `~/flag.txt` — flag đọc được trên host.
- `~/harden_verify.txt` — chứa `list_secrets_after=no`.

> Đây là bài mức 4: nếu chưa Y, đừng tìm "lệnh sẵn" — hãy quay lại **Hướng tiếp cận** và tra tài liệu `kubectl`. Đó là phần rèn tư duy chính của bài.
