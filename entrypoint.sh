#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

PORT=${PORT:-8080}  
HEALTH_PORT=8081  

echo "Starting Hikka on port $PORT..."
python -m hikka --port "$PORT" &  # Запускаем Hikka в фоне
HIKKA_PID=$!  # Запоминаем её PID

echo "Waiting for Hikka to start..."
sleep 10  # Даём Hikka время стартануть

echo "Starting health check server on port $HEALTH_PORT..."
python - <<EOF &
import http.server
import socketserver

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_error(404, "Not Found")

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("0.0.0.0", $HEALTH_PORT), HealthHandler) as httpd:
    httpd.serve_forever()
EOF

echo "Health check server started on port $HEALTH_PORT"

keep_alive_local() {
    sleep 30
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        echo "Error: RENDER_EXTERNAL_HOSTNAME is not set"
        exit 1
    fi
    while true; do
        echo "Checking health at: https://$RENDER_EXTERNAL_HOSTNAME:$HEALTH_PORT/health"
        curl -s "https://$RENDER_EXTERNAL_HOSTNAME:$HEALTH_PORT/health" -o /dev/null &
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

keep_alive_local &  # Проверка доступности health check
monitor_forbidden &  # Мониторинг запрещённых утилит

wait $HIKKA_PID  # Ждём, пока Hikka не завершится
