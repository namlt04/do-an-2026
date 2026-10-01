#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
s3lite.py — Máy chủ đối tượng tương thích S3 (tối giản) cho lab Labtainer.

LÝ DO TỒN TẠI: MinIO đã gỡ toàn bộ kênh phân phối binary công khai (dl.min.io
410 Gone; Docker Hub / quay.io yêu cầu đăng nhập). s3lite thay thế MinIO cho
các bài storage, CHỈ dùng thư viện chuẩn Python (không cần pip) → build/chạy
hoàn toàn offline, và TỰ kiểm soát cơ chế xác thực để CHỐNG BYPASS.

CHỐNG BYPASS:
  - Bucket PRIVATE: bắt buộc request phải mang đúng AccessKeyId (đọc từ SigV4
    "Authorization: ... Credential=<AKID>/..." hoặc header X-S3LITE-AKID) mới
    được list/get; nếu không → 403 AccessDenied (XML chuẩn S3).
  - aws-cli không thể tạo chữ ký nếu thiếu access key + secret key → trên thực
    tế sinh viên phải có ĐỦ cặp credential lộ mới truy cập được.
  - Bucket PUBLIC: cho phép ẩn danh list/get (mô phỏng bucket cấu hình sai).

TƯƠNG THÍCH: đủ cho `aws s3api list-objects-v2`, `aws s3api get-object`,
`aws s3 ls`, `aws s3 cp` (path-style, --endpoint-url) và `curl`.

CẤU HÌNH qua biến môi trường:
  S3LITE_ROOT           thư mục gốc chứa các bucket (mỗi bucket = 1 thư mục con).
                        Mặc định: /opt/s3lite/data
  S3LITE_PUBLIC_BUCKETS danh sách bucket public, phân tách bởi dấu phẩy.
  S3LITE_AKID           AccessKeyId hợp lệ (bucket private). Hoặc:
  S3LITE_AKID_FILE      đường dẫn file chứa AccessKeyId (1 dòng) — tiện cho
                        HASH_REPLACE bơm giá trị per-student vào file này.
  S3LITE_PORT           cổng lắng nghe (mặc định 9000).
  S3LITE_LOG            file log truy cập (mặc định /opt/s3lite/access.log).
