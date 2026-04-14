// ─── App Configuration ───────────────────────────────────────────────────────
//
// Set WS_URL at build time via --dart-define to point at a custom server:
//   flutter build apk --dart-define=WS_URL=wss://sync.yourdomain.com
//
// The health-check URL is derived automatically from wsUrl.
// ─────────────────────────────────────────────────────────────────────────────

class AppConfig {
  AppConfig._();

  /// WebSocket relay server URL.
  /// Override at build time: --dart-define=WS_URL=wss://...
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://locksync.fireydev.com',
  );

  /// HTTP health-check endpoint derived from [wsUrl].
  ///
  /// Example: wss://locksync.fireydev.com → https://locksync.fireydev.com/health
  ///
  /// The server exposes GET /health which returns 2xx when healthy.
  static String get healthUrl {
    final base = wsUrl
        .replaceFirst('wss://', 'https://')
        .replaceFirst('ws://', 'http://');
    return '$base/health';
  }
}
