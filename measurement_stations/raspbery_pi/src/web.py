from flask import Flask, jsonify, request, render_template
from shared_state import state, lock
import shutil
import os
import json

app = Flask(__name__)   # 👈 MUSÍ být před route

HDD_DIR = "/media/admin/Elements/iq_data"

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/status")
def status():
    try:
        with open("/tmp/recorder_status.json", "r") as f:
            return jsonify(json.load(f))
    except:
	    with lock:
	        return jsonify(dict(state))

@app.route("/disk")
def disk():
    try:
        usage = shutil.disk_usage(HDD_DIR)
        return jsonify({
            "total_gb": usage.total / 1e9,
            "free_gb": usage.free / 1e9,
            "used_percent": (usage.used / usage.total) * 100
        })
    except:
        return jsonify({"error": "disk unavailable"})

@app.route("/prepare_disk_swap", methods=["POST"])
def prepare_disk_swap():
    with open("/tmp/swap_flag", "w") as f:
        f.write("1")
    return "Swap requested"

@app.route("/confirm_swap", methods=["POST"])
def confirm_swap():
    with open("/tmp/confirm_swap_flag", "w") as f:
        f.write("1")

    return "Swap confirmed"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
