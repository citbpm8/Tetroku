#!/bin/bash
set -e

# Список запрещённых утилит
FORBIDDEN_UTILS="socat nc netcat php lua telnet ncat cryptcat rlwrap msfconsole hydra medusa john hashcat sqlmap metasploit empire cobaltstrike ettercap bettercap responder mitmproxy evil-winrm chisel ligolo revshells powershell certutil bitsadmin smbclient impacket-scripts smbmap crackmapexec enum4linux ldapsearch onesixtyone snmpwalk zphisher socialfish blackeye weeman aircrack-ng reaver pixiewps wifite kismet horst wash bully wpscan commix xerosploit slowloris hping iodine iodine-client iodine-server"

# Пути
DATA_DIR="/data"                         # Директория на ячейке, где hikka хранит данные
CELL_NAME="${CELL_NAME:-default_cell}"   # Уникальное название ячейки
DB_CELL_KEY="data_$CELL_NAME"            # Ключ в базе (например, data_bot1)

# Проверка и установка зависимостей для работы с PostgreSQL
if ! python -c "import psycopg2" >/dev/null 2>&1; then
    echo "Установка psycopg2-binary..."
    pip install psycopg2-binary
fi

# Проверка наличия DATABASE_URL
if [ -z "$DATABASE_URL" ]; then
    echo "Ошибка: Переменная окружения DATABASE_URL не задана. Убедитесь, что база данных настроена на Render."
    exit 1
fi

