# =============================================================================
# Dockerfile MẪU — internal-app:1.0 (CỐ TÌNH CÓ LỖ HỔNG)
# Image này được build sẵn và nạp vào workstation
# Chứa secret trong layer trung gian + base image cũ
# =============================================================================

# ⚠️ Base image CŨ có nhiều CVE
FROM python:3.8.0-slim

LABEL maintainer="dev@internal.local"
LABEL app="internal-app"

WORKDIR /app

# ── Cài dependency ──
RUN pip install flask requests

# ── Copy mã nguồn ──
COPY app.py /app/app.py
COPY requirements.txt /app/requirements.txt

# ⚠️ COPY file secret vào image (SAI!)
COPY .env /app/.env
COPY secrets/aws-credentials.txt /app/secrets/aws-credentials.txt

# ⚠️ Cố xóa secret nhưng vẫn còn trong layer trước!
RUN rm -f /app/.env /app/secrets/aws-credentials.txt && \
    rm -rf /app/secrets

EXPOSE 5000

CMD ["python", "app.py"]
