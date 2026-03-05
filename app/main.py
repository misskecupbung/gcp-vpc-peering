"""
Simple API for testing VPC connectivity from Cloud Run
"""
import os
import requests
from flask import Flask, jsonify

app = Flask(__name__)


@app.route('/')
def health():
    """Health check endpoint"""
    return jsonify({"service": "my-api", "status": "healthy"})


@app.route('/check-internal/<ip>')
def check_internal(ip):
    """Test connectivity to internal VPC resources"""
    try:
        resp = requests.get(f'http://{ip}', timeout=5)
        return jsonify({
            "target": ip,
            "reachable": True,
            "response": resp.text[:50]
        })
    except requests.exceptions.Timeout:
        return jsonify({
            "target": ip,
            "reachable": False,
            "error": "Connection timeout - check firewall rules"
        }), 504
    except requests.exceptions.ConnectionError as e:
        return jsonify({
            "target": ip,
            "reachable": False,
            "error": f"Connection failed: {str(e)}"
        }), 502
    except Exception as e:
        return jsonify({
            "target": ip,
            "reachable": False,
            "error": str(e)
        }), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=True)
