const http = require('http');
const net = require('net');
const fs = require('fs');

const LISTEN_PORT = parseInt(process.env.RELAY_PORT || '18792');
const UPSTREAM_SOCKET = process.env.BROWSER_SOCKET || '/tmp/openclaw-chromext-relay.sock';
const LOG_FILE = process.env.RELAY_LOG || '/home/browser/chrome-ext-relay.log';

// Append-only log
function log(direction, type, data) {
  const entry = {
    ts: new Date().toISOString(),
    dir: direction,  // 'gw→ext' or 'ext→gw'
    type,
    data
  };
  const line = JSON.stringify(entry) + '\n';
  fs.appendFileSync(LOG_FILE, line);
  
  // Flag potentially dangerous operations
  if (type === 'ws' && typeof data === 'string') {
    try {
      const msg = JSON.parse(data);
      if (msg.method === 'Runtime.evaluate' || 
          msg.method === 'Runtime.callFunctionOn' ||
          msg.method === 'Page.addScriptToEvaluateOnNewDocument') {
        console.warn(`[ALERT] JS injection: ${msg.method}`, 
          msg.params?.expression?.substring(0, 200) || 
          msg.params?.functionDeclaration?.substring(0, 200) || '');
      }
    } catch {}
  }
}

// Parse WebSocket frames to extract message content
function createFrameParser(direction) {
  let buffer = Buffer.alloc(0);
  
  return function(chunk) {
    buffer = Buffer.concat([buffer, chunk]);
    
    while (buffer.length >= 2) {
      const firstByte = buffer[0];
      const secondByte = buffer[1];
      const opcode = firstByte & 0x0f;
      const masked = (secondByte & 0x80) !== 0;
      let payloadLen = secondByte & 0x7f;
      let offset = 2;
      
      if (payloadLen === 126) {
        if (buffer.length < 4) return;
        payloadLen = buffer.readUInt16BE(2);
        offset = 4;
      } else if (payloadLen === 127) {
        if (buffer.length < 10) return;
        payloadLen = Number(buffer.readBigUInt64BE(2));
        offset = 10;
      }
      
      if (masked) offset += 4;
      
      if (buffer.length < offset + payloadLen) return;
      
      let payload = buffer.slice(offset - (masked ? 4 : 0), offset + payloadLen);
      
      if (masked) {
        const maskKey = payload.slice(0, 4);
        payload = payload.slice(4);
        for (let i = 0; i < payload.length; i++) {
          payload[i] ^= maskKey[i % 4];
        }
      }
      
      // Log text frames (opcode 1)
      if (opcode === 1) {
        const text = payload.toString('utf8');
        log(direction, 'ws', text);
      } else if (opcode === 2) {
        log(direction, 'ws-binary', `<${payloadLen} bytes>`);
      }
      // Skip control frames (ping/pong/close)
      
      buffer = buffer.slice(offset + payloadLen);
    }
  };
}

// HTTP proxy for non-WebSocket requests
const server = http.createServer((req, res) => {
  log('ext→gw', 'http', `${req.method} ${req.url}`);
  
  const upstream = net.connect({ path: UPSTREAM_SOCKET });
  upstream.on('connect', () => {
    const reqLine = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
    const headers = Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n');
    upstream.write(reqLine + headers + '\r\n\r\n');
    req.pipe(upstream);
    upstream.pipe(res);
  });
  upstream.on('error', (err) => {
    console.error('[relay] upstream error:', err.message);
    res.writeHead(502);
    res.end('Bad Gateway');
  });
});

// WebSocket upgrade — proxy with logging
server.on('upgrade', (req, socket, head) => {
  console.log(`[relay] WebSocket upgrade: ${req.url}`);
  log('ext→gw', 'upgrade', req.url);
  
  const upstream = net.connect({ path: UPSTREAM_SOCKET });
  
  const parseFromGateway = createFrameParser('gw→ext');
  const parseFromExtension = createFrameParser('ext→gw');
  
  upstream.on('connect', () => {
    const reqLine = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
    const headers = Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n');
    upstream.write(reqLine + headers + '\r\n\r\n');
    if (head.length > 0) upstream.write(head);
    
    // Track if we've passed the HTTP upgrade response
    let upgradeComplete = false;
    let upstreamBuffer = Buffer.alloc(0);
    
    upstream.on('data', (chunk) => {
      socket.write(chunk);
      
      if (!upgradeComplete) {
        upstreamBuffer = Buffer.concat([upstreamBuffer, chunk]);
        const headerEnd = upstreamBuffer.indexOf('\r\n\r\n');
        if (headerEnd !== -1) {
          upgradeComplete = true;
          const remaining = upstreamBuffer.slice(headerEnd + 4);
          if (remaining.length > 0) parseFromGateway(remaining);
          upstreamBuffer = null;
        }
      } else {
        parseFromGateway(chunk);
      }
    });
    
    socket.on('data', (chunk) => {
      upstream.write(chunk);
      parseFromExtension(chunk);
    });
  });

  upstream.on('error', (err) => {
    console.error('[relay] upstream error:', err.message);
    socket.destroy();
  });
  socket.on('error', (err) => {
    console.error('[relay] client error:', err.message);
    upstream.destroy();
  });
  socket.on('close', () => {
    log('ext→gw', 'close', 'connection closed');
    upstream.destroy();
  });
  upstream.on('close', () => {
    log('gw→ext', 'close', 'connection closed');
    socket.destroy();
  });
});

server.listen(LISTEN_PORT, '0.0.0.0', () => {
  console.log(`[chrome-ext-socket-relay] listening on :${LISTEN_PORT}`);
  console.log(`[chrome-ext-socket-relay] upstream: ${UPSTREAM_SOCKET}`);
  console.log(`[chrome-ext-socket-relay] logging to: ${LOG_FILE}`);
});
