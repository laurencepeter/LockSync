# LockSync

LockSync is an app that allows users to have a coordinated synchronized lockscreen — when one person edits their lockscreen, the other person's updates in real time.

## Architecture

- **Flutter app** (`lib/`) — mobile/web client for both paired users
- **WebSocket relay server** (`server/`) — thin relay that pairs devices and forwards lockscreen sync messages in real time; no data is stored

## How It Works

1. One device generates a 6-digit pairing code
2. The other device enters the code to pair
3. Both devices receive JWTs to authenticate subsequent reconnections
4. Any lockscreen change on one device is instantly relayed to the paired device

## Server

The relay server is a Node.js WebSocket server. It handles pairing, JWT auth, and real-time message forwarding.

### Setup

```bash
cd server
cp .env.example .env
# Edit .env — set JWT_SECRET to a random 64-byte hex string
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
npm install
npm start
```

### Deploy with Docker

```bash
cd server
docker compose up -d
```

See `server/nginx-locksync.conf` for a production Nginx reverse proxy config.

## Flutter App

```bash
flutter pub get
flutter run
```
