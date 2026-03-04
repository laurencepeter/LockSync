/// Application-wide constants.
class AppConstants {
  AppConstants._();

  // ── Networking ──────────────────────────────────────────────────
  /// Default WebSocket port for the P2P host server.
  static const int defaultWsPort = 8765;

  /// Maximum reconnect attempts before giving up.
  static const int maxReconnectAttempts = 10;

  /// Base delay (ms) for exponential reconnect backoff.
  static const int reconnectBaseDelayMs = 1000;

  /// Ping interval to detect silent disconnects.
  static const Duration pingInterval = Duration(seconds: 15);

  /// How long to wait for a pong before treating peer as disconnected.
  static const Duration pingTimeout = Duration(seconds: 5);

  // ── Storage box names ────────────────────────────────────────────
  static const String spacesBox = 'spaces_v1';
  static const String membersBox = 'members_v1';
  static const String layoutsBox = 'layouts_v1';
  static const String pendingEventsBox = 'pending_events_v1';
  static const String settingsBox = 'settings_v1';

  // ── Settings keys ────────────────────────────────────────────────
  static const String keyDeviceId = 'deviceId';
  static const String keyDeviceName = 'deviceName';
  static const String keyCurrentSpaceId = 'currentSpaceId';

  // ── P2P message types ────────────────────────────────────────────
  static const String msgSyncEvent = 'SYNC_EVENT';
  static const String msgLayoutSnapshot = 'LAYOUT_SNAPSHOT';
  static const String msgRequestSnapshot = 'REQUEST_SNAPSHOT';
  static const String msgMemberUpdate = 'MEMBER_UPDATE';
  static const String msgPing = 'PING';
  static const String msgPong = 'PONG';

  // ── Element types ────────────────────────────────────────────────
  static const String elementTextNote = 'text_note';
  static const String elementDrawingCanvas = 'drawing_canvas';
  static const String elementBackground = 'background';
  static const String elementMovableWidget = 'movable_widget';

  // ── Change types ─────────────────────────────────────────────────
  static const String changeAdd = 'add';
  static const String changeUpdate = 'update';
  static const String changeDelete = 'delete';
  static const String changeBackgroundChange = 'background_change';
  static const String changeReorder = 'reorder';

  // ── UI ───────────────────────────────────────────────────────────
  static const double defaultElementWidth = 160.0;
  static const double defaultElementHeight = 100.0;
  static const double minElementWidth = 80.0;
  static const double minElementHeight = 60.0;
  static const double handleSize = 12.0;
  static const double selectionBorderWidth = 2.0;
}
