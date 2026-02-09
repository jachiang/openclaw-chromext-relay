#!/bin/bash
set -euo pipefail

CHROME_USER="browser-container"

echo "=== OpenClaw Podman Browser Teardown ==="

# 1. Stop and disable services
echo "[+] Stopping services..."
systemctl stop browser-container gateway-socket-relay 2>/dev/null || true
systemctl disable browser-container gateway-socket-relay 2>/dev/null || true

# 2. Remove container and image (as browser-container for rootless podman)
echo "[+] Removing container and image..."
if id "$CHROME_USER" &>/dev/null; then
    sudo -u "$CHROME_USER" podman stop -t 5 browser-container 2>/dev/null || true
    sudo -u "$CHROME_USER" podman rm -f browser-container 2>/dev/null || true
    sudo -u "$CHROME_USER" podman rmi browser-container:latest 2>/dev/null || true
fi
# Also try system-wide in case it was run that way
podman rm -f browser-container 2>/dev/null || true
podman rmi browser-container:latest 2>/dev/null || true

# 3. Remove systemd units
echo "[+] Removing systemd units..."
rm -f /etc/systemd/system/gateway-socket-relay.service
rm -f /etc/systemd/system/browser-container.service
# tmpfiles.d no longer needed (socket in /tmp/)
systemctl daemon-reload

# 4. Clean up runtime directory

# 5. Clean up browser-container build directory
if [ -d "/home/$CHROME_USER/chrome-relay" ]; then
    echo "[+] Removing /home/$CHROME_USER/chrome-relay..."
    rm -rf "/home/$CHROME_USER/chrome-relay"
fi

# 6. Optionally remove browser-container
read -p "Remove $CHROME_USER user and home directory? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Remove subuid/subgid entries
    sed -i "/^$CHROME_USER:/d" /etc/subuid 2>/dev/null || true
    sed -i "/^$CHROME_USER:/d" /etc/subgid 2>/dev/null || true
    userdel -r "$CHROME_USER" 2>/dev/null || true
    echo "    Removed $CHROME_USER"
fi

echo ""
echo "=== Teardown complete ==="
echo "Note: This repo is still at $(cd "$(dirname "$0")" && pwd)"
echo "Note: podman, nodejs, npm packages were NOT removed"
