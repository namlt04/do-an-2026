"""
app.py — Internal App mẫu (đơn giản)
Đây là ứng dụng Flask giả lập đi kèm image internal-app:1.0
"""

from flask import Flask
import os

app = Flask(__name__)

@app.route("/")
def index():
    return "Internal App v1.0 - Running"

@app.route("/health")
def health():
    return "OK"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