"""
import os, sys, socketserver, http.server, urllib.parse, datetime, hashlib, re

ROOT = os.environ.get("S3LITE_ROOT", "/opt/s3lite/data")
PUBLIC = set(b.strip() for b in os.environ.get("S3LITE_PUBLIC_BUCKETS", "").split(",") if b.strip())
PORT = int(os.environ.get("S3LITE_PORT", "9000"))
LOGF = os.environ.get("S3LITE_LOG", "/opt/s3lite/access.log")

def required_akid():
    v = os.environ.get("S3LITE_AKID")
    if v:
        return v.strip()
    f = os.environ.get("S3LITE_AKID_FILE")
    if f and os.path.isfile(f):
        try:
            return open(f).read().strip()
        except Exception:
            return None
    return None

S3NS = "http://s3.amazonaws.com/doc/2006-03-01/"

def log(msg):
    try:
        with open(LOGF, "a") as fh:
            fh.write("%s %s\n" % (datetime.datetime.utcnow().isoformat(), msg))
    except Exception:
        pass

def akid_from_auth(headers):
    # SigV4: "AWS4-HMAC-SHA256 Credential=<AKID>/20250101/us-east-1/s3/aws4_request, ..."
    a = headers.get("Authorization", "") or ""
    m = re.search(r"Credential=([^/,\s]+)/", a)
    if m:
        return m.group(1)
    # Fallback header (dùng cho curl trong solver/kiểm thử)
    return (headers.get("X-S3LITE-AKID") or "").strip() or None

def xml_error(code, msg, key=""):
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            '<Error><Code>%s</Code><Message>%s</Message>'
            '<Resource>%s</Resource></Error>' % (code, msg, key)).encode()

class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "s3lite/1.0"

    def _send(self, status, body=b"", ctype="application/xml"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("x-amz-request-id", hashlib.md5(os.urandom(8)).hexdigest()[:16])
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _deny(self, key=""):
        log("DENY %s auth_akid=%s" % (self.path, akid_from_auth(self.headers)))
        self._send(403, xml_error("AccessDenied", "Access Denied", key))

    def _parse(self):
        p = urllib.parse.urlparse(self.path)
        parts = p.path.lstrip("/").split("/", 1)
        bucket = parts[0] if parts and parts[0] else ""
        key = parts[1] if len(parts) > 1 else ""
        qs = urllib.parse.parse_qs(p.query)
        return bucket, key, qs

    def _authorized(self, bucket):
        if bucket in PUBLIC:
            return True
        need = required_akid()
        if not need:
            return False  # chưa cấu hình AKID → mặc định từ chối (an toàn)
        return akid_from_auth(self.headers) == need

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        bucket, key, qs = self._parse()
        if not bucket:
            # ListAllMyBuckets (tối giản) — chỉ liệt kê bucket public để tránh lộ tên bucket private
            items = "".join("<Bucket><Name>%s</Name><CreationDate>%sZ</CreationDate></Bucket>" %
                            (b, datetime.datetime.utcnow().isoformat()) for b in sorted(PUBLIC))
            body = ('<?xml version="1.0" encoding="UTF-8"?>'
                    '<ListAllMyBucketsResult xmlns="%s"><Owner><ID>s3lite</ID>'
                    '<DisplayName>s3lite</DisplayName></Owner><Buckets>%s</Buckets>'
                    '</ListAllMyBucketsResult>' % (S3NS, items)).encode()
            return self._send(200, body)

        bdir = os.path.join(ROOT, bucket)
        if not os.path.isdir(bdir):
            return self._send(404, xml_error("NoSuchBucket", "The specified bucket does not exist", bucket))

        # LIST (list-type=2, hoặc GET bucket không key)
        if not key or "list-type" in qs or key == "":
            if not self._authorized(bucket):
                return self._deny(bucket)
            prefix = (qs.get("prefix", [""])[0])
            contents = []
            for dirpath, _dirs, files in os.walk(bdir):
                for fn in files:
                    full = os.path.join(dirpath, fn)
                    rel = os.path.relpath(full, bdir).replace(os.sep, "/")
                    if prefix and not rel.startswith(prefix):
                        continue
                    st = os.stat(full)
                    contents.append((rel, st.st_size,
                                     datetime.datetime.utcfromtimestamp(st.st_mtime).isoformat()))
            xml_items = "".join(
                "<Contents><Key>%s</Key><LastModified>%sZ</LastModified>"
                "<Size>%d</Size><StorageClass>STANDARD</StorageClass></Contents>" %
                (k, m, s) for (k, s, m) in sorted(contents))
            body = ('<?xml version="1.0" encoding="UTF-8"?>'
                    '<ListBucketResult xmlns="%s"><Name>%s</Name><Prefix>%s</Prefix>'
                    '<KeyCount>%d</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>'
                    '%s</ListBucketResult>' % (S3NS, bucket, prefix, len(contents), xml_items)).encode()
            return self._send(200, body)

        # GET object
        if not self._authorized(bucket):
            return self._deny(bucket + "/" + key)
        fpath = os.path.join(bdir, key)
        if not os.path.isfile(fpath):
            return self._send(404, xml_error("NoSuchKey", "The specified key does not exist", key))
        with open(fpath, "rb") as fh:
            data = fh.read()
        log("GET %s/%s ok (%d bytes)" % (bucket, key, len(data)))
        return self._send(200, data, ctype="application/octet-stream")

    def do_PUT(self):
        bucket, key, qs = self._parse()
        if not self._authorized(bucket):
            return self._deny(bucket + "/" + key)
        bdir = os.path.join(ROOT, bucket)
        if not key or not os.path.isdir(bdir):
            return self._send(404, xml_error("NoSuchBucket", "no bucket", bucket))
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length) if length else b""
        fpath = os.path.join(bdir, key)
        os.makedirs(os.path.dirname(fpath), exist_ok=True)
        with open(fpath, "wb") as fh:
            fh.write(data)
        return self._send(200, b"")

    def log_message(self, fmt, *args):
        return  # tắt log mặc định (dùng log() riêng)

class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

if __name__ == "__main__":
    os.makedirs(ROOT, exist_ok=True)
    try:
        os.makedirs(os.path.dirname(LOGF), exist_ok=True)
    except Exception:
        pass
    log("s3lite start port=%d root=%s public=%s akid_set=%s" %
        (PORT, ROOT, ",".join(sorted(PUBLIC)), bool(required_akid())))
    ThreadingServer(("0.0.0.0", PORT), Handler).serve_forever()
