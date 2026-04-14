import 'dart:io';

import '../config/app_config.dart';

/// Lightweight helper that pings [AppConfig.healthUrl] and reports whether
/// the LockSync relay server is reachable.
///
/// Used by:
///  • [WebSocketService] — smarter reconnect backoff (30 s when server is down)
///  • [_BgServiceRunner]  — skip wasted connect attempts in background isolate
///  • [DiagnosticsScreen] — live "Server" status card
class ServerHealth {
  ServerHealth._();

  /// Performs an HTTP GET to [AppConfig.healthUrl] and returns `true` when
  /// the server responds with a 2xx status within [timeout].
  ///
  /// Uses [dart:io] [HttpClient] — no extra package required.
  static Future<bool> check({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = timeout
        ..idleTimeout = timeout;
      final request = await client
          .getUrl(Uri.parse(AppConfig.healthUrl))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      // Drain the body so the connection is released cleanly
      await response.drain<void>();
      client.close(force: false);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
