#!/bin/bash
set -e

FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

DATA_DIR="/data"
VALKEY_KEY="data"

if [ -z "$REDIS_URL" ]; then
    echo "Ошибка: Переменная окружения REDIS_URL не задана. Убедитесь, что Valkey настроен на Render."
    exit 1
fi

init_valkey() {
    echo "Инициализация Valkey"
    python - <<EOF
import redis
import os

try:
    r = redis.Redis.from_url("$REDIS_URL", decode_responses=False)
    if not r.exists("$VALKEY_KEY"):
        print("Ключ $VALKEY_KEY ещё не существует в Valkey.")
    if not os.path.exists("$DATA_DIR"):
        os.makedirs("$DATA_DIR")
    print("Valkey инициализирован!")
except Exception as e:
    print(f"Ошибка инициализации Valkey: {e}")
EOF
}

restore_data_from_valkey() {
    echo "Запуск restore_data_from_valkey"
    python - <<EOF
import redis
import os
import tarfile
import io

data_dir = "$DATA_DIR"
valkey_url = "$REDIS_URL"
valkey_key = "$VALKEY_KEY"

try:
    r = redis.Redis.from_url(valkey_url, decode_responses=False)
    tar_data = r.get(valkey_key)
    if tar_data:
        if not os.path.exists(data_dir):
            os.makedirs(data_dir)
        with tarfile.open(fileobj=io.BytesIO(tar_data), mode="r") as tar:
            tar.extractall(path=data_dir)
            print("Восстановленные файлы и директории:")
            for member in tar.getnames():
                print(f" - {member}")
        print(f"Данные восстановлены в {data_dir}!")
        r.delete(valkey_key)
        print(f"Данные удалены из Valkey после восстановления.")
    else:
        print(f"В Valkey нет данных для ключа {valkey_key}, ждём создания файлов в {data_dir}.")
except Exception as e:
    print(f"Ошибка восстановления данных: {e}")
EOF
}

save_data_to_valkey() {
    echo "Запуск save_data_to_valkey"
    python - <<EOF
import redis
import os
import tarfile
import io

data_dir = "$DATA_DIR"
valkey_url = "$REDIS_URL"
valkey_key = "$VALKEY_KEY"

try:
    r = redis.Redis.from_url(valkey_url, decode_responses=False)
    if os.path.exists(data_dir) and os.listdir(data_dir):
        tar_buffer = io.BytesIO()
        with tarfile.open(fileobj=tar_buffer, mode="w") as tar:
            tar.add(data_dir, arcname=os.path.basename(data_dir))
            print("Сохраняемые файлы и директории:")
            for member in tar.getmembers():
                print(f" - {member.name}")
        tar_buffer.seek(0)
        tar_data = tar_buffer.read()
        r.set(valkey_key, tar_data)
        print(f"Данные из {data_dir} сохранены в Valkey!")
    else:
        print(f"Директория {data_dir} пуста или не существует, ничего не сохраняем.")
except Exception as e:
    print(f"Ошибка сохранения данных: {e}")
EOF
}

auto_save() {
    echo "Запуск auto_save в фоновом режиме"
    while true; do
        save_data_to_valkey
        sleep 60
    done
}
auto_save &

keep_alive_local() {
    echo "Запуск keep_alive_local в фоновом режиме"
    sleep 30
    if [ -z "$RENDER_EXTERNAL_HOSTNAME" ]; then
        echo "Ошибка: Переменная RENDER_EXTERNAL_HOSTNAME не задана. Активность не будет генерироваться."
        exit 1
    fi
    echo "Обнаружен домен сервиса: $RENDER_EXTERNAL_HOSTNAME"
    while true; do
        curl -s "https://$RENDER_EXTERNAL_HOSTNAME" -o /dev/null &
        echo "Отправлен запрос на https://$RENDER_EXTERNAL_HOSTNAME для поддержания активности"
        sleep 30
    done
}
keep_alive_local &

monitor_forbidden() {
    echo "Запуск monitor_forbidden"
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

echo "Инициализация скрипта"
init_valkey
restore_data_from_valkey

echo "Установка trap для SIGTERM"
trap 'echo "Получен SIGTERM, сохраняем данные..."; save_data_to_valkey; echo "Данные сохранены, завершаем работу."; exit 0' SIGTERM SIGINT

echo "Запуск python -m hikka"
exec python -m hikka --port 8080
