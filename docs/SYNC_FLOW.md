# LockSync — Synchronisation Flow

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Device A (Host)                         │
│                                                                 │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────┐  │
│  │  Editor UI   │◄──►│LayoutStateManager│◄──►│  SyncEngine  │  │
│  └──────────────┘    └──────────────────┘    └──────┬───────┘  │
│                               │                     │          │
│                        Hive Local DB          PeerConnection    │
│                                               Service (HOST)    │
│                                                     │ ws://     │
└─────────────────────────────────────────────────────┼───────────┘
                                                       │ WebSocket
┌─────────────────────────────────────────────────────┼───────────┐
│                         Device B (Client)            │           │
│                                                     │          │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────┴───────┐  │
│  │  Editor UI   │◄──►│LayoutStateManager│◄──►│  SyncEngine  │  │
│  └──────────────┘    └──────────────────┘    └──────────────┘  │
│                               │                                 │
│                        Hive Local DB                            │
└─────────────────────────────────────────────────────────────────┘
```

## Connection Establishment

```
Device A (Host)                        Device B (Client)
      │                                        │
      │  1. Create Space                       │
      │  2. Start WebSocket server             │
      │     ws://192.168.1.5:8765             │
      │  3. Encode QR:                         │
      │     { spaceId, host, port,            │
      │       hostDeviceId }                   │
      │                                        │
      │◄─── 4. B scans QR / enters code ──────│
      │                                        │
      │◄─── 5. WebSocket connect ─────────────│
      │                                        │
      │◄─── 6. MEMBER_UPDATE ─────────────────│
      │         { deviceId, deviceName }       │
      │                                        │
      │──── 7. REQUEST_SNAPSHOT ─────────────►│
      │         (B sends to host)              │
      │                                        │
      │◄─── 8. LAYOUT_SNAPSHOT ───────────────│
      │         { layout: LayoutState }        │
      │                                        │
      │     9. Both devices switch to          │
      │        delta-only sync                 │
```

## Real-Time Edit Sync (Delta Only)

```
Device A (editing)              Device B (receiving)
      │                                  │
      │  User moves element              │
      │                                  │
      │  LayoutStateManager              │
      │  .updateElement(el)              │
      │    → Apply locally               │
      │    → Persist to Hive             │
      │    → Emit SyncEvent              │
      │         via eventStream          │
      │                                  │
      │  SyncEngine                      │
      │  ._broadcastLocalEvent()         │
      │    → Queue to Hive               │
      │       (pending_events)           │
      │    → Send PeerMessage:           │
      │      { type: SYNC_EVENT,         │
      │        payload: SyncEvent }      │
      │                                  │
      │──── WebSocket ──────────────────►│
      │                                  │
      │                       SyncEngine │
      │               ._handleRemote()   │
      │                                  │
      │           Check originatingDevice│
      │           ≠ own deviceId ✓       │
      │                                  │
      │       LayoutStateManager         │
      │       .applyRemoteEvent()        │
      │         LWW: compare timestamps  │
      │         Apply if newer           │
      │         Persist to Hive          │
      │         notifyListeners()        │
      │                                  │
      │                       UI rebuilds│
      │                     with new pos │
```

## Conflict Resolution: Last-Write-Wins (LWW)

Every `HomeElement` carries an `updatedAt: DateTime` timestamp.

When a remote `SYNC_EVENT` of type `update` arrives:

```
incoming.timestamp > existing.updatedAt  →  Apply remote version
incoming.timestamp ≤ existing.updatedAt  →  Discard (local is newer)
```

Timestamps are set at mutation time on the originating device.
Clock skew between devices is acceptable for typical usage (≤1s).

## Sync Loop Prevention

Every `SyncEvent` carries `originatingDevice: String`.

On receipt of a `SYNC_EVENT`, the engine immediately checks:

```dart
if (event.originatingDevice == deviceId) return; // Skip own events
```

This prevents the echo-back of our own changes when the host rebroadcasts.

## Offline Queuing

When a peer is disconnected, locally-produced `SyncEvent`s are:
1. Queued in the `pending_events_v1` Hive box with `synced: false`.
2. When the connection is restored, `SyncEngine._flushPendingEvents()` sends
   them in chronological order.
3. Each event is marked `synced: true` after successful transmission.
4. `pruneOldEvents()` removes all synced events periodically.

## Late-Join Behaviour

When a new client connects mid-session:

```
New Client                              Host
     │                                   │
     │─── REQUEST_SNAPSHOT ─────────────►│
     │      { deviceId }                 │
     │                                   │
     │◄── LAYOUT_SNAPSHOT ───────────────│
     │      { layout, requestedBy }      │
     │                                   │
     │  applySnapshot(layout)            │
     │  (replaces entire local state)    │
     │                                   │
     │  Switch to delta sync             │
```

## Data Models

```
Space            (1)──has──(many) Member
Space            (1)──has──(1)    LayoutState
LayoutState      (1)──has──(many) HomeElement
SyncEngine       (N)──produces──  SyncEvent   → broadcast to peers
SyncEvent        ──applies to──   HomeElement (via changeType)
```

## Widget Tree Data Flow

```
LocalStorageService (Hive)
        │
        ▼
LayoutStateManager (ChangeNotifier)
        │ eventStream (SyncEvent)
        ▼
SyncEngine ──► PeerConnectionService ──► remote peers
        │
        ▼ (notifyListeners)
layoutProvider (StateProvider<LayoutState?>)
        │
        ▼
HomescreenEditor (ConsumerWidget)
  └── DraggableElement
        ├── TextNoteWidget
        ├── DrawingCanvasWidget
        └── (future widget types)
```

## Future Compatibility Notes

`LayoutState` and `HomeElement` are intentionally decoupled from Flutter UI.
The JSON schema is stable and can be consumed by:

- **Android widgets**: Read `LayoutState` JSON from shared storage, render
  elements using RemoteViews or Jetpack Compose Glance.
- **iOS widgets**: Decode `LayoutState` from App Group shared container,
  render using WidgetKit `Timeline`.
- **Lock screen**: Same JSON, different render target.

No changes to the data model or sync engine are required for these use cases.
