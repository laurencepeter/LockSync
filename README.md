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

LockSync — Getting Started
LockSync lets two people share and sync their lock screens in real time — drawing, messages, photos, and more, instantly reflected on both devices.


# How to use?

1. Pair Your Devices
One person opens the app and taps Generate Code — a 6-digit code (and QR option) appears. The other person taps Enter Code and types it in (or scans the QR). That's it — you're paired.

Codes expire in 5 minutes. You only need to pair once; the app reconnects automatically after that.

2. Main Features
Tab	What it does
Chat	Send messages that appear on each other's lock screen
Canvas	Draw together in real time — becomes your shared wallpaper
Widgets	Add shared widgets (clocks, notes, countdowns) to the lock screen
Moments	A private shared photo gallery between the two of you
Travel Groups	Create or join a group trip with a shared itinerary and packing list
3. Travel Groups (optional)
Tap the Travel tab → Start or join a trip group → create with a name or join with an 8-digit code. Share the code with travel companions. Group codes expire in 5 minutes and support up to 30 days of synced membership.

4. Tips
Both devices need the app open at least once to establish the connection.
No account or sign-up required — pairing is anonymous.
To re-pair or switch partners, go to Settings and unpair.
