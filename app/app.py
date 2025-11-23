from flask import Flask, render_template, jsonify, Response, request
import os, time, json

app = Flask(__name__)

APP_NAME = os.getenv("APP_NAME", "SkyCanary")
APP_VERSION = os.getenv("APP_VERSION", "stable")
USE_K8S = os.getenv("USE_K8S", "0") == "1"
ROLLBACK = False
current_weights = {"stable": 100, "canary": 0}

# --- Dashboard ---
@app.route("/")
def index():
    return render_template("index.html", app_name=APP_NAME, version=APP_VERSION)

# --- SSE Stream (simulated rollout) ---
@app.route("/api/stream")
def stream():
    def event_stream():
        steps = [10, 25, 50, 75, 100]
        for step in steps:
            current_weights["canary"] = step
            current_weights["stable"] = 100 - step
            data = {"step": step, "weights": current_weights}
            yield f"data: {json.dumps(data)}\n\n"
            time.sleep(2)
    return Response(event_stream(), mimetype="text/event-stream")

# --- Rollout Simulation ---
@app.route("/api/rollout", methods=["POST"])
def rollout():
    return jsonify({"message": "Rollout started", "mode": "simulation"})

# --- Current State ---
@app.route("/api/state")
def state():
    return jsonify({
        "app": APP_NAME,
        "version": APP_VERSION,
        "use_k8s": USE_K8S,
        "weights": current_weights
    })

# --- Ping/Message ---
@app.route("/api/message", methods=["POST"])
def message():
    msg = request.json.get("message", "No message")
    print(f"📨 Message: {msg}")
    return jsonify({"status": "ok", "message": msg})

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8090))
    app.run(host="0.0.0.0", port=port, debug=False)
