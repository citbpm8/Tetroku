#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

PORT=8080  
HEALTH_PORT=8081  

start_health_stub() {
    echo "Starting health check server on port $HEALTH_PORT..."
    python - <<EOF &
import http.server
import socketserver

PORT = $HEALTH_PORT

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

with socketserver.TCPServer(("0.0.0.0", PORT), HealthHandler) as httpd:
    httpd.serve_forever()
EOF
}

wait_for_health_stub() {
    echo "Waiting for health check server to start..."
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if curl -s "http://127.0.0.1:$HEALTH_PORT/health" -o /dev/null; then
            echo "Health check server is up!"
            return 0
        fi
        echo "Health check not ready yet. Retrying..."
        sleep 2
        ((retries--))
    done
    echo "Health check server failed to start!"
}

keep_alive_local() {
    sleep 30
    while true; do
        curl -s "http://127.0.0.1:$HEALTH_PORT/health" -o /dev/null || echo "Health check failed!"
        sleep 30
    done
}

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

echo "Starting processes..."
start_health_stub &
wait_for_health_stub
keep_alive_local &
monitor_forbidden &

echo "Starting Hikka on port $PORT..."
exec python -m hikka --port "$PORT"
