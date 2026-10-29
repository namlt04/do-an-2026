from flask import Flask, jsonify, request

app = Flask(__name__)
VALID_API_KEY = "AKIAIMAGEAPIKEY"

@app.route("/health")
def health():
    return jsonify(status="healthy")

@app.route("/flag", methods=["GET", "POST"])
def get_flag():
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    if token != VALID_API_KEY:
        return jsonify(error="invalid API key"), 403
    with open("/home/ubuntu/flag_seed.txt") as stream:
        return jsonify(status="success", flag=stream.read().strip())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
