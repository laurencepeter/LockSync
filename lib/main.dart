import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/canvas_renderer.dart';
import 'services/crash_logger.dart';
import 'services/storage_service.dart';
import 'services/websocket_service.dart';
import 'services/lock_screen_service.dart';
import 'services/wallpaper_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/sync_screen.dart';
import 'theme.dart';

void main() {
  // Install the crash logger BEFORE anything else so even errors that happen
  // during initialization are captured and surfaced in the app next launch.
  CrashLogger.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    CrashLogger.install();

    // Initialize lock screen background service + notification channels.
    // Wrapped in try-catch so a failure (e.g. foreground-service restrictions on
    // certain Android versions) doesn't crash the app on first launch.
    try {
      await LockScreenService.initialize();
    } catch (e, st) {
      debugPrint('[LockSync] Background service init failed: $e');
      await CrashLogger.record(
        source: 'init',
        error: e,
        stack: st,
        context: 'LockScreenService.initialize',
      );
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    final storage = StorageService();
    await storage.init();

    // Auto-enable lock screen display so the app shows over the lock screen
    // at all times — users shouldn't need to open the app first.
    WallpaperService.setShowOnLockScreen(true);

    // Query the device's actual screen dimensions so canvas renders match
    // the lock screen exactly instead of using hardcoded 1080x1920.
    _initDeviceDimensions();

    // Auto-enable wallpaper updates if not yet prompted (default on)
    if (!storage.autoWallpaperPrompted) {
      await storage.setAutoWallpaperPrompted(true);
      await storage.setAutoUpdateWallpaper(true);
    }

    // Request notification permission early so lock screen notifications work
    await LockScreenService.requestPermissions();

    // If there's saved canvas data, render and set it as the lock screen
    // wallpaper immediately on startup — this ensures the lock screen shows
    // the shared canvas even if the app wasn't recently in the foreground.
    if (storage.isPaired && storage.autoUpdateWallpaper) {
      _setInitialWallpaper(storage);
    }

    runApp(LockSyncApp(storage: storage));
  });
}

/// Query device screen dimensions and cache them in CanvasRenderer so
/// wallpaper renders match the actual lock screen resolution.
Future<void> _initDeviceDimensions() async {
  try {
    final dims = await WallpaperService.getScreenDimensions();
    if (dims != null) {
      CanvasRenderer.setDeviceDimensions(dims['width']!, dims['height']!);
    }
  } catch (e) {
    debugPrint('[LockSync] Failed to get screen dimensions: $e');
  }
}

/// Render the last-known canvas state and set it as the lock screen wallpaper.
/// Runs async and doesn't block startup — the wallpaper updates in the
/// background so the lock screen is always current even after a cold start.
Future<void> _setInitialWallpaper(StorageService storage) async {
  try {
    final json = storage.canvasState;
    if (json == null) return;
    final canvasData = jsonDecode(json) as Map<String, dynamic>;
    final bytes = await CanvasRenderer.renderToBytes(canvasData);
    if (bytes != null) {
      await WallpaperService.setWallpaperSilent(bytes);
    }
  } catch (e) {
    debugPrint('[LockSync] Initial wallpaper failed: $e');
  }
}

class LockSyncApp extends StatelessWidget {
  final StorageService storage;
  const LockSyncApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final ws = WebSocketService(storage: storage);
        // If already paired, pause the background service first so both
        // isolates don't try to authenticate at the same time — the server
        // drops one connection when it sees two for the same device, which
        // caused infinite reconnect loops and eventual crash on cold start.
        //
        // Every call is wrapped so a platform-channel error (e.g. the bg
        // service hasn't been configured yet on this cold start) cannot
        // bubble up into provider.create — which otherwise tears the whole
        // widget tree down before the first frame is painted.
        if (storage.isPaired) {
          try {
            LockScreenService.pause();
          } catch (e, st) {
            CrashLogger.record(
              source: 'startup',
              error: e,
              stack: st,
              context: 'LockScreenService.pause on cold start',
            );
          }
          // Delay the main connect to give the background service time to
          // release its WebSocket (mirrors the logic in _handleAppResumed).
          Future.delayed(const Duration(milliseconds: 500), () {
            try {
              ws.connect();
            } catch (e, st) {
              CrashLogger.record(
                source: 'startup',
                error: e,
                stack: st,
                context: 'ws.connect on cold start',
              );
            }
          });
        } else {
          try {
            ws.connect();
          } catch (e, st) {
            CrashLogger.record(
              source: 'startup',
              error: e,
              stack: st,
              context: 'ws.connect (unpaired)',
            );
          }
        }
        return ws;
      },
      child: MaterialApp(
        title: 'LockSync',
        debugShowCheckedModeBanner: false,
        theme: LockSyncTheme.darkTheme,
        home: _InitialRoute(storage: storage),
      ),
    );
  }
}

