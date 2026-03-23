/**
 * LockSync WebSocket Relay Server
 *
 * Architecture: Thin relay — the server exists ONLY to:
 *   1. Generate & validate 6-digit pairing codes
 *   2. Issue long-lived JWTs after successful pairing (permanent pairing)
 *   3. Forward message deltas between paired devices in real-time
 *
 * Pairs are persisted to DATA_DIR/pairs.json so they survive server restarts.
 * No database needed — just a mounted Docker volume at /app/data.
 *
 * The VPS is a "secure postman": authenticates the pair once, then
 * blindly forwards sealed envelopes between them forever.
 */

require('dotenv').config();
const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');

// ─── Config ──────────────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT, 10) || 8080;
const JWT_SECRET = process.env.JWT_SECRET || (() => {
  console.error('FATAL: JWT_SECRET is not set. Exiting.');
  process.exit(1);
})();
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '*').split(',').map(s => s.trim());
const PAIR_CODE_TTL = parseInt(process.env.PAIR_CODE_TTL, 10) || 300;       // seconds
const JWT_EXPIRY = process.env.JWT_EXPIRY || '365d';                          // permanent
const JWT_REFRESH_EXPIRY = process.env.JWT_REFRESH_EXPIRY || '730d';         // 2 years
const PAIR_RATE_LIMIT = parseInt(process.env.PAIR_RATE_LIMIT, 10) || 10;
const MAX_MESSAGE_SIZE = parseInt(process.env.MAX_MESSAGE_SIZE, 10) || 16384;
const DATA_DIR = process.env.DATA_DIR || '/app/data';
const PAIRS_FILE = path.join(DATA_DIR, 'pairs.json');

// ─── Pair persistence ────────────────────────────────────────────────
// Saved structure: { pairId: { deviceAId, deviceBId, createdAt } }
// WS connections are not saved (they're ephemeral). On load we re-hydrate
// the pair map without ws references; devices re-attach on authenticate.

function ensureDataDir() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  } catch (e) {
    console.error('[STORE] Cannot create data dir:', e.message);
  }
}

function savePairs() {
  try {
    const data = {};
    for (const [pairId, pair] of activePairs) {
      data[pairId] = {
        deviceAId: pair.deviceA.id,
        deviceBId: pair.deviceB.id,
        createdAt: pair.createdAt,
      };
    }
    fs.writeFileSync(PAIRS_FILE, JSON.stringify(data, null, 2));
  } catch (e) {
    console.error('[STORE] Failed to save pairs:', e.message);
  }
}

function loadPairs() {
  try {
    if (!fs.existsSync(PAIRS_FILE)) return;
    const data = JSON.parse(fs.readFileSync(PAIRS_FILE, 'utf8'));
    let loaded = 0;
    for (const [pairId, entry] of Object.entries(data)) {
      activePairs.set(pairId, {
        deviceA: { id: entry.deviceAId, ws: null },
        deviceB: { id: entry.deviceBId, ws: null },
        createdAt: entry.createdAt,
        _bothOfflineSince: null,
      });
      deviceToPair.set(entry.deviceAId, pairId);
      deviceToPair.set(entry.deviceBId, pairId);
      loaded++;
    }
    console.log(`[STORE] Loaded ${loaded} persisted pair(s)`);
  } catch (e) {
    console.error('[STORE] Failed to load pairs:', e.message);
  }
}

// ─── In-memory stores ────────────────────────────────────────────────
/** Pending pairing codes: code → { deviceId, createdAt, ws } */
const pairingCodes = new Map();

/** Active pairs: pairId → { deviceA: { id, ws }, deviceB: { id, ws }, createdAt } */
const activePairs = new Map();

/** Device → pairId lookup for fast disconnect cleanup */
const deviceToPair = new Map();

/** Rate limiter: IP → { count, windowStart } */
const rateLimits = new Map();

// ─── HTTP server (health check + upgrade) ────────────────────────────
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      pairs: activePairs.size,
      pendingCodes: pairingCodes.size,
      uptime: process.uptime(),
    }));
    return;
  }
  res.writeHead(404);
  res.end();
});