# Инициализация базы данных
init_db() {
    echo "Запуск init_db"
    python - <<EOF
import psycopg2
from psycopg2 import Error

try:
    conn = psycopg2.connect("$DATABASE_URL")
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cell_data (
            id SERIAL PRIMARY KEY,
            cell_key VARCHAR(255) UNIQUE,  # Ключ в базе (например, data_bot1)
            content BYTEA,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS instance_state (
            id SERIAL PRIMARY KEY,
            cell_name VARCHAR(50) UNIQUE,
            state VARCHAR(50),
            last_shutdown TIMESTAMP,
            last_startup TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)
    cursor.execute("SELECT COUNT(*) FROM instance_state WHERE cell_name = %s;", ("$CELL_NAME",))
    if cursor.fetchone()[0] == 0:
        cursor.execute("INSERT INTO instance_state (cell_name, state) VALUES (%s, 'created');", ("$CELL_NAME",))
    conn.commit()
    print("База данных инициализирована для ячейки $CELL_NAME!")
except Error as e:
    print(f"Ошибка инициализации базы данных: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Проверка состояния ячейки
check_instance_state() {
    echo "Запуск check_instance_state"
    python - <<EOF
import psycopg2

db_url = "$DATABASE_URL"
cell_name = "$CELL_NAME"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    cursor.execute("SELECT state, last_shutdown FROM instance_state WHERE cell_name = %s;", (cell_name,))
    result = cursor.fetchone()
    if result:
        state, last_shutdown = result
        if state == 'created' and last_shutdown is None:
            print(f"Ячейка {cell_name} создана впервые.")
        elif state == 'sleeping' and last_shutdown is not None:
            print(f"Ячейка {cell_name} проснулась после сна.")
            cursor.execute("UPDATE instance_state SET state = 'awake', last_startup = CURRENT_TIMESTAMP WHERE cell_name = %s;", (cell_name,))
        else:
            print(f"Неизвестное состояние ячейки {cell_name}.")
    conn.commit()
except Exception as e:
    print(f"Ошибка проверки состояния: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Восстановление данных из базы в /data
restore_data_from_db() {
    echo "Запуск restore_data_from_db"
    python - <<EOF
import psycopg2
import os
import tarfile
import io

data_dir = "$DATA_DIR"
db_url = "$DATABASE_URL"
cell_key = "$DB_CELL_KEY"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    cursor.execute("SELECT content FROM cell_data WHERE cell_key = %s;", (cell_key,))
    result = cursor.fetchone()
    if result:
        tar_data = result[0]
        if not os.path.exists(data_dir):
            os.makedirs(data_dir)
        with tarfile.open(fileobj=io.BytesIO(tar_data), mode="r") as tar:
            tar.extractall(path=data_dir)
            print("Восстановленные файлы и директории:")
            for member in tar.getnames():
                print(f" - {member}")
        print(f"Данные для ячейки с ключом {cell_key} восстановлены в {data_dir}!")
        # Удаляем данные из базы после восстановления
        cursor.execute("DELETE FROM cell_data WHERE cell_key = %s;", (cell_key,))
        conn.commit()
        print(f"Данные для ячейки с ключом {cell_key} удалены из базы после восстановления.")
    else:
        print(f"В базе нет данных для ключа {cell_key}, ждём создания файлов в {data_dir}.")
except Exception as e:
    print(f"Ошибка восстановления данных: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Сохранение данных из /data в базу с ключом data_$CELL_NAME
save_data_to_db() {
    echo "Запуск save_data_to_db"
    python - <<EOF
import psycopg2
import os
import tarfile
import io

data_dir = "$DATA_DIR"
db_url = "$DATABASE_URL"
cell_key = "$DB_CELL_KEY"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    # Удаляем старую запись для этого ключа
    cursor.execute("DELETE FROM cell_data WHERE cell_key = %s;", (cell_key,))
    if os.path.exists(data_dir) and os.listdir(data_dir):  # Проверяем, есть ли файлы в /data
        tar_buffer = io.BytesIO()
        with tarfile.open(fileobj=tar_buffer, mode="w") as tar:
            tar.add(data_dir, arcname=os.path.basename(data_dir))
            print("Сохраняемые файлы и директории:")
            for member in tar.getmembers():
                print(f" - {member.name}")
        tar_buffer.seek(0)
        tar_data = tar_buffer.read()
        cursor.execute("""
            INSERT INTO cell_data (cell_key, content)
            VALUES (%s, %s);
        """, (cell_key, psycopg2.Binary(tar_data)))
        print(f"Данные из {data_dir} сохранены в базу с ключом {cell_key}, старая запись удалена!")
    else:
        print(f"Директория {data_dir} пуста или не существует, ничего не сохраняем.")
    cursor.execute("UPDATE instance_state SET state = 'sleeping', last_shutdown = CURRENT_TIMESTAMP WHERE cell_name = %s;", ("$CELL_NAME",))
    conn.commit()
except Exception as e:
    print(f"Ошибка сохранения данных: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
EOF
}

# Периодическое автосохранение данных
auto_save() {
    echo "Запуск auto_save в фоновом режиме"
    while true; do
        save_data_to_db
        sleep 60  # Увеличили до 60 секунд, чтобы дать hikka время создать файлы
    done
}
auto_save &

# Генерация внешнего трафика
keep_alive() {
    echo "Запуск keep_alive"
    urls=(
        "https://api.github.com/repos/hikariatama/Hikka/commits?per_page=10"
        "https://httpbin.org/stream/20"
        "https://httpbin.org/get"
    )
    while true; do
        for url in "${urls[@]}"; do
            curl -s "$url" -o /dev/null &
        done
        sleep 5
    done
}
keep_alive &

# Мониторинг запрещённых утилит
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

# Инициализация, проверка состояния и восстановление данных
echo "Инициализация скрипта"
init_db
check_instance_state
restore_data_from_db

# Перехват SIGTERM от Render для сохранения данных перед "засыпанием"
echo "Установка trap для SIGTERM"
trap 'echo "Получен SIGTERM, сохраняем данные..."; save_data_to_db; echo "Данные сохранены, завершаем работу."; exit 0' SIGTERM SIGINT

# Запуск приложения
echo "Запуск hikka"
exec python3 -m hikka
