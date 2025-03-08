#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

PORT=8080

HIKKA_RESTART_TIMEOUT=5

pip install flask requests

if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
    RENDER_EXTERNAL_HOSTNAME=$(curl -s "http://169.254.169.254/latest/meta-data/public-hostname" || echo "")
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        exit 1
    fi
fi

nohup python3 - <<EOF &
from flask import Flask
import requests
import subprocess
import time
import threading

app = Flask(__name__)
hikka_process = None
hikka_last_seen = time.time()

def start_hikka():
    global hikka_process
    hikka_process = subprocess.Popen(["python", "-m", "hikka", "--port", str($PORT)])
    print(f"Hikka restarted with PID: {hikka_process.pid}")

def stop_hikka():
    global hikka_process
    if hikka_process:
        hikka_process.kill()
        print(f"Hikka (PID: {hikka_process.pid}) stopped")
        hikka_process = None

def monitor_hikka():
    global hikka_last_seen
    while True:
        time.sleep(10)
        if hikka_process and hikka_process.poll() is None:
            hikka_last_seen = time.time()
        else:
            print(f"Hikka process is dead (PID: {hikka_process.pid if hikka_process else 'None'})")
            if time.time() - hikka_last_seen > $HIKKA_RESTART_TIMEOUT:
                stop_hikka()
                start_hikka()
                hikka_last_seen = time.time()

start_hikka()
threading.Thread(target=monitor_hikka, daemon=True).start()

@app.route("/healthz")
def healthz():
    try:
        response = requests.get(f"http://localhost:$PORT", timeout=3)
        if response.status_code == 200:
            return "OK", 200
    except requests.exceptions.RequestException:
        return "DOWN", 500

def wait_for_hikka():
    while True:
        if hikka_process and hikka_process.poll() is None:
            time.sleep(10)
            continue
        else:
            break
    print("Hikka is confirmed dead, starting Flask")
    app.run(host="0.0.0.0", port=$PORT)

threading.Thread(target=wait_for_hikka, daemon=True).start()
EOF
SERVER_PID=$!

keep_alive_local() {
    sleep 30
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        exit 1
    fi
    while true; do
        curl -s "https://$RENDER_EXTERNAL_HOSTNAME" -o /dev/null &
        sleep 30
    done
}
keep_alive_local &

monitor_forbidden() {
    while true; do
        for cmd in $FORBIDDEN_UTILS; do
            if command -v "$cmd" >/dev/null 2>&1; then
                apt-get purge -y "$cmd" 2>/dev/null || true
            fi
        done
        sleep 10
    done
}
monitor_forbidden &

trap "kill $SERVER_PID; exit 0" SIGTERM SIGINT

wait
