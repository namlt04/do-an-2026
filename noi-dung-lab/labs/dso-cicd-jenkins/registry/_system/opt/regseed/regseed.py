#!/usr/bin/env python3
# Dung san storage cho Docker Registry v2 (storage driver filesystem) voi mot
# image acme/app:1.0 ma lop layer chua flag_pivot (ca the hoa theo sinh vien).
import hashlib, io, json, os, gzip, tarfile, shutil

ROOT = "/var/lib/registry/docker/registry/v2"
REPO = "acme/app"
TAG = "1.0"
FLAG = open("/opt/regseed/flag_pivot.txt").read().strip()

def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()

def write_blob(data):
    d = sha256_hex(data)
    p = os.path.join(ROOT, "blobs", "sha256", d[:2], d, "data")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        f.write(data)
    return d

def link(path, digest):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("sha256:" + digest)

# 1) layer: tar.gz chua flag_pivot.txt
raw = io.BytesIO()
tf = tarfile.open(fileobj=raw, mode="w")
content = ("flag_pivot=" + FLAG + "\n").encode()
ti = tarfile.TarInfo("flag_pivot.txt"); ti.size = len(content)
tf.addfile(ti, io.BytesIO(content))
tf.close()
gz = io.BytesIO()
with gzip.GzipFile(fileobj=gz, mode="wb", mtime=0) as g:
    g.write(raw.getvalue())
layer_bytes = gz.getvalue()
layer_digest = write_blob(layer_bytes)

# 2) config blob (OCI/docker image config toi gian)
config = {
    "architecture": "amd64", "os": "linux",
    "config": {"Labels": {"maintainer": "acme-devops"}},
    "rootfs": {"type": "layers", "diff_ids": ["sha256:" + sha256_hex(raw.getvalue())]},
}
config_bytes = json.dumps(config).encode()
config_digest = write_blob(config_bytes)

# 3) manifest schema2
manifest = {
    "schemaVersion": 2,
    "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
    "config": {"mediaType": "application/vnd.docker.container.image.v1+json",
               "size": len(config_bytes), "digest": "sha256:" + config_digest},
    "layers": [{"mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                "size": len(layer_bytes), "digest": "sha256:" + layer_digest}],
}
manifest_bytes = json.dumps(manifest).encode()
manifest_digest = write_blob(manifest_bytes)

# 4) lien ket trong repository
base = os.path.join(ROOT, "repositories", REPO)
link(os.path.join(base, "_layers", "sha256", layer_digest, "link"), layer_digest)
link(os.path.join(base, "_layers", "sha256", config_digest, "link"), config_digest)
link(os.path.join(base, "_manifests", "revisions", "sha256", manifest_digest, "link"), manifest_digest)
link(os.path.join(base, "_manifests", "tags", TAG, "current", "link"), manifest_digest)
link(os.path.join(base, "_manifests", "tags", TAG, "index", "sha256", manifest_digest, "link"), manifest_digest)

print("seeded %s:%s layer=sha256:%s manifest=sha256:%s" % (REPO, TAG, layer_digest, manifest_digest))
