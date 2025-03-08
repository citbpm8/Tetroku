#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

PORT=${PORT:-8080}
HIKKA_RESTART_TIMEOUT=60

pip install flask requests

if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
    RENDER_EXTERNAL_HOSTNAME=$(curl -s "http://169.254.169.254/latest/meta-data/public-hostname" || echo "")
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        exit 1
    fi
fi

python3 - <<EOF
from flask import Flask
import requests
import subprocess
import time
import threading
import logging
import sys

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger()

app = Flask(__name__)
hikka_process = None
current_mode = "hikka"  # "hikka" или "flask"
hikka_last_seen = time.time()

def start_hikka():
    global hikka_process, current_mode
    hikka_process = subprocess.Popen(["python", "-m", "hikka", "--port", str($PORT)])
    logger.info(f"Hikka started with PID: {hikka_process.pid}")
    current_mode = "hikka"

def stop_hikka():
    global hikka_process
    if hikka_process and hikka_process.poll() is None:
        hikka_process.kill()
        logger.info(f"Hikka (PID: {hikka_process.pid}) stopped")
    hikka_process = None

def monitor_hikka():
    global hikka_last_seen, current_mode
    while True:
        time.sleep(10)
        if hikka_process and hikka_process.poll() is None:
            hikka_last_seen = time.time()
        else:
            logger.warning(f"Hikka process is dead (PID: {hikka_process.pid if hikka_process else 'None'})")
            if time.time() - hikka_last_seen > $HIKKA_RESTART_TIMEOUT and current_mode == "hikka":
                stop_hikka()
                current_mode = "flask"  # Переключаемся на Flask
                logger.info("Switching to Flask mode")
        if current_mode == "flask" and not hikka_process:
            stop_hikka()  # Убедимся, что Hikka не висит
            start_hikka()  # Пробуем перезапустить Hikka
            time.sleep(5)  # Даём время Hikka запуститься
            if hikka_process and hikka_process.poll() is None:
                logger.info("Hikka is back, switching from Flask")
                current_mode = "hikka"
                sys.exit(0)  # Завершаем Flask

def keep_alive_local():
    while True:
        time.sleep(30)
        try:
            requests.get(f"https://$RENDER_EXTERNAL_HOSTNAME", timeout=5)
        except requests.exceptions.RequestException:
            pass

def monitor_forbidden():
    forbidden_utils = "$FORBIDDEN_UTILS".split()
    while True:
        for cmd in forbidden_utils:
            if subprocess.call(["command", "-v", cmd], stdout=subprocess.PIPE, stderr=subprocess.PIPE) == 0:
                subprocess.run(["apt-get", "purge", "-y", cmd], check=False)
        time.sleep(10)

# Запускаем фоновые задачи
threading.Thread(target=monitor_hikka, daemon=True).start()
threading.Thread(target=keep_alive_local, daemon=True).start()
threading.Thread(target=monitor_forbidden, daemon=True).start()

# Основной цикл: переключение между Hikka и Flask
start_hikka()
while True:
    if current_mode == "hikka":
        if hikka_process and hikka_process.poll() is None:
            time.sleep(10)
        else:
            current_mode = "flask"  # Hikka умерла, переключаемся
    if current_mode == "flask":
        logger.info("Running Flask as fallback")
        app.run(host="0.0.0.0", port=$PORT)

@app.route("/healthz")
def healthz():
    try:
        response = requests.get(f"http://localhost:$PORT", timeout=3)
        if response.status_code == 200:
            return "OK", 200
    except requests.exceptions.RequestException:
        return "DOWN", 500
EOF
