import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/canvas_renderer.dart';
import 'services/storage_service.dart';
import 'services/websocket_service.dart';
import 'services/lock_screen_service.dart';
import 'services/wallpaper_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/sync_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize lock screen background service + notification channels.
  // Wrapped in try-catch so a failure (e.g. foreground-service restrictions on
  // certain Android versions) doesn't crash the app on first launch.
  try {
    await LockScreenService.initialize();
  } catch (e) {
    debugPrint('[LockSync] Background service init failed: $e');
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
        if (storage.isPaired) {
          LockScreenService.pause();
          // Delay the main connect to give the background service time to
          // release its WebSocket (mirrors the logic in _handleAppResumed).
          Future.delayed(const Duration(milliseconds: 500), () {
            ws.connect();
          });
        } else {
          ws.connect();
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
    if (s.isPaired &&
        s.accessToken != null &&
        s.pairId != null &&
        s.partnerId != null) {
      // Wait for the main WebSocket to finish its initial connect before
      // starting the background service (which opens its own connection).
      await Future.delayed(const Duration(seconds: 2));
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
class _ReconnectingSplash extends StatelessWidget {
  const _ReconnectingSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 16),
            Text('Reconnecting…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
