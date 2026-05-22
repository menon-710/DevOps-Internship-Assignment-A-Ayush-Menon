#!/usr/bin/env python3
"""
Alchemyst Inference Gateway
HTTP wrapper around iii trigger CLI
"""

import subprocess
import os
import os
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

III_BIN = os.environ.get("III_BIN", "/home/ubuntu/.local/bin/iii")
WORKING_DIR = os.environ.get("WORKING_DIR", "/opt/alchemyst/quickstart")

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "alchemyst-api-gateway"})

@app.route("/v1/trigger", methods=["POST"])
def trigger():
    data = request.get_json()
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    worker   = data.get("worker")
    function = data.get("function")
    args     = data.get("args", {})

    if not worker or not function:
        return jsonify({"error": "'worker' and 'function' are required"}), 400

    # Build: iii trigger math::add a=2 b=3
    rpc_target = f"{worker}::{function}"
    arg_list   = [f"{k}={v}" for k, v in args.items()]
    cmd        = [III_BIN, "trigger", rpc_target] + arg_list

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            cwd=WORKING_DIR
        )
        if result.returncode != 0:
            return jsonify({
                "error": "RPC call failed",
                "detail": result.stderr.strip()
            }), 500

        return jsonify({
            "result":   result.stdout.strip(),
            "worker":   worker,
            "function": function,
            "args":     args
        })

    except subprocess.TimeoutExpired:
        return jsonify({"error": "RPC call timed out after 30s"}), 504
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
