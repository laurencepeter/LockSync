/**
 * LockSync WebSocket Relay Server
 *
 * Architecture: Thin relay — the server exists ONLY to:
 *   1. Generate & validate 6-digit pairing codes
 *   2. Issue long-lived JWTs after successful pairing (permanent pairing)
 *   3. Forward message deltas between paired devices in real-time
 *   4. Buffer last state per pair for reconnection sync
 *   5. Rate-limit nudge messages (max 1 per 10 seconds per device)
 *
 * Pairs are persisted to DATA_DIR/pairs.json so they survive server restarts.
 * No database needed — just a mounted Docker volume at /app/data.
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
const MAX_MESSAGE_SIZE = parseInt(process.env.MAX_MESSAGE_SIZE, 10) || 52428800; // 50 MB — supports base64 images/video
const NUDGE_COOLDOWN_MS = 10000; // 10 seconds between nudges
const DATA_DIR = process.env.DATA_DIR || '/app/data';
const PAIRS_FILE = path.join(DATA_DIR, 'pairs.json');

// ─── Pair persistence ────────────────────────────────────────────────
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
        displayNames: pair.displayNames || {},
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
        displayNames: entry.displayNames || {},
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
const pairingCodes = new Map();
const activePairs = new Map();
const deviceToPair = new Map();
const rateLimits = new Map();

/** Last state buffer per pair: pairId → { deviceId → { text, displayName, mood, canvas } } */
const lastStateBuffer = new Map();

/** Nudge rate limit per device: deviceId → lastNudgeTimestamp */
const nudgeLimits = new Map();

