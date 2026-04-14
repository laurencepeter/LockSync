import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures crashes and uncaught errors from every Dart entry point and
/// persists them to shared_preferences so the user can read them the next
/// time they open the app.
///
/// We hook three things:
///   * [FlutterError.onError]                — Flutter framework / widget errors
///   * [PlatformDispatcher.instance.onError] — uncaught async errors / isolate errors
///   * A [runZonedGuarded] zone around [runApp] — catches anything else
///
/// Each crash is stored as a JSON entry in a rolling buffer (max
/// [_maxEntries]).  [CrashLogger.readAll] / [CrashLogger.clear] are the
/// public APIs used by the settings screen.
class CrashLogger {
  CrashLogger._();

  static const String _key = 'locksync_crash_log_v1';
  static const int _maxEntries = 15;

  /// Called as early as possible from `main()`.
  ///
  /// Installs [FlutterError.onError] + [PlatformDispatcher.instance.onError]
  /// so that any uncaught error from Flutter or the Dart isolate is captured
  /// and written to persistent storage before the process potentially dies.
  static void install() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _recordSync(
        source: 'FlutterError',
        summary: details.exceptionAsString(),
        stack: details.stack?.toString(),
        library: details.library,
      );
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _recordSync(
        source: 'PlatformDispatcher',
        summary: error.toString(),
        stack: stack.toString(),
      );
      // Returning true tells Flutter the error has been handled so it doesn't
      // crash the isolate — but if something deeper (e.g. the Android runtime)
      // still kills the process, we've at least persisted the entry.
      return true;
    };
  }

  /// Convenience wrapper for the caller's `runApp`.  Use like:
  ///
  /// ```dart
  /// CrashLogger.runGuarded(() => runApp(MyApp()));
  /// ```
  static void runGuarded(void Function() body) {
    runZonedGuarded(body, (error, stack) {
      _recordSync(
        source: 'Zone',
        summary: error.toString(),
        stack: stack.toString(),
      );
    });
  }

  /// Manually record an error (useful inside try/catch blocks where we want
  /// to surface the problem in-app even though we swallowed the exception).
  static Future<void> record({
    required String source,
    required Object error,
    StackTrace? stack,
    String? context,
  }) async {
    final summary =
        context == null ? error.toString() : '$context: $error';
    await _recordAsync(
      source: source,
      summary: summary,
      stack: stack?.toString(),
    );
  }

  /// Fire-and-forget variant of [_recordAsync] — used from the synchronous
  /// Flutter / PlatformDispatcher error handlers where we can't await.
  static void _recordSync({
    required String source,
    required String summary,
    String? stack,
    String? library,
  }) {
    // Intentionally unawaited — the handlers are not async.
    unawaited(_recordAsync(
      source: source,
      summary: summary,
      stack: stack,
      library: library,
    ));
    // Mirror to debug output so logcat still gets the crash.
    debugPrint('[CrashLogger] $source: $summary');
    if (stack != null) debugPrint(stack);
  }

  static Future<void> _recordAsync({
    required String source,
    required String summary,
    String? stack,
    String? library,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_key) ?? <String>[];
      final entry = jsonEncode({
        'ts': DateTime.now().toIso8601String(),
        'source': source,
        'library': library,
        // Limit sizes so one giant stack trace doesn't evict everything
        // useful from the rolling log.
        'summary': _trim(summary, 400),
        'stack': stack == null ? null : _trim(stack, 4000),
      });
      final next = <String>[entry, ...existing];
      if (next.length > _maxEntries) {
        next.removeRange(_maxEntries, next.length);
      }
      await prefs.setStringList(_key, next);
    } catch (_) {
      // Never let the logger itself throw — that would cascade.
    }
  }

  /// Read all stored crashes, newest first.  Safe to call from UI code.
  static Future<List<CrashEntry>> readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const [];
      return raw
          .map((s) {
            try {
              return CrashEntry.fromJson(
                  jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<CrashEntry>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// True if any crash is recorded — used by the splash to show a banner.
  static Future<bool> hasAny() async {
    final all = await readAll();
    return all.isNotEmpty;
  }

  /// Wipe the rolling buffer.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  static String _trim(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}… [truncated]';
}

class CrashEntry {
  final DateTime timestamp;
  final String source;
  final String? library;
  final String summary;
  final String? stack;

  CrashEntry({
    required this.timestamp,
    required this.source,
    required this.summary,
    this.library,
    this.stack,
  });

  factory CrashEntry.fromJson(Map<String, dynamic> json) {
    return CrashEntry(
      timestamp: DateTime.tryParse(json['ts'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      source: json['source'] as String? ?? 'unknown',
      library: json['library'] as String?,
      summary: json['summary'] as String? ?? '',
      stack: json['stack'] as String?,
    );
  }
}
