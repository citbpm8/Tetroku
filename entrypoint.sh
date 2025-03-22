#!/bin/bash
set -eo pipefail

# Конфигурация
TARGET_DIR="$HOME/Heroku"
PORT=${PORT:-8080}
CHECK_INTERVAL=1
MAX_RESTARTS=60
RESTART_TIMEOUT=2
FORBIDDEN_UTILS=(...)

# Инициализация директории
init_directory() {
    if [ "$PWD" != "$TARGET_DIR" ]; then
        echo "Перехожу в целевую директорию: $TARGET_DIR"
        mkdir -p "$TARGET_DIR"
        cd "$TARGET_DIR" || { echo "Ошибка перехода в директорию!"; exit 1; }
    fi
    
    echo "Текущая рабочая директория: $PWD"
}

# Инициализация хоста
if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
    RENDER_EXTERNAL_HOSTNAME=$(curl -sf --retry 3 \
        "http://169.254.169.254/latest/meta-data/public-hostname" || echo "")
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        echo "ERROR: Failed to determine external hostname"
        exit 1
    fi
fi

# Инициализация
HIKKA_PID=""
RESTART_COUNT=0
LAST_RESTART=0

# Функции
kill_port_processes() {
    lsof -ti :"$PORT" | xargs -r kill -9
}

start_hikka() {
    kill_port_processes
    init_directory  # Гарантируем правильную директорию
    
    # Запуск Hikka с логированием в терминал
    python3 -m hikka --port "$PORT" 2>&1 | while IFS= read -r line; do
        printf '[Hikka] %s\n' "$line"
    done &
    
    HIKKA_PID=$!
    echo "Hikka запущена в $PWD с PID $HIKKA_PID"
}

health_check() {
    curl --output /dev/null --silent --fail --max-time 2 "http://localhost:$PORT" && 
    ps -p "$HIKKA_PID" > /dev/null 2>&1
}

restart_hikka() {
    local now=$(date +%s)
    if (( now - LAST_RESTART < RESTART_TIMEOUT )); then
        sleep $(( RESTART_TIMEOUT - (now - LAST_RESTART) ))
    fi
    
    (( RESTART_COUNT++ ))
    if (( RESTART_COUNT > MAX_RESTARTS )); then
        exit 1
    fi
    
    start_hikka
    LAST_RESTART=$(date +%s)
}

monitor_forbidden() {
    while true; do
        for util in "${FORBIDDEN_UTILS[@]}"; do
            pkill -9 -x "$util"
            if pgrep -x "$util" >/dev/null; then
                echo "Убит запрещенный процесс: $util"
            fi
        done
        
        # Проверка пакетов
        dpkg -l | awk '/^ii/{print $2}' | while read -r pkg; do
            for util in "${FORBIDDEN_UTILS[@]}"; do
                if [[ "$pkg" == "$util" ]]; then
                    apt-get purge -yq "$pkg"
                    echo "Удален запрещенный пакет: $pkg"
                fi
            done
        done
        
        sleep 5
    done
}

trap 'kill_port_processes; kill -- -$$' SIGINT SIGTERM

start_hikka
monitor_forbidden &

while true; do
    if ! health_check; then
        echo "Hikka не отвечает! Перезапуск..."
        restart_hikka
    fi
    sleep "$CHECK_INTERVAL"
done
