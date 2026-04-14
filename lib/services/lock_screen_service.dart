import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import 'canvas_renderer.dart';
import 'server_health.dart';
import 'wallpaper_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// LockScreen Background Service
//
// Runs as a foreground service (Android) / background task (iOS) so the
// WebSocket stays alive when the phone is locked.
//
// When the partner sends a message the notification on the lock screen updates
// in real-time — visible even before unlocking the phone.
//
// Android:  foreground service with a persistent "LockSync active" notification
//           + a separate high-priority notification for incoming messages that
//           shows on the lock screen with full content (visibility: public).
// iOS:      background mode keeps the isolate alive for as long as iOS allows;
//           shows a local notification when a message arrives.
// ──────────────────────────────────────────────────────────────────────────────

const _kNotifChannelService = 'locksync_service';
const _kNotifChannelMessages = 'locksync_messages';
const _kNotifChannelNudge = 'locksync_nudge';
const _kNotifIdService = 1;
const _kNotifIdMessage = 2;
const _kNotifIdNudge = 3;
const _kNotifIdWidget = 4;

// Keys for communicating between main isolate ↔ background isolate
const _kInvokeStart = 'locksync.start';
const _kInvokeStop = 'locksync.stop';
const _kInvokePause = 'locksync.pause';
const _kInvokeResume = 'locksync.resume';
const _kEventMessage = 'locksync.message';
const _kEventStatus = 'locksync.status';

// ─── Public API (called from main isolate) ───────────────────────────

class LockScreenService {
  LockScreenService._();

  static final FlutterLocalNotificationsPlugin _notifs =
      FlutterLocalNotificationsPlugin();

  /// Call once in main() before runApp().
  static Future<void> initialize() async {
    // Notification channels
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _notifs.initialize(initSettings);

    // Android: create channels
    const serviceChannel = AndroidNotificationChannel(
      _kNotifChannelService,
      'LockSync Active',
      description: 'Keeps your LockSync connection alive',
      importance: Importance.low,
      showBadge: false,
    );
    const messageChannel = AndroidNotificationChannel(
      _kNotifChannelMessages,
      'LockSync Messages',
      description: 'Partner messages shown on lock screen',
      importance: Importance.high,
      showBadge: true,
    );
    final androidPlugin =
        _notifs.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    const nudgeChannel = AndroidNotificationChannel(
      _kNotifChannelNudge,
      'LockSync Nudges',
      description: 'Nudge alerts from your partner',
      importance: Importance.max,
      showBadge: true,
      playSound: false,
    );
    await androidPlugin?.createNotificationChannel(serviceChannel);
    await androidPlugin?.createNotificationChannel(messageChannel);
    await androidPlugin?.createNotificationChannel(nudgeChannel);

    // Configure background service
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _backgroundMain,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _kNotifChannelService,
        initialNotificationTitle: 'LockSync',
        initialNotificationContent: 'Paired — waiting for messages',
        foregroundServiceNotificationId: _kNotifIdService,
        // Allow the service to keep running even if the app process is killed
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _backgroundMain,
        onBackground: _iosBackground,
      ),
    );
  }

  /// Start the background service for a given pair session.
  /// Call this right after the device enters the `paired` state.
  static Future<void> start({
    required String serverUrl,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
    required String pairId,
    required String partnerId,
  }) async {
    // Persist the session so the background isolate can read it from prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_server_url', serverUrl);
    await prefs.setString('bg_access_token', accessToken);
    await prefs.setString('bg_refresh_token', refreshToken);
    await prefs.setString('bg_device_id', deviceId);
    await prefs.setString('bg_pair_id', pairId);
    await prefs.setString('bg_partner_id', partnerId);

    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    }
    service.invoke(_kInvokeStart);
  }

  /// Stop the background service (e.g. when the user unpairas).
  static Future<void> stop() async {
    FlutterBackgroundService().invoke(_kInvokeStop);
  }

  /// Pause the background service's WebSocket connection.
  /// Call when the app comes to the foreground so the main isolate's
  /// WebSocket is the only active connection for this device.
  static void pause() {
    FlutterBackgroundService().invoke(_kInvokePause);
  }

  /// Resume the background service's WebSocket connection.
  /// Call when the app goes to the background so messages are still
  /// received and the lock screen notification stays up to date.
  static void resume() {
    FlutterBackgroundService().invoke(_kInvokeResume);
  }

  /// Listen for incoming sync messages forwarded by the background isolate.
  static Stream<Map<String, dynamic>> get onMessage {
    return FlutterBackgroundService().on(_kEventMessage).map(
          (data) => Map<String, dynamic>.from(data ?? {}),
        );
  }

  /// Listen for status updates from the background isolate.
  static Stream<Map<String, dynamic>> get onStatus {
    return FlutterBackgroundService().on(_kEventStatus).map(
          (data) => Map<String, dynamic>.from(data ?? {}),
        );
  }

  /// Show a nudge notification from the main (foreground) isolate.
  /// Called by WebSocketService when a nudge arrives while the app is open
  /// and the background-service WebSocket is paused.
  static Future<void> showForegroundNudge(String partnerName) async {
    await _notifs.show(
      _kNotifIdNudge,
      '$partnerName nudged you! 📳',
      'Tap to open LockSync',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kNotifChannelNudge,
          'LockSync Nudges',
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.public,
          fullScreenIntent: true,
          autoCancel: true,
          ongoing: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Request permission to post notifications (Android 13+ / iOS).
  static Future<void> requestPermissions() async {
    await _notifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _notifs
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: false);
  }
}

