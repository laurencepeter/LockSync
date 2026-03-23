// ─── App Configuration ───────────────────────────────────────────────────────
//
// Set LOCKSYNC_SERVER_URL at build time via --dart-define:
//   flutter build apk --dart-define=LOCKSYNC_SERVER_URL=wss://sync.yourdomain.com
//
// Or update the defaultValue below for development.
// ─────────────────────────────────────────────────────────────────────────────

class AppConfig {
  AppConfig._();

  /// WebSocket relay server URL.
  /// Override at build time: --dart-define=LOCKSYNC_SERVER_URL=wss://...
  static const String lockSyncServerUrl = String.fromEnvironment(
    'LOCKSYNC_SERVER_URL',
    defaultValue: 'wss://locksync.yourdomain.com',
  );
}