// ─── HTTP server ─────────────────────────────────────────────────────
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

  if (Date.now() - entry.createdAt > PAIR_CODE_TTL * 1000) {
    pairingCodes.delete(code);
    sendError(ws, 'CODE_EXPIRED', 'Pairing code has expired');
    return;
  }

  pairingCodes.delete(code);

  const pairId = uuidv4();
  const pair = {
    deviceA: { id: entry.deviceId, ws: entry.ws },
    deviceB: { id: deviceId, ws },
    createdAt: Date.now(),
    displayNames: {},
    _bothOfflineSince: null,
  };
  activePairs.set(pairId, pair);
  deviceToPair.set(entry.deviceId, pairId);
  deviceToPair.set(deviceId, pairId);

  ws._deviceId = deviceId;
  ws._pairId = pairId;
  entry.ws._pairId = pairId;

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
    sendError(ws, 'PAIR_NOT_FOUND', 'Pair session not found. Please re-pair.');
    return;
  }

  ws._deviceId = deviceId;
  ws._pairId = pairId;
  ws._authenticated = true;

  if (pair.deviceA.id === deviceId) {
    // Close any stale connection from this device (e.g. background service
    // that didn't disconnect cleanly before the main isolate reconnected).
    // Without this, the old socket stays open but stops receiving forwarded
    // messages, triggering infinite reconnect loops on the client.
    if (pair.deviceA.ws && pair.deviceA.ws !== ws && pair.deviceA.ws.readyState === 1) {
      console.log(`[AUTH] Closing stale connection for device ${deviceId.slice(0, 8)}…`);
      pair.deviceA.ws.close(4001, 'Replaced by new connection');
    }
    pair.deviceA.ws = ws;
  } else if (pair.deviceB.id === deviceId) {
    if (pair.deviceB.ws && pair.deviceB.ws !== ws && pair.deviceB.ws.readyState === 1) {
      console.log(`[AUTH] Closing stale connection for device ${deviceId.slice(0, 8)}…`);
      pair.deviceB.ws.close(4001, 'Replaced by new connection');
    }
    pair.deviceB.ws = ws;
  } else {
    sendError(ws, 'DEVICE_MISMATCH', 'Device not part of this pair');
    return;
  }

  deviceToPair.set(deviceId, pairId);

  const partnerId = pair.deviceA.id === deviceId ? pair.deviceB.id : pair.deviceA.id;

  // Get last buffered state from partner
  const pairBuffer = lastStateBuffer.get(pairId);
  const partnerState = pairBuffer ? pairBuffer[partnerId] : null;

  send(ws, {
    type: 'authenticated',
    pairId,
    partnerId,
    partnerOnline: getPartnerWs(pair, deviceId)?.readyState === 1,
    lastState: partnerState || null,
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

  const payload = msg.payload;
  if (!payload || typeof payload !== 'object') return;

  const syncType = payload.syncType;
  if (!syncType || typeof syncType !== 'string') return;

  // Validate syncType is a known type to prevent arbitrary data injection
  const validSyncTypes = ['text', 'canvas', 'display_name', 'mood', 'nudge',
    'reaction', 'grocery', 'watchlist', 'reminder', 'countdown', 'moment'];
  if (!validSyncTypes.includes(syncType)) {
    sendError(ws, 'INVALID_SYNC_TYPE', `Unknown sync type: ${syncType}`);
    return;
  }

  // Input sanitization — BEFORE buffering so sanitized values are stored
  if (payload.text && typeof payload.text === 'string') {
    payload.text = sanitizeText(payload.text);
  }
  if (payload.displayName && typeof payload.displayName === 'string') {
    payload.displayName = sanitizeText(payload.displayName).substring(0, 50);
  }
  if (payload.mood && typeof payload.mood === 'string') {
    // Moods should only be emoji — cap length to prevent abuse
    payload.mood = payload.mood.substring(0, 8);
  }

  // Nudge rate limiting (server-side enforcement)
  if (syncType === 'nudge') {
    const lastNudge = nudgeLimits.get(ws._deviceId);
    const now = Date.now();
    if (lastNudge && now - lastNudge < NUDGE_COOLDOWN_MS) {
      sendError(ws, 'NUDGE_RATE_LIMITED', 'Wait before sending another nudge');
      return;
    }
    nudgeLimits.set(ws._deviceId, now);
  }

  // Buffer state for reconnection sync (uses already-sanitized values)
  if (syncType === 'text' || syncType === 'display_name' || syncType === 'mood' || syncType === 'canvas') {
    if (!lastStateBuffer.has(ws._pairId)) {
      lastStateBuffer.set(ws._pairId, {});
    }
    const buffer = lastStateBuffer.get(ws._pairId);
    if (!buffer[ws._deviceId]) buffer[ws._deviceId] = {};

    if (syncType === 'text') {
      buffer[ws._deviceId].text = payload.text;
    } else if (syncType === 'display_name') {
      buffer[ws._deviceId].displayName = payload.displayName;
      // Also persist display name in the pair record
      if (pair.displayNames) {
        pair.displayNames[ws._deviceId] = payload.displayName;
        savePairs();
      }
    } else if (syncType === 'mood') {
      buffer[ws._deviceId].mood = payload.mood;
    } else if (syncType === 'canvas') {
      buffer[ws._deviceId].canvas = payload.canvasData;
    }
  }

  const partnerWs = getPartnerWs(pair, ws._deviceId);
  if (!partnerWs || partnerWs.readyState !== 1) {
    // Don't send partner_offline for display_name/mood syncs (they're stored in buffer)
    if (syncType !== 'display_name' && syncType !== 'mood') {
      send(ws, { type: 'partner_offline' });
    }
    return;
  }

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

  // Clear the ws reference so we don't hold stale socket objects in memory
  if (pair.deviceA.id === ws._deviceId && pair.deviceA.ws === ws) {
    pair.deviceA.ws = null;
  } else if (pair.deviceB.id === ws._deviceId && pair.deviceB.ws === ws) {
    pair.deviceB.ws = null;
  }

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

/** Strip HTML/script tags and dangerous characters from user-submitted text */
function sanitizeText(text) {
  return text
    .replace(/<[^>]*>/g, '')           // Strip HTML tags
    .replace(/javascript:/gi, '')       // Strip JS protocol
    .replace(/on\w+\s*=/gi, '')         // Strip event handlers
    .replace(/data:\s*text\/html/gi, '') // Strip data: HTML URIs
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, '') // Strip control chars
    .substring(0, 1000);
}

// ─── Periodic cleanup ────────────────────────────────────────────────
setInterval(() => {
  const now = Date.now();

  for (const [code, entry] of pairingCodes) {
    if (now - entry.createdAt > PAIR_CODE_TTL * 1000) {
      pairingCodes.delete(code);
    }
  }

  for (const [ip, entry] of rateLimits) {
    if (now - entry.windowStart > 120000) {
      rateLimits.delete(ip);
    }
  }

  // Clean old nudge rate limits (older than 1 minute)
  for (const [deviceId, ts] of nudgeLimits) {
    if (now - ts > 60000) {
      nudgeLimits.delete(deviceId);
    }
  }

  // Clean up lastStateBuffer entries for pairs that no longer exist
  for (const [pairId] of lastStateBuffer) {
    if (!activePairs.has(pairId)) {
      lastStateBuffer.delete(pairId);
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