/// Decides the initial screen based on saved session state.
class _InitialRoute extends StatefulWidget {
  final StorageService storage;
  const _InitialRoute({required this.storage});

  @override
  State<_InitialRoute> createState() => _InitialRouteState();
}

class _InitialRouteState extends State<_InitialRoute> {
  @override
  void initState() {
    super.initState();
    // Schedule the background service start after the main WebSocket has had
    // time to connect. Starting both simultaneously caused the server to see
    // two connections for the same device and drop one, leading to an infinite
    // reconnect loop that eventually crashed the app.
    _autoStartBackgroundService();
  }

  Future<void> _autoStartBackgroundService() async {
    final s = widget.storage;
    if (!s.isPaired ||
        s.accessToken == null ||
        s.pairId == null ||
        s.partnerId == null) {
      return;
    }
    try {
      // Wait for the main WebSocket to finish its initial connect before
      // starting the background service (which opens its own connection).
      await Future.delayed(const Duration(seconds: 2));
      // Widget may have been unmounted during the 2s delay (e.g. user
      // unpaired).  Bail out if so — starting the service here would leave
      // a dangling foreground-service notification with stale credentials.
      if (!mounted) return;
      await LockScreenService.start(
        serverUrl: const String.fromEnvironment(
          'WS_URL',
          defaultValue: 'wss://locksync.fireydev.com',
        ),
        accessToken: s.accessToken!,
        refreshToken: s.refreshToken ?? '',
        deviceId: s.getDeviceId(),
        pairId: s.pairId!,
        partnerId: s.partnerId!,
      );
    } catch (e, st) {
      await CrashLogger.record(
        source: 'startup',
        error: e,
        stack: st,
        context: '_autoStartBackgroundService',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();

    // Already authenticated in this session → go straight to sync
    if (ws.status == ConnectionStatus.paired) {
      return const SyncScreen();
    }

    // Stored session exists (reconnecting after close / network drop).
    // Only show SyncScreen once the WebSocket is fully authenticated
    // (status == paired). Showing it earlier caused crashes because
    // SyncScreen subscribes to streams and accesses partner data that
    // hasn't been restored yet — if auth then fails (PAIR_NOT_FOUND,
    // INVALID_TOKEN), the session is cleared but SyncScreen is still
    // mounted and accessing stale/null state.
    if (widget.storage.isPaired) {
      if (ws.status != ConnectionStatus.paired) {
        return const _ReconnectingSplash();
      }
      return const SyncScreen();
    }

    return const WelcomeScreen();
  }
}

/// Minimal splash shown while the WebSocket reconnects on cold start.
/// Prevents SyncScreen from rendering before the service is ready.
/// Surfaces a subtle notice when a crash was recorded on the previous run
/// so the user knows to open Settings → Diagnostics for details.
class _ReconnectingSplash extends StatefulWidget {
  const _ReconnectingSplash();

  @override
  State<_ReconnectingSplash> createState() => _ReconnectingSplashState();
}

class _ReconnectingSplashState extends State<_ReconnectingSplash> {
  bool _hasCrashLog = false;

  @override
  void initState() {
    super.initState();
    _checkCrashLog();
  }

  Future<void> _checkCrashLog() async {
    final any = await CrashLogger.hasAny();
    if (!mounted) return;
    if (any) setState(() => _hasCrashLog = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 16),
            const Text('Reconnecting…',
                style: TextStyle(color: Colors.white70)),
            if (_hasCrashLog) ...[
              const SizedBox(height: 24),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'A crash was recorded last run. Open '
                  'Settings → Diagnostics to view the log.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
