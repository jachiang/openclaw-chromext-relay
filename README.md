# OpenClaw Chrome Extension Relay

Run Chrome in a Podman container, fully isolated from the OpenClaw gateway, communicating only through a Unix socket.

## Architecture

```
┌─────────────────────────────────────┐
│  Host                               │
│                                     │
│  OpenClaw Gateway (:18792)          │
│       ↕                             │
│  gateway-socket-relay               │
│  (Gateway:18792 ↔ Unix socket)      │
│       ↕                             │
│  /tmp/openclaw-chromext-relay.sock   │
└──────────┼──────────────────────────┘
           │  (bind-mounted into container)
┌──────────┼──────────────────────────┐
│  Podman Container (rootless)        │
│  (user: browser)                    │
│                                     │
│  chrome-ext-socket-relay            │
│  (Unix socket ↔ :18792)             │
│  ├─ HTTP/WebSocket proxy            │
│  ├─ WebSocket message logging       │
│  ├─ JS injection alerts             │
│       ↕                             │
│  Chrome + OpenClaw Extension        │
│  (connects ws://127.0.0.1:18792)    │
│                                     │
│  Xvfb :99 (1920x1080)              │
│  x11vnc → noVNC (:6080)            │
└─────────────────────────────────────┘
```

### How it works

1. **gateway-socket-relay** (host) listens on `/tmp/openclaw-chromext-relay.sock` and forwards all traffic to the OpenClaw gateway on `localhost:18792`.
2. The socket is bind-mounted into the container.
3. **chrome-ext-socket-relay** (container) listens on container-local `:18792` and forwards to the Unix socket.
4. The **OpenClaw Chrome extension** connects to `ws://127.0.0.1:18792` inside the container — its default behavior — and reaches the gateway through the relay chain.

The browser process **never has direct network access to the gateway**. All communication goes through the inspectable Unix socket relay.

### Authentication

The Chrome extension does not authenticate with a token. Security relies on:
- The socket is only accessible to local users on the host
- The container can only reach the gateway through the socket (no direct TCP)
- The gateway's own auth token protects its HTTP API separately

## Purpose & Motivation

- **Security isolation**: Chrome runs in a separate user namespace with no direct access to host processes or the gateway.
- **Inspectability**: The relay logs all WebSocket messages and alerts on JS injection attempts (`Runtime.evaluate`, `Runtime.callFunctionOn`, `Page.addScriptToEvaluateOnNewDocument`).
- **Reproducibility**: Everything needed to recreate the setup is in this repo.
- **Requirement**: OpenClaw must NOT be a parent process of the browser. Podman satisfies this — the container's process tree is completely separate.

## Prerequisites

- Ubuntu/Debian (tested on Ubuntu 24.04)
- Podman (`apt install podman`)
- Node.js 18+ (`apt install nodejs npm`)
- OpenClaw installed (for the browser extension)

## Quick Start

```bash
git clone https://github.com/jachiang/openclaw-chromext-relay.git
cd openclaw-chromext-relay
chmod +x install.sh
sudo ./install.sh
```

The install script will:
1. Create a dedicated system user for rootless Podman
2. Set up subuid/subgid for rootless containers
3. Copy the OpenClaw browser extension into the build context
4. Build the container image (rootless)
5. Install and enable systemd services
6. Start everything

## Security Properties

| Property | Status |
|---|---|
| Browser in separate PID namespace | ✅ Podman |
| Browser in separate network namespace | ✅ slirp4netns |
| Browser runs as unprivileged user | ✅ `browser` inside container |
| No direct TCP to gateway | ✅ Unix socket only |
| Socket permissions | `666` in `/tmp/` (localhost trust model) |
| Communication inspectable | ✅ WebSocket message logging |
| JS injection alerts | ✅ Logged to stderr |
| Message filtering | ⏳ Hook exists, not yet implemented |

## Accessing the Browser

noVNC runs inside the container on port 6080 (published to localhost).

```bash
ssh -L 6080:localhost:6080 your-server
# Open http://localhost:6080/vnc.html in your local browser
```

The Chrome extension must be manually activated — click the OpenClaw Browser Relay toolbar icon so the badge shows "ON" on the active tab.

## Systemd Services

| Service | Description |
|---|---|
| `gateway-socket-relay` | Host-side: Unix socket ↔ Gateway:18792 |
| `browser-container` | Podman container with Chrome + relays + noVNC |

```bash
# Check status
systemctl status gateway-socket-relay browser-container

# Restart everything
systemctl restart gateway-socket-relay browser-container

# View container logs
sudo -u browser-container podman logs -f browser-container

# Rebuild after changes
systemctl stop browser-container
sudo -u browser-container podman build -t browser-container .
systemctl start browser-container
```

## Repository Structure

```
openclaw-chromext-relay/
├── README.md
├── install.sh                  # Setup script
├── uninstall.sh                # Teardown script
├── Containerfile               # Container image definition
├── entrypoint.sh               # Container startup (Xvfb, Chrome, x11vnc, noVNC, relay)
├── chrome-ext-socket-relay/
│   ├── relay.js                # In-container: :18792 → Unix socket (with logging)
│   └── package.json
├── gateway-socket-relay/
│   └── relay.js                # Host-side: Unix socket → Gateway:18792
└── systemd/
    ├── gateway-socket-relay.service
    └── browser-container.service
```

## Troubleshooting

### Socket not created
Check that `gateway-socket-relay` is running:
```bash
systemctl status gateway-socket-relay
ls -la /tmp/openclaw-chromext-relay.sock
```

### Chrome extension not connecting
The extension must be activated per-tab — click the toolbar icon in the VNC session so the badge shows "ON".

### Container won't start (name conflict)
```bash
sudo -u browser-container podman rm -f browser-container
systemctl start browser-container
```

### Relay crashes on first message
Check the log path is writable by the container's `browser` user. The relay logs to `~/chrome-ext-relay.log` inside the container.

## Future Work

- [ ] Message filtering in chrome-ext-socket-relay (inspect/block specific CDP commands)
- [ ] `--cap-drop ALL` (removed due to Chrome sandbox requirements)
- [ ] Auto-activate extension (currently requires manual VNC click)
- [ ] Health checks (systemd watchdog or container HEALTHCHECK)