// ─── iOS background handler (keep-alive callback) ────────────────────
@pragma('vm:entry-point')
Future<bool> _iosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ─── Background isolate state ─────────────────────────────────────────────
//
// Encapsulates all mutable state and helpers for the background isolate so
// that [connect] and [scheduleReconnect] can refer to each other freely as
// ordinary instance methods — no forward-reference tricks required.
class _BgServiceRunner {
  final ServiceInstance service;
  final FlutterLocalNotificationsPlugin notifs;

  WebSocketChannel? channel;
  StreamSubscription? wsSub;
  Timer? pingTimer;
  Timer? reconnectTimer;
  bool active = false;
  int reconnectAttempts = 0;

  _BgServiceRunner(this.service, this.notifs);

  // ── Helper: show / update the lock screen message notification ──
  Future<void> showMessageNotif(String text) async {
    await notifs.show(
      _kNotifIdMessage,
      'Message from your partner',
      text,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _kNotifChannelMessages,
          'LockSync Messages',
          importance: Importance.high,
          priority: Priority.high,
          // PUBLIC = show full content on lock screen without unlocking
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(text),
          // Wake the screen and display the app over the lock screen
          fullScreenIntent: true,
          ongoing: false,
          autoCancel: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      ),
    );
  }

  // ── Helper: nudge notification ──
  Future<void> showNudgeNotif(String partnerName) async {
    await notifs.show(
      _kNotifIdNudge,
      '$partnerName nudged you! 📳',
      'Tap to open LockSync',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kNotifChannelNudge,
          'LockSync Nudges',
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.public,
          // Wake the screen and show the app over the lock screen
          fullScreenIntent: true,
          autoCancel: true,
          ongoing: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ── Helper: widget update notification ──
  Future<void> showWidgetNotif(String widgetType, String partnerName) async {
    const labels = <String, String>{
      'grocery': 'updated the grocery list',
      'watchlist': 'updated the watchlist',
      'reminder': 'added a reminder for you',
      'countdown': 'updated a countdown',
    };
    final action = labels[widgetType] ?? 'updated a widget';
    final title = '$partnerName $action';
    final body =
        'Check the ${widgetType[0].toUpperCase()}${widgetType.substring(1)} widget';
    await notifs.show(
      _kNotifIdWidget,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kNotifChannelMessages,
          'LockSync Messages',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
          autoCancel: true,
          ongoing: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      ),
    );
  }

  // ── Helper: update the foreground service notification (Android) ──
  void updateServiceNotif(String content) {
    final svc = service;
    if (svc is AndroidServiceInstance) {
      svc.setForegroundNotificationInfo(
        title: 'LockSync',
        content: content,
      );
    }
  }

  // ── Reconnect with exponential backoff (1s, 2s, 4s, 8s, 16s, 30s cap) ──
  void scheduleReconnect() {
    reconnectTimer?.cancel();
    final delaySec = (1 << reconnectAttempts).clamp(1, 30);
    if (reconnectAttempts < 5) reconnectAttempts++;
    reconnectTimer = Timer(Duration(seconds: delaySec), () {
      reconnectTimer = null;
      if (active) connect();
    });
  }

  // ── Connect WebSocket and start relaying ──
  Future<void> connect() async {
    // Refuse to connect if the service has been paused (main app is in
    // foreground) — calling this from a stale reconnect timer would create
    // the dual-WS race the pause handler is trying to prevent.
    if (!active) return;

    // Tear down any lingering channel/subscription before opening a new one
    // so we never end up holding two WebSockets at once.
    try {
      await wsSub?.cancel();
    } catch (_) {}
    wsSub = null;
    try {
      await channel?.sink.close();
    } catch (_) {}
    channel = null;
    pingTimer?.cancel();
    pingTimer = null;

    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('bg_server_url');
    final accessToken = prefs.getString('bg_access_token');
    final deviceId = prefs.getString('bg_device_id');

    if (serverUrl == null || accessToken == null || deviceId == null) return;

    // ── Health check before opening the WebSocket ─────────────────────────
    // Avoids burning reconnect attempts when the server is known-down.
    // Uses AppConfig.healthUrl (derived from the compiled-in WS URL) which
    // is consistent with the stored serverUrl for the default server.
    final serverUp = await ServerHealth.check();
    if (!active) return; // pause may have fired during the health check
    if (!serverUp) {
      debugPrint('[BG] Health check failed — server unreachable, deferring reconnect');
      scheduleReconnect(); // try again after the normal backoff
      return;
    }

    try {
      channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      await channel!.ready;
      // If pause fired while we were awaiting `ready`, abort — we should not
      // start listening or pinging because the main isolate is now the
      // authoritative connection.
      if (!active) {
        try {
          await channel?.sink.close();
        } catch (_) {}
        channel = null;
        return;
      }

      // Authenticate immediately
      channel!.sink.add(jsonEncode({
        'type': 'authenticate',
        'token': accessToken,
      }));

      // Reset backoff on successful connection
      reconnectAttempts = 0;

      wsSub = channel!.stream.listen(
        (raw) async {
          final Map<String, dynamic> msg;
          try {
            msg = jsonDecode(raw as String) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('[BG] Malformed WebSocket message, skipping: $e');
            return;
          }
          final type = msg['type'] as String?;

          switch (type) {
            case 'authenticated':
              updateServiceNotif('Paired — watching for messages');
              service.invoke(_kEventStatus, {'status': 'paired'});
              break;

            case 'partner_online':
              updateServiceNotif('Partner online');
              service.invoke(_kEventStatus, {'status': 'partner_online'});
              break;

            case 'partner_offline':
              updateServiceNotif('Partner offline');
              service.invoke(_kEventStatus, {'status': 'partner_offline'});
              break;

            case 'sync':
              final payload = msg['payload'];
              if (payload is Map) {
                final syncType = payload['syncType'] as String? ?? 'text';

                // Always relay to the main isolate so it can update the
                // wallpaper even while the phone is locked.
                service.invoke(_kEventMessage, {
                  'from': msg['from'],
                  'payload': Map<String, dynamic>.from(
                      payload as Map<Object?, Object?>),
                  'ts': msg['ts'],
                });

                // Show a text notification for text / canvas-with-text updates
                if (syncType == 'text' || syncType == 'canvas') {
                  final text = payload['text'] as String? ??
                      payload['delta'] as String? ??
                      '';
                  if (text.isNotEmpty) {
                    await showMessageNotif(text);
                  }
                }

                // Nudge notification
                if (syncType == 'nudge') {
                  final p = await SharedPreferences.getInstance();
                  final partnerName =
                      p.getString('locksync_partner_name') ?? 'Your partner';
                  await showNudgeNotif(partnerName);
                }

                // Widget change notifications
                if (syncType == 'grocery' ||
                    syncType == 'watchlist' ||
                    syncType == 'reminder' ||
                    syncType == 'countdown') {
                  final p = await SharedPreferences.getInstance();
                  final partnerName =
                      p.getString('locksync_partner_name') ?? 'Your partner';
                  await showWidgetNotif(syncType, partnerName);
                  // Also persist widget data so next open shows latest
                  const widgetKeys = <String, String>{
                    'grocery': 'locksync_grocery_list',
                    'watchlist': 'locksync_watchlist',
                    'reminder': 'locksync_reminders',
                    'countdown': 'locksync_countdowns',
                  };
                  final items = payload['items'];
                  final storageKey = widgetKeys[syncType];
                  if (items != null && storageKey != null) {
                    final p2 = await SharedPreferences.getInstance();
                    await p2.setString(storageKey, jsonEncode(items));
                  }
                }

                // Moment notification
                if (syncType == 'moment') {
                  final p = await SharedPreferences.getInstance();
                  final partnerName =
                      p.getString('locksync_partner_name') ?? 'Your partner';
                  final mediaType =
                      payload['mediaType'] as String? ?? 'image';
                  final label = mediaType == 'video' ? 'a video' : 'a photo';
                  await notifs.show(
                    _kNotifIdWidget,
                    '$partnerName sent you $label',
                    'Open LockSync to view this moment',
                    const NotificationDetails(
                      android: AndroidNotificationDetails(
                        _kNotifChannelMessages,
                        'LockSync Messages',
                        importance: Importance.high,
                        priority: Priority.high,
                        visibility: NotificationVisibility.public,
                        autoCancel: true,
                        ongoing: false,
                      ),
                      iOS: DarwinNotificationDetails(
                        presentAlert: true,
                        presentSound: true,
                      ),
                    ),
                  );
                  // Persist the moment
                  final momentsRaw = p.getString('locksync_moments');
                  final moments = momentsRaw != null
                      ? (jsonDecode(momentsRaw) as List)
                      : [];
                  moments.insert(0, Map<String, dynamic>.from(payload));
                  await p.setString('locksync_moments', jsonEncode(moments));
                }

                // Persist canvas JSON and render the wallpaper so the lock
                // screen stays up to date even while the app is sleeping.
                if (syncType == 'canvas') {
                  final canvasData = payload['canvasData'];
                  if (canvasData != null) {
                    final p = await SharedPreferences.getInstance();
                    // Default to true — matches StorageService.autoUpdateWallpaper
                    final autoUpdate =
                        p.getBool('locksync_auto_update_wallpaper') ?? true;
                    if (autoUpdate) {
                      await p.setString(
                        'bg_last_canvas_json',
                        jsonEncode(canvasData),
                      );
                      // Render the canvas to PNG and set it as the lock
                      // screen wallpaper immediately from the background engine.
                      // WallpaperPlugin is registered in the background engine
                      // via LockSyncBackgroundService.configureFlutterEngine()
                      // so the MethodChannel call succeeds even while the
                      // phone is locked — no app open needed.
                      try {
                        // Init device dimensions on first render so the
                        // canvas fills the entire lock screen.
                        if (CanvasRenderer.deviceWidth == null) {
                          final dims =
                              await WallpaperService.getScreenDimensions();
                          if (dims != null) {
                            CanvasRenderer.setDeviceDimensions(
                                dims['width']!, dims['height']!);
                          }
                        }
                        final bytes = await CanvasRenderer.renderToBytes(
                          Map<String, dynamic>.from(
                              canvasData as Map<Object?, Object?>),
                        );
                        if (bytes != null) {
                          // Apply directly — this updates the lock screen now.
                          await WallpaperService.setWallpaperSilent(bytes);

                          // Also persist as a fallback for first cold-boot
                          // before WallpaperPlugin has been registered.
                          final dir = await getTemporaryDirectory();
                          final file =
                              File('${dir.path}/locksync_bg_wallpaper.png');
                          await file.writeAsBytes(bytes);
                          await p.setBool('bg_wallpaper_pending', true);
                        }
                      } catch (e) {
                        // Log but don't crash the background service
                        debugPrint('[BG] Wallpaper render failed: $e');
                      }
                    }
                  }
                }
              }
              break;

            case 'pong':
              break;
          }
        },
        onDone: () {
          if (active) scheduleReconnect();
        },
        onError: (_) {
          if (active) scheduleReconnect();
        },
      );

      pingTimer?.cancel();
      pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        channel?.sink.add(jsonEncode({'type': 'ping'}));
      });
    } catch (_) {
      if (active) scheduleReconnect();
    }
  }

  // ── Wire up service event listeners and kick off the initial connection ──
  void run() {
    // ── Handle stop signal from main isolate ──
    service.on(_kInvokeStop).listen((_) async {
      active = false;
      reconnectTimer?.cancel();
      reconnectTimer = null;
      pingTimer?.cancel();
      await wsSub?.cancel();
      await channel?.sink.close();
      channel = null;
      await notifs.cancel(_kNotifIdMessage);
      service.stopSelf();
    });

    // ── Handle start / re-credential signal ──
    // Only mark the service as active and tear down any stale connection.
    // Do NOT call connect() here — the app is still in the foreground when
    // this fires (called from _autoStartBackgroundService 2 s after launch).
    // The actual connection is deferred until the app backgrounds and
    // _kInvokeResume fires, preventing the dual-connection race that caused
    // the server to drop the main isolate's WebSocket on cold start.
    service.on(_kInvokeStart).listen((_) async {
      active = true;
      reconnectTimer?.cancel();
      reconnectTimer = null;
      reconnectAttempts = 0;
      await wsSub?.cancel();
      await channel?.sink.close();
      channel = null;
      // Connection will be established by _kInvokeResume when app backgrounds.
    });

    // ── Pause WS while the main app is in the foreground ──
    // Prevents dual-connection conflicts that cause the main isolate to
    // get kicked off the server when the user is editing the canvas.
    //
    // CRITICAL: We flip `active` to false here so that if the underlying
    // WebSocket is torn down racily (onDone/onError firing *before* the
    // cancel below has been awaited), the stray `scheduleReconnect` call
    // won't re-open a second connection behind the main isolate's back.
    // `_kInvokeResume` sets active=true again when the app backgrounds.
    service.on(_kInvokePause).listen((_) async {
      active = false;
      reconnectTimer?.cancel();
      reconnectTimer = null;
      pingTimer?.cancel();
      try {
        await wsSub?.cancel();
      } catch (_) {}
      wsSub = null;
      try {
        await channel?.sink.close();
      } catch (_) {}
      channel = null;
    });

    // ── Resume WS when the app goes back to the background ──
    service.on(_kInvokeResume).listen((_) async {
      active = true;
      reconnectAttempts = 0;
      connect();
    });

    // Do NOT auto-connect here. The service starts while the app is still in
    // the foreground; connecting immediately would create a dual-WebSocket
    // race with the main isolate's connection. The _kInvokeResume event
    // (fired by WebSocketService._handleAppBackgrounded) triggers the actual
    // connection once the app moves to the background.
    active = false; // will be set true by _kInvokeStart

    // ── Keep-alive heartbeat ─────────────────────────────────────────────────
    // Fires every 5 s to prevent aggressive battery managers (Huawei, Xiaomi,
    // Samsung "Sleeping apps") from marking the isolate as idle and killing it.
    // The timer itself has no network cost — it just keeps the Dart event loop
    // spinning so the OS sees the process as active.
    Timer.periodic(const Duration(seconds: 5), (_) {
      // If the service has been stopped, the isolate is about to be torn down
      // anyway, so we can safely no-op here.
      if (service is AndroidServiceInstance) {
        // Keeping the event loop warm is all we need — no log spam in release.
        assert(() {
          debugPrint('[BG] Service alive…');
          return true;
        }());
      }
    });
  }
}

// ─── Background isolate entry point ─────────────────────────────────
@pragma('vm:entry-point')
Future<void> _backgroundMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final notifs = FlutterLocalNotificationsPlugin();
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await notifs.initialize(initSettings);

  _BgServiceRunner(service, notifs).run();
}