// ─── WebSocket server ────────────────────────────────────────────────
const wss = new WebSocketServer({
  server,
  maxPayload: MAX_MESSAGE_SIZE,
  verifyClient: ({ req }, done) => {
    // Origin validation: block cross-origin web requests, but allow native
    // app connections (Android/iOS dart:io WebSocket sends no Origin header).
    if (ALLOWED_ORIGINS[0] !== '*') {
      const origin = req.headers.origin;
      if (origin && !ALLOWED_ORIGINS.includes(origin)) {
        done(false, 403, 'Origin not allowed');
        return;
      }
    }
    done(true);
  },
});

wss.on('connection', (ws, req) => {
  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress;
  ws._ip = ip;
  ws._deviceId = null;
  ws._pairId = null;
  ws._authenticated = false;

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      sendError(ws, 'INVALID_JSON', 'Message must be valid JSON');
      return;
    }

    if (!msg.type) {
      sendError(ws, 'MISSING_TYPE', 'Message must have a "type" field');
      return;
    }

    switch (msg.type) {
      case 'request_code':
        handleRequestCode(ws, msg);
        break;
      case 'join_code':
        handleJoinCode(ws, msg, ip);
        break;
      case 'authenticate':
        handleAuthenticate(ws, msg);
        break;
      case 'refresh_token':
        handleRefreshToken(ws, msg);
        break;
      case 'sync':
        handleSync(ws, msg);
        break;
      case 'ping':
        send(ws, { type: 'pong', ts: Date.now() });
        break;
      default:
        sendError(ws, 'UNKNOWN_TYPE', `Unknown message type: ${msg.type}`);
    }
  });

  ws.on('close', () => handleDisconnect(ws));
  ws.on('error', () => handleDisconnect(ws));
});

// ─── Pairing: Device A requests a code ───────────────────────────────
function handleRequestCode(ws, msg) {
  const deviceId = msg.deviceId;
  if (!deviceId || typeof deviceId !== 'string' || deviceId.length < 8) {
    sendError(ws, 'INVALID_DEVICE_ID', 'Provide a valid deviceId (min 8 chars)');
    return;
  }

  // Clean up any existing code from this device
  for (const [code, entry] of pairingCodes) {
    if (entry.deviceId === deviceId) {
      pairingCodes.delete(code);
    }
  }

  const code = generatePairCode();
  pairingCodes.set(code, {
    deviceId,
    createdAt: Date.now(),
    ws,
  });

  ws._deviceId = deviceId;

  // Auto-expire the code
  setTimeout(() => {
    if (pairingCodes.has(code)) {
      const entry = pairingCodes.get(code);
      pairingCodes.delete(code);
      if (entry.ws.readyState === 1) {
        send(entry.ws, { type: 'code_expired', code });
      }
    }
  }, PAIR_CODE_TTL * 1000);

  send(ws, { type: 'code_created', code, expiresIn: PAIR_CODE_TTL });
  console.log(`[PAIR] Code ${code} created for device ${deviceId.slice(0, 8)}…`);
}

