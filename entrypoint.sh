#!/bin/bash
set -e

PORT=8080
HIKKA_RESTART_TIMEOUT=60

pip install flask requests

if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
    RENDER_EXTERNAL_HOSTNAME=$(curl -s "http://169.254.169.254/latest/meta-data/public-hostname" || echo "")
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        exit 1
    fi
fi

python3 - <<EOF &
from flask import Flask
import requests
import subprocess
import time
import threading
import sys
import logging

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger()

app = Flask(__name__)
hikka_process = None
hikka_last_seen = time.time()
flask_running = False

def start_hikka():
    global hikka_process
    hikka_process = subprocess.Popen(["python", "-m", "hikka", "--port", str($PORT)])
    logger.info(f"Hikka restarted with PID: {hikka_process.pid}")

def stop_hikka():
    global hikka_process
    if hikka_process:
        hikka_process.kill()
        logger.info(f"Hikka (PID: {hikka_process.pid}) stopped")
        hikka_process = None

def monitor_hikka():
    global hikka_last_seen, flask_running
    while True:
        time.sleep(10)
        if hikka_process and hikka_process.poll() is None:
            hikka_last_seen = time.time()
            if flask_running:
                logger.info("Hikka is back, stopping Flask")
                flask_running = False
                sys.exit(0)  # Завершаем Flask
        else:
            logger.warning(f"Hikka process is dead (PID: {hikka_process.pid if hikka_process else 'None'})")
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

def run_flask():
    global flask_running
    flask_running = True
    app.run(host="0.0.0.0", port=$PORT)

def wait_for_hikka():
    while True:
        if hikka_process and hikka_process.poll() is None:
            time.sleep(10)
            continue
        else:
            logger.info("Hikka is confirmed dead, starting Flask")
            threading.Thread(target=run_flask).start()
            break

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

trap "kill $SERVER_PID; exit 0" SIGTERM SIGINT

wait
