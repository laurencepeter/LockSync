import 'dart:async';
import '../core/constants/app_constants.dart';
import '../models/sync_event.dart';
import '../models/layout_state.dart';
import '../services/peer_connection_service.dart';
import '../services/layout_state_manager.dart';
import '../services/local_storage_service.dart';

/// Orchestrates bidirectional synchronisation between local layout state
/// and remote peers.
///
/// Responsibilities:
///   • Listens to [LayoutStateManager.eventStream] and broadcasts each
///     locally-produced [SyncEvent] to peers.
///   • Listens to [PeerConnectionService.messages] and routes each incoming
///     message to the appropriate handler.
///   • Handles late-join: sends a full [LayoutState] snapshot to newly
///     connected peers that request it.
///   • Prevents sync loops by filtering out self-originated events.
///   • Flushes the pending-event queue when a peer reconnects.
class SyncEngine {
  SyncEngine({
    required this.deviceId,
    required PeerConnectionService connectionService,
    required LayoutStateManager layoutManager,
    required LocalStorageService storageService,
  })  : _connection = connectionService,
        _layout = layoutManager,
        _storage = storageService;

  final String deviceId;
  final PeerConnectionService _connection;
  final LayoutStateManager _layout;
  final LocalStorageService _storage;

  StreamSubscription<PeerMessage>? _incomingSub;
  StreamSubscription<SyncEvent>? _outgoingSub;
  StreamSubscription<PeerConnectionStatus>? _statusSub;

  bool _initialized = false;

  // ── Initialization ────────────────────────────────────────────────

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Forward locally-produced events to peers.
    _outgoingSub = _layout.eventStream.listen(_broadcastLocalEvent);

    // Handle incoming peer messages.
    _incomingSub = _connection.messages.listen(_handleIncomingMessage);

    // Flush pending queue when we (re)connect.
    _statusSub = _connection.statusStream.listen((status) {
      if (status == PeerConnectionStatus.connected) {
        _flushPendingEvents();
      }
    });
  }

  // ── Outgoing ──────────────────────────────────────────────────────

  Future<void> _broadcastLocalEvent(SyncEvent event) async {
    // Queue persistently before broadcasting (survives disconnect).
    await _storage.queueEvent(event);

    if (!_connection.isConnected) return;

    _connection.sendMessage(PeerMessage(
      type: AppConstants.msgSyncEvent,
      payload: event.toJson(),
    ));

    await _storage.markEventSynced(event.eventId);
  }

  Future<void> _flushPendingEvents() async {
    final pending = await _storage.getPendingEvents();
    if (pending.isEmpty) return;

    print('[SyncEngine] Flushing ${pending.length} pending events');
    for (final event in pending) {
      _connection.sendMessage(PeerMessage(
        type: AppConstants.msgSyncEvent,
        payload: event.toJson(),
      ));
      await _storage.markEventSynced(event.eventId);
    }
    await _storage.pruneOldEvents();
  }

  // ── Incoming ──────────────────────────────────────────────────────

  void _handleIncomingMessage(PeerMessage message) {
    switch (message.type) {
      case AppConstants.msgSyncEvent:
        _handleRemoteSyncEvent(message.payload);

      case AppConstants.msgLayoutSnapshot:
        _handleLayoutSnapshot(message.payload);

      case AppConstants.msgRequestSnapshot:
        _handleSnapshotRequest(message.payload);

      case AppConstants.msgMemberUpdate:
        // Handled by the provider layer; nothing to do here.
        break;

      default:
        break;
    }
  }

  void _handleRemoteSyncEvent(Map<String, dynamic> payload) {
    final event = SyncEvent.fromJson(payload);

    // Ignore events we originated (prevents sync loops).
    if (event.originatingDevice == deviceId) return;

    _layout.applyRemoteEvent(event);
  }

  void _handleLayoutSnapshot(Map<String, dynamic> payload) {
    // The snapshot may be targeted at a specific device (late-join).
    final targetDevice = payload['requestedBy'] as String?;
    if (targetDevice != null && targetDevice != deviceId) return;

    final snapshotMap = payload['layout'] as Map<String, dynamic>?;
    if (snapshotMap == null) return;

    final snapshot = LayoutState.fromJson(snapshotMap);
    _layout.applySnapshot(snapshot);
  }

  void _handleSnapshotRequest(Map<String, dynamic> payload) {
    // Only the host responds to snapshot requests.
    if (_connection.role != ConnectionRole.host) return;

    final requestingDevice = payload['deviceId'] as String? ?? '';
    final snapshot = _layout.layout;

    _connection.sendMessage(PeerMessage(
      type: AppConstants.msgLayoutSnapshot,
      payload: {
        'layout': snapshot.toJson(),
        'requestedBy': requestingDevice,
      },
    ));
    print('[SyncEngine] Sent layout snapshot to $requestingDevice');
  }

  // ── Public API ────────────────────────────────────────────────────

  /// Called by a newly-joined client to request the current layout snapshot.
  void requestSnapshot() {
    _connection.sendMessage(PeerMessage(
      type: AppConstants.msgRequestSnapshot,
      payload: {'deviceId': deviceId},
    ));
  }

  // ── Teardown ──────────────────────────────────────────────────────

  void dispose() {
    _incomingSub?.cancel();
    _outgoingSub?.cancel();
    _statusSub?.cancel();
  }
}
