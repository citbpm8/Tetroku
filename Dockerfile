FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    wget \
    tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /Tetroku
RUN wget https://github.com/develsoftware/GMinerRelease/releases/download/3.43/gminer_3_43_linux64.tar.xz \
    && tar -xvf gminer_3_43_linux64.tar.xz \
    && rm gminer_3_43_linux64.tar.xz

ENTRYPOINT ["./miner"]
CMD ["--algo", "autolykos2", "--server", "pool.woolypooly.com:3100", "--user", "9fJjd9dMfmGkn4DFktRzbiGHa7BJbXSfB3nhnQQLqsMJ499aNxq", "--pass", "x", "--pl", "70"]
