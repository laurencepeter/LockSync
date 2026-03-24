import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
const _kNotifIdService = 1;
const _kNotifIdMessage = 2;

// Keys for communicating between main isolate ↔ background isolate
const _kInvokeStart = 'locksync.start';
const _kInvokeStop = 'locksync.stop';
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
    await androidPlugin?.createNotificationChannel(serviceChannel);
    await androidPlugin?.createNotificationChannel(messageChannel);

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
  bool active = false;

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

                // Persist canvas JSON so we can use it if the main isolate
                // isn't running when this arrives.
                if (syncType == 'canvas') {
                  final canvasData = payload['canvasData'];
                  if (canvasData != null) {
                    final prefs = await SharedPreferences.getInstance();
                    final autoUpdate = prefs.getBool(
                            'locksync_auto_update_wallpaper') ??
                        false;
                    if (autoUpdate) {
                      await prefs.setString(
                        'bg_last_canvas_json',
                        jsonEncode(canvasData),
                      );
                    }
                  }
                }
              }
              break;

            case 'pong':
              break;
          }
        },
        onDone: () async {
          if (active) {
            await Future.delayed(const Duration(seconds: 5));
            connect();
          }
        },
        onError: (_) async {
          if (active) {
            await Future.delayed(const Duration(seconds: 5));
            connect();
          }
        },
      );

      pingTimer?.cancel();
      pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        channel?.sink.add(jsonEncode({'type': 'ping'}));
      });
    } catch (_) {
      if (active) {
        await Future.delayed(const Duration(seconds: 10));
        connect();
      }
    }
  }

  // ── Handle stop signal from main isolate ──
  service.on(_kInvokeStop).listen((_) async {
    active = false;
    pingTimer?.cancel();
    await wsSub?.cancel();
    await channel?.sink.close();
    await notifs.cancel(_kNotifIdMessage);
    service.stopSelf();
  });

  // ── Handle start / re-credential signal ──
  service.on(_kInvokeStart).listen((_) async {
    active = true;
    await wsSub?.cancel();
    await channel?.sink.close();
    connect();
  });

  // Auto-start on service launch
  active = true;
  connect();
}
