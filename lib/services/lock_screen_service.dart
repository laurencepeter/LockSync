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

import 'canvas_renderer.dart';
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
        autoStart: true,
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

// ─── Background isolate entry point ─────────────────────────────────
@pragma('vm:entry-point')
void _backgroundMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final notifs = FlutterLocalNotificationsPlugin();
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await notifs.initialize(initSettings);

  WebSocketChannel? channel;
  StreamSubscription? wsSub;
  Timer? pingTimer;
  Timer? reconnectTimer;
  bool active = false;
  int reconnectAttempts = 0;

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
  Future<void> showWidgetNotif(
      String widgetType, String partnerName) async {
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
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'LockSync',
        content: content,
      );
    }
  }

  // ── Connect WebSocket and start relaying ──
  Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('bg_server_url');
    final accessToken = prefs.getString('bg_access_token');
    final deviceId = prefs.getString('bg_device_id');

    if (serverUrl == null || accessToken == null || deviceId == null) return;

    try {
      channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      await channel!.ready;

      // Authenticate immediately
      channel!.sink.add(jsonEncode({
        'type': 'authenticate',
        'token': accessToken,
      }));

      // Reset backoff on successful connection
      reconnectAttempts = 0;

      wsSub = channel!.stream.listen(
        (raw) async {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
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
                final syncType =
                    payload['syncType'] as String? ?? 'text';

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
                  final prefs = await SharedPreferences.getInstance();
                  final partnerName =
                      prefs.getString('locksync_partner_name') ??
                          'Your partner';
                  await showNudgeNotif(partnerName);
                }

                // Widget change notifications
                if (syncType == 'grocery' ||
                    syncType == 'watchlist' ||
                    syncType == 'reminder' ||
                    syncType == 'countdown') {
                  final prefs = await SharedPreferences.getInstance();
                  final partnerName =
                      prefs.getString('locksync_partner_name') ??
                          'Your partner';
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
                    final prefs2 = await SharedPreferences.getInstance();
                    await prefs2.setString(storageKey, jsonEncode(items));
                  }
                }

                // Moment notification
                if (syncType == 'moment') {
                  final prefs = await SharedPreferences.getInstance();
                  final partnerName =
                      prefs.getString('locksync_partner_name') ??
                          'Your partner';
                  final mediaType =
                      payload['mediaType'] as String? ?? 'image';
                  final label =
                      mediaType == 'video' ? 'a video' : 'a photo';
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
                  final momentsRaw =
                      prefs.getString('locksync_moments');
                  final moments = momentsRaw != null
                      ? (jsonDecode(momentsRaw) as List)
                      : [];
                  moments.insert(
                      0,
                      Map<String, dynamic>.from(payload));
                  await prefs.setString(
                      'locksync_moments', jsonEncode(moments));
                }

                // Persist canvas JSON and render the wallpaper so the lock
                // screen stays up to date even while the app is sleeping.
                if (syncType == 'canvas') {
                  final canvasData = payload['canvasData'];
                  if (canvasData != null) {
                    final prefs = await SharedPreferences.getInstance();
                    // Default to true — matches StorageService.autoUpdateWallpaper
                    final autoUpdate = prefs.getBool(
                            'locksync_auto_update_wallpaper') ??
                        true;
                    if (autoUpdate) {
                      await prefs.setString(
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
                          await prefs.setBool(
                              'bg_wallpaper_pending', true);
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
  service.on(_kInvokeStart).listen((_) async {
    active = true;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    reconnectAttempts = 0;
    await wsSub?.cancel();
    await channel?.sink.close();
    channel = null;
    connect();
  });

  // ── Pause WS while the main app is in the foreground ──
  // Prevents dual-connection conflicts that cause the main isolate to
  // get kicked off the server when the user is editing the canvas.
  service.on(_kInvokePause).listen((_) async {
    reconnectTimer?.cancel();
    reconnectTimer = null;
    pingTimer?.cancel();
    await wsSub?.cancel();
    await channel?.sink.close();
    channel = null;
  });

  // ── Resume WS when the app goes back to the background ──
  service.on(_kInvokeResume).listen((_) async {
    if (active) {
      reconnectAttempts = 0;
      connect();
    }
  });

  // Auto-start on service launch
  active = true;
  connect();
}
