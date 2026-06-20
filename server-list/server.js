'use strict';

const dgram = require('node:dgram');
const dns = require('node:dns').promises;
const http = require('node:http');
const net = require('node:net');

const MASTER_PORT = Number(process.env.MASTER_PORT || 20810);
const HTTP_PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';
const SERVER_LIST = (process.env.SERVERS || 'mp1.swifly.net:1154')
  .split(',')
  .map((server) => server.trim())
  .filter(Boolean);

const RESPONSE_HEADER = Buffer.from('\xff\xff\xff\xffgetServersResponse ', 'latin1');

function parseHostPort(value) {
  const separator = value.lastIndexOf(':');
  if (separator <= 0 || separator === value.length - 1) {
    throw new Error(`Invalid server address "${value}". Expected host:port.`);
  }

  const host = value.slice(0, separator).trim();
  const port = Number(value.slice(separator + 1));

  if (!host || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`Invalid server address "${value}". Expected host:port.`);
  }

  return { host, port };
}

async function resolveIpv4(host) {
  if (net.isIPv4(host)) {
    return host;
  }

  const result = await dns.lookup(host, { family: 4 });
  return result.address;
}

async function buildServerEntries() {
  const entries = [];

  for (const raw of SERVER_LIST) {
    try {
      const { host, port } = parseHostPort(raw);
      const ip = await resolveIpv4(host);
      const octets = ip.split('.').map((part) => Number(part));

      if (octets.length !== 4 || octets.some((part) => part < 0 || part > 255)) {
        throw new Error(`Resolved invalid IPv4 address: ${ip}`);
      }

      const entry = Buffer.alloc(7);
      entry[0] = octets[0];
      entry[1] = octets[1];
      entry[2] = octets[2];
      entry[3] = octets[3];
      entry.writeUInt16BE(port, 4);
      entry[6] = 0x5c; // backslash separator expected by the client
      entries.push(entry);
    } catch (error) {
      console.error(`[MASTER] Skipping ${raw}: ${error.message}`);
    }
  }

  return entries;
}

async function buildGetServersResponse() {
  const entries = await buildServerEntries();
  return Buffer.concat([RESPONSE_HEADER, ...entries]);
}

function getPacketCommand(message) {
  if (message.length < 5) {
    return '';
  }

  const hasConnectionlessHeader =
    message[0] === 0xff && message[1] === 0xff && message[2] === 0xff && message[3] === 0xff;

  const offset = hasConnectionlessHeader ? 4 : 0;
  return message.toString('latin1', offset).split(/\s+/)[0].toLowerCase();
}

const udp = dgram.createSocket('udp4');

udp.on('message', async (message, remote) => {
  const command = getPacketCommand(message);

  if (command !== 'getservers') {
    console.log(`[MASTER] Ignored ${command || 'unknown'} from ${remote.address}:${remote.port}`);
    return;
  }

  try {
    const response = await buildGetServersResponse();
    udp.send(response, remote.port, remote.address);
    console.log(`[MASTER] Sent ${SERVER_LIST.join(', ')} to ${remote.address}:${remote.port}`);
  } catch (error) {
    console.error(`[MASTER] Failed to respond to ${remote.address}:${remote.port}:`, error);
  }
});

udp.on('error', (error) => {
  console.error('[MASTER] UDP error:', error);
});

udp.bind(MASTER_PORT, HOST, () => {
  console.log(`[MASTER] Swifly UDP master listening on ${HOST}:${MASTER_PORT}`);
  console.log(`[MASTER] Servers: ${SERVER_LIST.join(', ')}`);
});

const httpServer = http.createServer((req, res) => {
  const payload = {
    name: 'Swifly Server List',
    master: `udp://${process.env.PUBLIC_HOST || 'client.swifly.net'}:${MASTER_PORT}`,
    servers: SERVER_LIST,
  };

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('ok');
    return;
  }

  if (req.url === '/servers.json') {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(payload, null, 2));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Swifly Server List</title>
  <style>
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #07080d; color: #f5f7ff; font-family: Inter, system-ui, sans-serif; }
    main { width: min(720px, calc(100% - 32px)); padding: 32px; border: 1px solid rgba(255,255,255,.12); border-radius: 24px; background: linear-gradient(145deg, rgba(255,255,255,.08), rgba(255,255,255,.03)); box-shadow: 0 24px 90px rgba(0,0,0,.45); }
    h1 { margin: 0 0 8px; font-size: clamp(32px, 6vw, 58px); letter-spacing: -0.06em; }
    p { color: #aeb6d6; line-height: 1.6; }
    code { display: inline-block; padding: 8px 10px; border-radius: 10px; background: rgba(255,255,255,.08); color: #ffffff; }
    .server { margin-top: 20px; padding: 16px; border-radius: 16px; background: rgba(90,120,255,.12); border: 1px solid rgba(130,150,255,.22); }
  </style>
</head>
<body>
  <main>
    <h1>Swifly Server List</h1>
    <p>This domain is running the Swifly UDP master server for the in-game server browser.</p>
    <p>Master endpoint: <code>client.swifly.net:${MASTER_PORT}</code></p>
    <div class="server"><strong>Listed server:</strong> <code>${SERVER_LIST.join('</code>, <code>')}</code></div>
    <p>JSON: <a href="/servers.json" style="color:#b9c5ff">/servers.json</a></p>
  </main>
</body>
</html>`);
});

httpServer.listen(HTTP_PORT, HOST, () => {
  console.log(`[HTTP] Status page listening on ${HOST}:${HTTP_PORT}`);
});
