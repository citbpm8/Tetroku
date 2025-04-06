FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    libuv1-dev \
    libssl-dev \
    libhwloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /Tetroku
RUN git clone https://github.com/xmrig/xmrig.git \
    && cd xmrig \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make

WORKDIR /Tetroku/xmrig/build
ENTRYPOINT ["./xmrig"]
CMD ["--url", "node.xmr.rocks:18089", "--user", "4AsybUjHWc3LtcJj7h7yd9NJ3JXQynQUneMTpoTALYgmSFNW6XLmYGGLR5rHr3zcfjbPZ6dHp9MSdLiDBAXd4wKQ5ufR6vv.KoyebMiner", "--pass", "x", "--threads", "6", "--cpu-max-threads-hint", "86"]
