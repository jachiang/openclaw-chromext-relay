#!/bin/bash
set -e

# Start virtual display
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99
sleep 1

# Start Chrome
chromium \
  --no-first-run --no-default-browser-check \
  --disable-gpu --disable-dev-shm-usage \
  --user-data-dir=/home/browser/chrome-data \
  --load-extension=/opt/chrome-extension \
  --disable-extensions-except=/opt/chrome-extension \
  "about:blank" &

sleep 2

# Start VNC + noVNC
x11vnc -display :99 -forever -passwd krusty -rfbport 5900 &
websockify --web /usr/share/novnc 6080 localhost:5900 &

# Start chrome-ext-socket-relay with auto-restart
(while true; do
  cd /opt/chrome-ext-socket-relay
  echo "[$(date)] Starting chrome-ext-socket-relay..."
  node relay.js 2>&1
  echo "[$(date)] chrome-ext-socket-relay exited, restarting in 3s..."
  sleep 3
done) &

echo "Browser container ready"
wait