// ─── Pairing: Device B joins with a code ─────────────────────────────
function handleJoinCode(ws, msg, ip) {
  // Rate limiting
  if (!checkRateLimit(ip)) {
    sendError(ws, 'RATE_LIMITED', 'Too many pairing attempts. Try again later.');
    return;
  }

  const { code, deviceId } = msg;
  if (!code || !deviceId || typeof deviceId !== 'string' || deviceId.length < 8) {
    sendError(ws, 'INVALID_REQUEST', 'Provide code and deviceId');
    return;
  }

  const entry = pairingCodes.get(code);
  if (!entry) {
    sendError(ws, 'INVALID_CODE', 'Code not found or expired');
    return;
  }

  if (entry.deviceId === deviceId) {
    sendError(ws, 'SELF_PAIR', 'Cannot pair with yourself');
    return;
  }

  // Check expiry
  if (Date.now() - entry.createdAt > PAIR_CODE_TTL * 1000) {
    pairingCodes.delete(code);
    sendError(ws, 'CODE_EXPIRED', 'Pairing code has expired');
    return;
  }

  // Consume the code
  pairingCodes.delete(code);

  // Create the pair
  const pairId = uuidv4();
  const pair = {
    deviceA: { id: entry.deviceId, ws: entry.ws },
    deviceB: { id: deviceId, ws },
    createdAt: Date.now(),
    _bothOfflineSince: null,
  };
  activePairs.set(pairId, pair);
  deviceToPair.set(entry.deviceId, pairId);
  deviceToPair.set(deviceId, pairId);

  ws._deviceId = deviceId;
  ws._pairId = pairId;
  entry.ws._pairId = pairId;

  // Issue long-lived JWTs to both devices
  const tokenA = issueTokens(entry.deviceId, pairId);
  const tokenB = issueTokens(deviceId, pairId);

  send(entry.ws, {
    type: 'paired',
    pairId,
    partnerId: deviceId,
    ...tokenA,
  });

  send(ws, {
    type: 'paired',
    pairId,
    partnerId: entry.deviceId,
    ...tokenB,
  });

  entry.ws._authenticated = true;
  ws._authenticated = true;

  // Persist to disk — this pair is now permanent
  savePairs();

  console.log(`[PAIR] Pair ${pairId.slice(0, 8)}… established: ${entry.deviceId.slice(0, 8)}… ↔ ${deviceId.slice(0, 8)}… (saved to disk)`);
}

// ─── Auth: reconnect with existing JWT ───────────────────────────────
function handleAuthenticate(ws, msg) {
  const { token } = msg;
  if (!token) {
    sendError(ws, 'MISSING_TOKEN', 'Provide a JWT token');
    return;
  }

  let payload;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch (err) {
    sendError(ws, 'INVALID_TOKEN', 'Token invalid or expired');
    return;
  }

  if (payload.tokenType !== 'access') {
    sendError(ws, 'WRONG_TOKEN_TYPE', 'Use an access token, not a refresh token');
    return;
  }

  const { deviceId, pairId } = payload;
  const pair = activePairs.get(pairId);

  if (!pair) {
    // Pair not in memory — can happen if JWT_SECRET changed (different server)
    sendError(ws, 'PAIR_NOT_FOUND', 'Pair session not found. Please re-pair.');
    return;
  }

  // Re-attach this WebSocket to the pair
  ws._deviceId = deviceId;
  ws._pairId = pairId;
  ws._authenticated = true;

  if (pair.deviceA.id === deviceId) {
    pair.deviceA.ws = ws;
  } else if (pair.deviceB.id === deviceId) {
    pair.deviceB.ws = ws;
  } else {
    sendError(ws, 'DEVICE_MISMATCH', 'Device not part of this pair');
    return;
  }

  deviceToPair.set(deviceId, pairId);

  const partnerId = pair.deviceA.id === deviceId ? pair.deviceB.id : pair.deviceA.id;

  send(ws, {
    type: 'authenticated',
    pairId,
    partnerId,
    partnerOnline: getPartnerWs(pair, deviceId)?.readyState === 1,
  });

  // Notify partner that we're back online
  const partnerWs = getPartnerWs(pair, deviceId);
  if (partnerWs?.readyState === 1) {
    send(partnerWs, { type: 'partner_online' });
  }

  console.log(`[AUTH] Device ${deviceId.slice(0, 8)}… reconnected to pair ${pairId.slice(0, 8)}…`);
}

// ─── Token refresh ───────────────────────────────────────────────────
function handleRefreshToken(ws, msg) {
  const { refreshToken } = msg;
  if (!refreshToken) {
    sendError(ws, 'MISSING_TOKEN', 'Provide a refreshToken');
    return;
  }

  let payload;
  try {
    payload = jwt.verify(refreshToken, JWT_SECRET);
  } catch {
    sendError(ws, 'INVALID_REFRESH_TOKEN', 'Refresh token invalid or expired');
    return;
  }

  if (payload.tokenType !== 'refresh') {
    sendError(ws, 'WRONG_TOKEN_TYPE', 'Use a refresh token');
    return;
  }

  // Only issue new tokens if the pair still exists
  if (!activePairs.has(payload.pairId)) {
    sendError(ws, 'PAIR_NOT_FOUND', 'Pair no longer exists. Please re-pair.');
    return;
  }

  const tokens = issueTokens(payload.deviceId, payload.pairId);
  send(ws, { type: 'token_refreshed', ...tokens });
}

