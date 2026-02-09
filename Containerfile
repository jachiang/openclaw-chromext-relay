FROM docker.io/library/debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium chromium-sandbox \
    xvfb x11vnc novnc python3-websockify \
    nodejs npm \
    socat \
    dbus-x11 fonts-liberation fonts-noto-color-emoji \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash browser

COPY chrome-extension/ /opt/chrome-extension/
COPY chrome-ext-socket-relay/ /opt/chrome-ext-socket-relay/
RUN cd /opt/chrome-ext-socket-relay && npm install

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER browser
ENTRYPOINT ["/entrypoint.sh"]
