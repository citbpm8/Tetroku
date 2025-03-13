FROM python:3.10-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3-dev gcc build-essential net-tools curl libcairo2 ffmpeg libmagic1 neofetch \
    wkhtmltopdf && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

RUN git clone https://github.com/Roger-git-cmd/Djtjtdhrsutdjtvjbvkhgoufl7fi6du5d7464e47du5dy4dutdkyfkug.igitl7fi6du4a4uaurdktsrusu5sitdgjfjbvkhfiy /Heroku

RUN python -m venv /Heroku/venv && \
    /Heroku/venv/bin/python -m pip install --upgrade pip && \
    /Heroku/venv/bin/pip install --no-cache-dir -r /Heroku/requirements.txt requests

FROM python:3.10-slim

ENV DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PIP_NO_CACHE_DIR=1 \
    PATH="/Heroku/venv/bin:$PATH"

COPY --from=builder /Heroku /Heroku
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

WORKDIR /Heroku

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
