#!/bin/bash
set -eo pipefail

python3 -m hikka --port "$PORT" &

keep_alive_bash() {
  while true; do
    sleep 150
    curl -s "https://$RENDER_EXTERNAL_HOSTNAME" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "Ошибка запроса keep_alive"
    fi
  done
}

keep_alive_bash &