// ─── Sync: forward message delta to partner ──────────────────────────
function handleSync(ws, msg) {
  if (!ws._authenticated) {
    sendError(ws, 'UNAUTHENTICATED', 'Authenticate first');
    return;
  }

  const pair = activePairs.get(ws._pairId);
  if (!pair) {
    sendError(ws, 'PAIR_NOT_FOUND', 'Pair no longer active');
    return;
  }

  const partnerWs = getPartnerWs(pair, ws._deviceId);
  if (!partnerWs || partnerWs.readyState !== 1) {
    send(ws, { type: 'partner_offline' });
    return;
  }

  // Forward the payload directly — zero inspection, maximum speed.
  send(partnerWs, {
    type: 'sync',
    from: ws._deviceId,
    payload: msg.payload,
    ts: Date.now(),
  });
}

// ─── Disconnect cleanup ──────────────────────────────────────────────
function handleDisconnect(ws) {
  if (!ws._deviceId) return;

  const pairId = ws._pairId || deviceToPair.get(ws._deviceId);
  if (!pairId) return;

  const pair = activePairs.get(pairId);
  if (!pair) return;

  // Notify partner of disconnect (but DON'T destroy the pair — it's permanent)
  const partnerWs = getPartnerWs(pair, ws._deviceId);
  if (partnerWs?.readyState === 1) {
    send(partnerWs, { type: 'partner_offline' });
  }

  console.log(`[DC] Device ${ws._deviceId.slice(0, 8)}… disconnected from pair ${pairId.slice(0, 8)}…`);
}

// ─── Helpers ─────────────────────────────────────────────────────────
function generatePairCode() {
  let code;
  do {
    code = String(Math.floor(100000 + Math.random() * 900000));
  } while (pairingCodes.has(code));
  return code;
}

function issueTokens(deviceId, pairId) {
  const accessToken = jwt.sign(
    { deviceId, pairId, tokenType: 'access' },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY }
  );
  const refreshToken = jwt.sign(
    { deviceId, pairId, tokenType: 'refresh' },
    JWT_SECRET,
    { expiresIn: JWT_REFRESH_EXPIRY }
  );
  return { accessToken, refreshToken };
}

function getPartnerWs(pair, myDeviceId) {
  return pair.deviceA.id === myDeviceId ? pair.deviceB.ws : pair.deviceA.ws;
}

function send(ws, data) {
  if (ws?.readyState === 1) {
    ws.send(JSON.stringify(data));
  }
}

function sendError(ws, code, message) {
  send(ws, { type: 'error', code, message });
}

function checkRateLimit(ip) {
  const now = Date.now();
  const entry = rateLimits.get(ip);

  if (!entry || now - entry.windowStart > 60000) {
    rateLimits.set(ip, { count: 1, windowStart: now });
    return true;
  }

  entry.count++;
  if (entry.count > PAIR_RATE_LIMIT) {
    return false;
  }
  return true;
}

// ─── Periodic cleanup ────────────────────────────────────────────────
setInterval(() => {
  const now = Date.now();

  // Clean expired pairing codes
  for (const [code, entry] of pairingCodes) {
    if (now - entry.createdAt > PAIR_CODE_TTL * 1000) {
      pairingCodes.delete(code);
    }
  }

  // NOTE: Permanent pairs are NEVER auto-deleted from activePairs.
  // They only disappear if the user explicitly unpairas (not yet implemented server-side)
  // or if the pairs.json is manually deleted.

  // Clean rate limit entries older than 2 minutes
  for (const [ip, entry] of rateLimits) {
    if (now - entry.windowStart > 120000) {
      rateLimits.delete(ip);
    }
  }
}, 60000);

// ─── Start ───────────────────────────────────────────────────────────
ensureDataDir();
loadPairs();

server.listen(PORT, () => {
  console.log(`[LockSync] WebSocket relay server running on port ${PORT}`);
  console.log(`[LockSync] Persistent pairs file: ${PAIRS_FILE}`);
  console.log(`[LockSync] Health check: http://localhost:${PORT}/health`);
});
