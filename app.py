import os
import json
import time
import subprocess
import glob
from flask import Flask, render_template, request, jsonify, send_file, session

app = Flask(__name__)
app.secret_key = "royalviento_secret_key_vps_trading"

CONFIG_FILE = "/root/dashboard/config.json"
STATUS_FILE = "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Files/web_status.json"
COMMAND_FILE = "/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Files/web_command.json"
SCREENSHOT_PATH = "/tmp/mt5_web_preview.png"
CLOUDFLARE_LOG = "/root/dashboard/cloudflared.log"

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {"pin": "1234", "daily_target_usd": 50.0}

def save_config(cfg):
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)

def is_mt5_running():
    try:
        res = subprocess.run(["pgrep", "-f", "terminal64.exe"], capture_output=True, text=True)
        return res.returncode == 0
    except Exception:
        return False

def get_cloudflare_url():
    import re
    if os.path.exists(CLOUDFLARE_LOG):
        try:
            with open(CLOUDFLARE_LOG, "r") as f:
                text = f.read()
                matches = re.findall(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com', text)
                if matches:
                    return matches[-1]
        except Exception:
            pass
    return None

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/auth", methods=["POST"])
def auth():
    data = request.json or {}
    pin = data.get("pin", "")
    cfg = load_config()
    if pin == cfg.get("pin", "1234"):
        session["authenticated"] = True
        return jsonify({"success": True})
    return jsonify({"success": False, "message": "PIN Salah!"}), 401

@app.route("/api/auth_check", methods=["GET"])
def auth_check():
    return jsonify({"authenticated": session.get("authenticated", False)})

@app.route("/api/status", methods=["GET"])
def get_status():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401
    
    cfg = load_config()
    running = is_mt5_running()
    
    status_data = {}
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, "r", encoding="utf-8", errors="ignore") as f:
                status_data = json.load(f)
        except Exception as e:
            status_data = {"error": f"Error parsing status: {str(e)}"}
    else:
        status_data = {"warning": "Status file belum tersedia"}

    status_data["mt5_running"] = running
    status_data["configured_target_usd"] = cfg.get("daily_target_usd", 50.0)
    status_data["cf_url"] = get_cloudflare_url()
    
    # System stats
    try:
        load1, load5, load15 = os.getloadavg()
        status_data["sys_load"] = f"{load1:.2f}, {load5:.2f}"
    except Exception:
        status_data["sys_load"] = "N/A"

    return jsonify(status_data)

@app.route("/api/command", methods=["POST"])
def send_command():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    data = request.json or {}
    action = data.get("action", "")

    cfg = load_config()

    if action == "set_daily_target":
        target = float(data.get("value", 50.0))
        cfg["daily_target_usd"] = target
        save_config(cfg)
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "set_daily_target", "value": target}, f)
        return jsonify({"success": True, "message": f"Target harian berhasil diatur ke ${target:.2f}"})

    elif action == "pause":
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "pause"}, f)
        return jsonify({"success": True, "message": "Trading di-Pause"})

    elif action == "resume":
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "resume"}, f)
        return jsonify({"success": True, "message": "Trading di-Resume"})

    elif action == "close_all":
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "close_all"}, f)
        return jsonify({"success": True, "message": "Perintah tutup semua posisi dikirim!"})

    elif action == "close_ticket":
        ticket = int(data.get("ticket", 0))
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "close_ticket", "ticket": ticket}, f)
        return jsonify({"success": True, "message": f"Perintah tutup tiket #{ticket} dikirim!"})

    elif action == "reset_daily":
        with open(COMMAND_FILE, "w") as f:
            json.dump({"action": "reset_daily"}, f)
        return jsonify({"success": True, "message": "Statistik profit harian di-reset ke 0"})

    elif action == "toggle_algo":
        try:
            subprocess.run("export DISPLAY=:99 && xdotool mousemove --sync 350 70 click 1", shell=True, timeout=5)
            return jsonify({"success": True, "message": "Tombol Algo Trading di-toggle!"})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)}), 500

    return jsonify({"success": False, "message": "Action tidak dikenal"}), 400

@app.route("/api/server", methods=["POST"])
def server_control():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    data = request.json or {}
    op = data.get("operation", "")

    if op == "restart_mt5":
        subprocess.Popen(["systemctl", "restart", "mt5-trading"])
        return jsonify({"success": True, "message": "Layanan MT5 sedang direstart..."})
    elif op == "stop_mt5":
        subprocess.Popen(["systemctl", "stop", "mt5-trading"])
        return jsonify({"success": True, "message": "Layanan MT5 dihentikan."})
    elif op == "start_mt5":
        subprocess.Popen(["systemctl", "start", "mt5-trading"])
        return jsonify({"success": True, "message": "Layanan MT5 dijalankan."})
    elif op == "change_pin":
        new_pin = str(data.get("pin", "")).strip()
        if len(new_pin) >= 4:
            cfg = load_config()
            cfg["pin"] = new_pin
            save_config(cfg)
            return jsonify({"success": True, "message": "PIN keamanan berhasil diubah!"})
        return jsonify({"success": False, "message": "PIN minimal 4 karakter"}), 400

    return jsonify({"success": False, "message": "Operasi tidak valid"}), 400

@app.route("/api/screenshot")
def screenshot():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401
    try:
        subprocess.run("export DISPLAY=:99 && scrot -o " + SCREENSHOT_PATH, shell=True, timeout=5)
        if os.path.exists(SCREENSHOT_PATH):
            return send_file(SCREENSHOT_PATH, mimetype="image/png", max_age=0)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    return jsonify({"error": "Failed to capture screenshot"}), 500

@app.route("/api/logs")
def get_logs():
    if not session.get("authenticated", False):
        return jsonify({"authenticated": False}), 401

    # Latest MQL5 log
    mql5_logs = sorted(glob.glob("/root/.wine/drive_c/Program Files/MetaTrader 5/MQL5/logs/*.log"), key=os.path.getmtime)
    ea_log_lines = []
    if mql5_logs:
        try:
            with open(mql5_logs[-1], "rb") as f:
                content = f.read().decode("utf-16le", errors="ignore")
                ea_log_lines = content.splitlines()[-40:]
        except Exception:
            pass

    # Latest Terminal log
    term_logs = sorted(glob.glob("/root/.wine/drive_c/Program Files/MetaTrader 5/logs/*.log"), key=os.path.getmtime)
    term_log_lines = []
    if term_logs:
        try:
            with open(term_logs[-1], "rb") as f:
                content = f.read().decode("utf-16le", errors="ignore")
                term_log_lines = content.splitlines()[-40:]
        except Exception:
            pass

    return jsonify({
        "ea_logs": ea_log_lines,
        "terminal_logs": term_log_lines
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
