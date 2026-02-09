const net = require('net');
const fs = require('fs');

const SOCKET_PATH = process.env.BROWSER_SOCKET || '/tmp/openclaw-chromext-relay.sock';
const GATEWAY_HOST = process.env.GATEWAY_HOST || '127.0.0.1';
const GATEWAY_PORT = parseInt(process.env.GATEWAY_PORT || '18792');

try { fs.unlinkSync(SOCKET_PATH); } catch {}

const server = net.createServer((client) => {
  const target = net.connect({ host: GATEWAY_HOST, port: GATEWAY_PORT }, () => {
    client.pipe(target);
    target.pipe(client);
  });
  target.on('error', (err) => {
    console.error('[gateway-relay] target error:', err.message);
    client.destroy();
  });
  client.on('error', (err) => {
    console.error('[gateway-relay] client error:', err.message);
    target.destroy();
  });
});

server.listen(SOCKET_PATH, () => {
  fs.chmodSync(SOCKET_PATH, 0o666);
  try {
  } catch {}
  console.log(`[gateway-socket-relay] ${SOCKET_PATH} → ${GATEWAY_HOST}:${GATEWAY_PORT}`);
});
