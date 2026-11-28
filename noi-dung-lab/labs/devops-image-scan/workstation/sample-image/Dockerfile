FROM python:3.8.0-slim

LABEL maintainer="dev@internal.local"
LABEL app="internal-app"

WORKDIR /app

COPY app.py /app/app.py
COPY requirements.txt /app/requirements.txt

COPY .env /app/.env
COPY secrets/aws-credentials.txt /app/secrets/aws-credentials.txt

RUN rm -f /app/.env /app/secrets/aws-credentials.txt && \
    rm -rf /app/secrets

EXPOSE 5000

CMD ["python", "app.py"]
