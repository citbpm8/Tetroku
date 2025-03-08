#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

PORT=8080  
HIKKA_RESTART_TIMEOUT=60  

echo "Starting Hikka on port $PORT..."
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

def stop_hikka():
    global hikka_process
    if hikka_process:
        hikka_process.kill()
        hikka_process = None

def monitor_hikka():
    global hikka_last_seen
    while True:
        time.sleep(10)
        try:
            response = requests.get(f"http://localhost:$PORT", timeout=3)
            if response.status_code == 200:
                hikka_last_seen = time.time()
        except requests.exceptions.RequestException:
            pass  

        if time.time() - hikka_last_seen > $HIKKA_RESTART_TIMEOUT:
            print("Hikka не отвечает более 1 минуты. Перезапускаю...")
            stop_hikka()
            start_hikka()
            hikka_last_seen = time.time()

start_hikka()
threading.Thread(target=monitor_hikka, daemon=True).start()

@app.route("/health")
def health():
    try:
        response = requests.get(f"http://localhost:$PORT", timeout=3)
        if response.status_code == 200:
            return "OK", 200
    except requests.exceptions.RequestException:
        return "DOWN", 500

def wait_for_hikka():
    while True:
        try:
            response = requests.get(f"http://localhost:$PORT", timeout=3)
            if response.status_code == 200:
                time.sleep(10)
                continue  
        except requests.exceptions.RequestException:
            print("Hikka упала! Запускаем резервный сервер...")
            break  

    app.run(host="0.0.0.0", port=$PORT)

threading.Thread(target=wait_for_hikka, daemon=True).start()
EOF
SERVER_PID=$!

echo "Server running on http://your-domain.com:$PORT"
echo "Health check available at http://your-domain.com:$PORT/health"

keep_alive_local() {
    sleep 10
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        exit 1
    fi
    while true; do
        echo "Preventing sleep: Checking health at https://$RENDER_EXTERNAL_HOSTNAME"
        curl -s "https://$RENDER_EXTERNAL_HOSTNAME" -o /dev/null &
        sleep 30
    done
}

monitor_forbidden() {
    while true; do
        for cmd in $FORBIDDEN_UTILS; do
            if command -v "$cmd" >/dev/null 2>&1; then
                echo "Removing forbidden utility: $cmd"
                apt-get purge -y "$cmd" 2>/dev/null || true
            fi
        done
        sleep 10
    done
}

keep_alive_local &  
monitor_forbidden &  

trap "echo 'Stopping processes'; kill $SERVER_PID; exit 0" SIGTERM SIGINT

echo "All processes started successfully. Monitoring logs..."
wait
