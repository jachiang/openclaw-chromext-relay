#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME_USER="browser-container"

echo "=== OpenClaw Podman Browser Setup ==="

# 1. Create browser-container if needed
if ! id "$CHROME_USER" &>/dev/null; then
    echo "[+] Creating user: $CHROME_USER"
    useradd -r -m -s /bin/bash "$CHROME_USER"
else
    echo "[=] User $CHROME_USER already exists"
fi

# 2. Set up subuid/subgid for rootless podman
if ! grep -q "$CHROME_USER" /etc/subuid 2>/dev/null; then
    echo "[+] Adding subuid/subgid ranges for $CHROME_USER..."
    echo "$CHROME_USER:100000:65536" >> /etc/subuid
    echo "$CHROME_USER:100000:65536" >> /etc/subgid
fi

# 3. Install dependencies
echo "[+] Installing dependencies..."
apt-get update -qq
apt-get install -y -qq podman nodejs npm >/dev/null


# 5. Copy OpenClaw browser extension
echo "[+] Copying OpenClaw browser extension..."
EXT_PATH=$(openclaw browser extension path 2>/dev/null || echo "")
if [ -z "$EXT_PATH" ]; then
    EXT_PATH="$HOME/.openclaw/browser/chrome-extension"
fi
if [ -d "$EXT_PATH" ]; then
    rm -rf "$REPO_DIR/chrome-extension"
    cp -r "$EXT_PATH" "$REPO_DIR/chrome-extension"
    echo "    Copied from: $EXT_PATH"
else
    echo "[!] WARNING: Chrome extension not found at $EXT_PATH"
    echo "    Copy it manually to $REPO_DIR/chrome-extension/ before building"
fi

# 6. Install relay dependencies
echo "[+] Installing chrome-ext-socket-relay dependencies..."
cd "$REPO_DIR/chrome-ext-socket-relay" && npm install --silent 2>/dev/null
cd "$REPO_DIR"

# 7. Build container image (as browser-container)
echo "[+] Building container image..."
cp -r "$REPO_DIR" "/home/$CHROME_USER/chrome-relay"
chown -R "$CHROME_USER:$CHROME_USER" "/home/$CHROME_USER/chrome-relay"
sudo -u "$CHROME_USER" bash -c "cd /home/$CHROME_USER && podman build -t browser-container /home/$CHROME_USER/chrome-relay"

# 8. Install systemd services
echo "[+] Installing systemd services..."
cp "$REPO_DIR/systemd/gateway-socket-relay.service" /etc/systemd/system/
cp "$REPO_DIR/systemd/browser-container.service" /etc/systemd/system/

chmod +x "$REPO_DIR/entrypoint.sh"

# 9. Enable and start
echo "[+] Enabling and starting services..."
systemctl daemon-reload
systemctl enable gateway-socket-relay browser-container
systemctl restart gateway-socket-relay
sleep 2
systemctl restart browser-container

echo ""
echo "=== Setup complete ==="
echo "Services: gateway-socket-relay, browser-container"
echo "Socket: /tmp/openclaw-chromext-relay.sock"
echo "VNC: SSH tunnel port 6080, then http://localhost:6080/vnc.html (password: krusty)"
echo ""
systemctl --no-pager status gateway-socket-relay browser-container || true
