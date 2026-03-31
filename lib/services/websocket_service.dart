import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'canvas_renderer.dart';
import 'lock_screen_service.dart';
import 'storage_service.dart';
import 'wallpaper_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, paired }

class WebSocketService extends ChangeNotifier with WidgetsBindingObserver {
  final StorageService storage;

  static const String _wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://locksync.fireydev.com',
  );

  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _pairingCode;
  String? _pairId;
  String? _partnerId;
  bool _partnerOnline = false;
  String _partnerText = '';
  String? _errorMessage;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;

  // Display name
  String? _partnerDisplayName;
  String? _partnerMood;

  // Nudge rate limiting (client-side)
  DateTime? _lastNudgeSent;

  // Canvas data from partner
  Map<String, dynamic>? _partnerCanvasData;

  // Auto-wallpaper update
  Timer? _wallpaperDebounce;
  StreamSubscription? _bgServiceSub;

  // Foreground tracking — used to skip expensive canvas renders while the
  // app is in background (the background-service isolate handles those).
  bool _isInForeground = true;

  // Fired when the app should show the one-time auto-wallpaper permission dialog
  final _wallpaperPromptController = StreamController<void>.broadcast();
  Stream<void> get onWallpaperPromptNeeded => _wallpaperPromptController.stream;

  // Canvas sync stream — fired whenever partner canvas data arrives
  final _canvasSyncController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onCanvasSync =>
      _canvasSyncController.stream;

  // Reactions stream
  final _reactionController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onReaction => _reactionController.stream;

  // Nudge stream
  final _nudgeController = StreamController<void>.broadcast();
  Stream<void> get onNudge => _nudgeController.stream;

  ConnectionStatus get status => _status;
  String? get pairingCode => _pairingCode;
  String? get pairId => _pairId;
  String? get partnerId => _partnerId;
  bool get partnerOnline => _partnerOnline;
  String get partnerText => _partnerText;
  String? get errorMessage => _errorMessage;
  String? get partnerDisplayName => _partnerDisplayName;
  String? get partnerMood => _partnerMood;
  bool get isReconnecting => _isReconnecting;
  Map<String, dynamic>? get partnerCanvasData => _partnerCanvasData;

  WebSocketService({required this.storage}) {
    WidgetsBinding.instance.addObserver(this);
    _listenToBackgroundService();
  }

  /// Relay sync events that arrive via the background service isolate
  /// (i.e. when the phone is locked and the main WebSocket is inactive).
  void _listenToBackgroundService() {
    _bgServiceSub = LockScreenService.onMessage.listen((msg) {
      final payload = msg['payload'] as Map<String, dynamic>?;
      if (payload == null) return;
      final syncType = payload['syncType'] as String?;

      switch (syncType) {
        case 'canvas':
          final canvasData = payload['canvasData'] as Map<String, dynamic>?;
          if (canvasData != null) {
            _partnerCanvasData = canvasData;
            _partnerText = (payload['text'] as String?) ?? _partnerText;
            storage.setCanvasState(jsonEncode(canvasData));
            _canvasSyncController.add(canvasData);
            notifyListeners();
            _maybeAutoUpdateWallpaper(canvasData);
          }
          break;
        case 'grocery':
          final gi = payload['items'];
          if (gi is List) {
            storage.setGroceryList(List<Map<String, dynamic>>.from(gi));
          }
          _widgetSyncController.add(payload);
          notifyListeners();
          break;
        case 'watchlist':
          final wi = payload['items'];
          if (wi is List) {
            storage.setWatchlist(List<Map<String, dynamic>>.from(wi));
          }
          _widgetSyncController.add(payload);
          notifyListeners();
          break;
        case 'reminder':
          final ri = payload['items'];
          if (ri is List) {
            storage.setReminders(List<Map<String, dynamic>>.from(ri));
          }
          _widgetSyncController.add(payload);
          notifyListeners();
          break;
        case 'countdown':
          final ci = payload['items'];
          if (ci is List) {
            storage.setCountdowns(List<Map<String, dynamic>>.from(ci));
          }
          _widgetSyncController.add(payload);
          notifyListeners();
          break;
        case 'moment':
          // Received a moment from partner — persist and forward to UI.
          final momentData = Map<String, dynamic>.from(payload);
          final existing = storage.getMoments();
          existing.insert(0, momentData);
          storage.setMoments(existing);
          _widgetSyncController.add(payload);
          notifyListeners();
          break;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      _isInForeground = false;
      _handleAppBackgrounded();
    }
  }

  void _handleAppResumed() {
    _isInForeground = true;
    // Ensure the app continues to display over the lock screen
    WallpaperService.setShowOnLockScreen(true);
    // Pause the background service's WebSocket first so the server only sees
    // one active connection per device. Without this, the server closes the
    // main isolate's connection when both try to authenticate simultaneously,
    // which is what causes the "boot out" during canvas editing.
    if (storage.isPaired) {
      LockScreenService.pause();
    }

    // Apply any wallpaper that the background service rendered while the
    // phone was sleeping — this is what makes the lock screen update when
    // the user glances at their phone.
    _applyPendingWallpaper();

    // Delay the main connect slightly to give the background service time to
    // actually close its WebSocket. This prevents the dual-connection race
    // where both try to authenticate at the same time and the server drops one.
    if (_status == ConnectionStatus.disconnected ||
        (_channel == null && storage.isPaired)) {
      _isReconnecting = true;
      notifyListeners();
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(milliseconds: 500), () {
        _reconnectTimer = null;
        connect();
      });
      // _isReconnecting is cleared in the 'authenticated' message handler
      // once the server confirms the session is restored.
    }
  }

  /// Check if the background service rendered a wallpaper while the app was
  /// sleeping and apply it now that we're back in the foreground.
  Future<void> _applyPendingWallpaper() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool('bg_wallpaper_pending') ?? false;
      if (!pending) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/locksync_bg_wallpaper.png');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await WallpaperService.setWallpaperSilent(bytes);
      }
      await prefs.setBool('bg_wallpaper_pending', false);
    } catch (e) {
      debugPrint('[WS] Failed to apply pending wallpaper: $e');
    }
  }

  void _handleAppBackgrounded() {
    // Hand the WebSocket back to the background service so lock screen
    // notifications and auto-wallpaper updates keep working when the
    // app is not in the foreground.
    if (storage.isPaired) {
      LockScreenService.resume();
    }
  }

  Future<void> connect() async {
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected ||
        _status == ConnectionStatus.paired) {
      return;
    }
    _status = ConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await channel.ready;
      // Verify we weren't disposed or disconnected while awaiting
      if (_status != ConnectionStatus.connecting) {
        channel.sink.close();
        return;
      }
      _channel = channel;
      _channel!.stream.listen(
        _onMessage,
        onError: (error) {
          debugPrint('[WS] Error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[WS] Connection closed');
          _handleDisconnect();
        },
      );
      _status = ConnectionStatus.connected;
      _reconnectAttempts = 0;
      _startPing();
      notifyListeners();

      if (storage.isPaired) {
        authenticate();
      }
    } catch (e) {
      debugPrint('[WS] Connect failed: $e');
      // Reset to a state that _handleDisconnect can process
      _status = ConnectionStatus.connecting;
      _handleDisconnect();
    }
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = msg['type'] as String?;

    switch (type) {
      case 'code_created':
        _pairingCode = msg['code'] as String;
        notifyListeners();
        break;

      case 'code_expired':
        _pairingCode = null;
        _errorMessage = 'Pairing code expired. Generate a new one.';
        notifyListeners();
        break;

      case 'paired':
        _handlePaired(msg);
        break;

      case 'authenticated':
        _isReconnecting = false;
        _pairId = msg['pairId'] as String;
        _partnerId = msg['partnerId'] as String;
        _partnerOnline = msg['partnerOnline'] as bool? ?? false;
        // Restore buffered last state if server sends it
        if (msg['lastState'] != null) {
          final lastState = msg['lastState'] as Map<String, dynamic>;
          if (lastState['text'] != null) {
            _partnerText = lastState['text'] as String;
          }
          if (lastState['displayName'] != null) {
            _partnerDisplayName = lastState['displayName'] as String;
            storage.setPartnerName(_partnerDisplayName!);
          }
          if (lastState['mood'] != null) {
            _partnerMood = lastState['mood'] as String;
          }
          if (lastState['canvas'] != null) {
            _partnerCanvasData = lastState['canvas'] as Map<String, dynamic>;
          }
        }
        _status = ConnectionStatus.paired;
        // Send our display name and mood to partner
        _syncDisplayName();
        _syncMood();
        notifyListeners();
        break;

      case 'token_refreshed':
        storage.updateTokens(
          accessToken: msg['accessToken'] as String,
          refreshToken: msg['refreshToken'] as String,
        );
        break;

      case 'sync':
        _handleSyncMessage(msg);
        break;

      case 'partner_online':
        _partnerOnline = true;
        notifyListeners();
        break;

      case 'partner_offline':
        _partnerOnline = false;
        notifyListeners();
        break;

      case 'pong':
        break;

      case 'error':
        _errorMessage = msg['message'] as String?;
        final code = msg['code'] as String?;
        if (code == 'PAIR_NOT_FOUND' || code == 'INVALID_TOKEN') {
          storage.clearSession();
          _status = ConnectionStatus.connected;
        }
        notifyListeners();
        break;
    }
  }

  void _handleSyncMessage(Map<String, dynamic> msg) {
    final payload = msg['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    final syncType = payload['syncType'] as String? ?? 'text';

    switch (syncType) {
      case 'text':
        _partnerText = (payload['text'] as String?) ?? _partnerText;
        notifyListeners();
        break;
      case 'canvas':
        _partnerCanvasData = payload['canvasData'] as Map<String, dynamic>?;
        _partnerText = (payload['text'] as String?) ?? _partnerText;
        notifyListeners();
        if (_partnerCanvasData != null) {
          // Save partner canvas to local storage so preview and canvas
          // screen always have the latest shared state.
          storage.setCanvasState(jsonEncode(_partnerCanvasData));
          // Fire the canvas sync stream for live updates
          _canvasSyncController.add(_partnerCanvasData!);
          _maybeAutoUpdateWallpaper(_partnerCanvasData!);
        }
        break;
      case 'display_name':
        _partnerDisplayName = payload['displayName'] as String?;
        if (_partnerDisplayName != null) {
          storage.setPartnerName(_partnerDisplayName!);
        }
        notifyListeners();
        break;
      case 'mood':
        _partnerMood = payload['mood'] as String?;
        notifyListeners();
        break;
      case 'nudge':
        _nudgeController.add(null);
        // Also fire a local notification so the nudge appears even when the
        // app is in the foreground but the screen may be turning off.
        final partnerName = storage.partnerName ?? 'Your partner';
        LockScreenService.showForegroundNudge(partnerName);
        break;
      case 'reaction':
        _reactionController.add(payload);
        break;
      case 'grocery':
        final groceryItems = payload['items'];
        if (groceryItems is List) {
          storage.setGroceryList(
              List<Map<String, dynamic>>.from(groceryItems));
        }
        _widgetSyncController.add(payload);
        notifyListeners();
        break;
      case 'watchlist':
        final watchlistItems = payload['items'];
        if (watchlistItems is List) {
          storage.setWatchlist(
              List<Map<String, dynamic>>.from(watchlistItems));
        }
        _widgetSyncController.add(payload);
        notifyListeners();
        break;
      case 'reminder':
        final reminderItems = payload['items'];
        if (reminderItems is List) {
          storage.setReminders(
              List<Map<String, dynamic>>.from(reminderItems));
        }
        _widgetSyncController.add(payload);
        notifyListeners();
        break;
      case 'countdown':
        final countdownItems = payload['items'];
        if (countdownItems is List) {
          storage.setCountdowns(
              List<Map<String, dynamic>>.from(countdownItems));
        }
        _widgetSyncController.add(payload);
        notifyListeners();
        break;
      case 'moment':
        final momentData = Map<String, dynamic>.from(payload);
        final existing = storage.getMoments();
        existing.insert(0, momentData);
        storage.setMoments(existing);
        _widgetSyncController.add(payload);
        notifyListeners();
        break;
    }
  }

  // Widget sync stream for grocery/watchlist/reminders/countdowns
  final _widgetSyncController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onWidgetSync =>
      _widgetSyncController.stream;

  /// Called on every canvas sync. Auto-enables wallpaper updates on first
  /// use (no dialog needed) and schedules a debounced wallpaper render+set.
  void _maybeAutoUpdateWallpaper(Map<String, dynamic> canvasData) {
    if (!storage.autoWallpaperPrompted) {
      // Auto-enable lock screen updates — no dialog, just works.
      storage.setAutoWallpaperPrompted(true);
      storage.setAutoUpdateWallpaper(true);
    }
    if (storage.autoUpdateWallpaper) {
      scheduleWallpaperUpdate(canvasData);
    }
  }

  /// Debounced wallpaper update — renders the canvas 800ms after the last
  /// change so we don't set the wallpaper on every single point while the
  /// partner is actively drawing.
  ///
  /// Skipped while the app is in the background because the background-service
  /// isolate already handles wallpaper updates from its own WebSocket — this
  /// avoids duplicate renders and saves CPU/data.
  bool _wallpaperUpdateInProgress = false;

  void scheduleWallpaperUpdate(Map<String, dynamic> canvasData) {
    if (!_isInForeground) return;
    _wallpaperDebounce?.cancel();
    _wallpaperDebounce =
        Timer(const Duration(milliseconds: 800), () async {
      _wallpaperDebounce = null;
      if (!_isInForeground || _wallpaperUpdateInProgress) return;
      _wallpaperUpdateInProgress = true;
      try {
        final bytes = await CanvasRenderer.renderToBytes(canvasData);
        if (bytes != null && _isInForeground) {
          await WallpaperService.setWallpaperSilent(bytes);
        }
      } catch (e) {
        debugPrint('[WS] Wallpaper update failed: $e');
      } finally {
        _wallpaperUpdateInProgress = false;
      }
    });
  }

  void _handlePaired(Map<String, dynamic> msg) {
    _pairId = msg['pairId'] as String;
    _partnerId = msg['partnerId'] as String;
    _pairingCode = null;
    _status = ConnectionStatus.paired;

    storage.saveSession(
      accessToken: msg['accessToken'] as String,
      refreshToken: msg['refreshToken'] as String,
      pairId: _pairId!,
      partnerId: _partnerId!,
    );

    // Send display name after pairing
    _syncDisplayName();
    _syncMood();

    notifyListeners();
  }

  void requestCode() {
    _errorMessage = null;
    _send({'type': 'request_code', 'deviceId': storage.getDeviceId()});
  }

  void joinCode(String code) {
    _errorMessage = null;
    _send({
      'type': 'join_code',
      'code': code,
      'deviceId': storage.getDeviceId(),
    });
  }

  void authenticate() {
    final token = storage.accessToken;
    if (token != null) {
      _send({'type': 'authenticate', 'token': token});
    }
  }

  void sendText(String text) {
    if (_status != ConnectionStatus.paired) return;
    _send({
      'type': 'sync',
      'payload': {'syncType': 'text', 'text': text},
    });
  }

  void sendCanvasData(Map<String, dynamic> canvasData, {String? text}) {
    if (_status != ConnectionStatus.paired) return;
    final payload = {
      'syncType': 'canvas',
      'canvasData': canvasData,
      if (text != null) 'text': text,
    };
    _send({
      'type': 'sync',
      'payload': payload,
    });
    // Also trigger auto-wallpaper for our own changes
    _maybeAutoUpdateWallpaper(canvasData);
  }

  void _syncDisplayName() {
    final name = storage.displayName;
    if (name != null && name.isNotEmpty) {
      _send({
        'type': 'sync',
        'payload': {'syncType': 'display_name', 'displayName': name},
      });
    }
  }

  void sendDisplayName(String name) {
    storage.setDisplayName(name);
    if (_status == ConnectionStatus.paired) {
      _send({
        'type': 'sync',
        'payload': {'syncType': 'display_name', 'displayName': name},
      });
    }
  }

  void _syncMood() {
    final mood = storage.mood;
    if (mood.isNotEmpty) {
      _send({
        'type': 'sync',
        'payload': {'syncType': 'mood', 'mood': mood},
      });
    }
  }

  void sendMood(String emoji) {
    storage.setMood(emoji);
    if (_status == ConnectionStatus.paired) {
      _send({
        'type': 'sync',
        'payload': {'syncType': 'mood', 'mood': emoji},
      });
    }
  }

  void sendNudge() {
    if (_status != ConnectionStatus.paired) return;
    final now = DateTime.now();
    if (_lastNudgeSent != null &&
        now.difference(_lastNudgeSent!).inSeconds < 10) {
      return; // Rate limited
    }
    _lastNudgeSent = now;
    _send({
      'type': 'sync',
      'payload': {'syncType': 'nudge'},
    });
  }

  void sendReaction(String emoji, double x, double y) {
    if (_status != ConnectionStatus.paired) return;
    _send({
      'type': 'sync',
      'payload': {
        'syncType': 'reaction',
        'emoji': emoji,
        'x': x,
        'y': y,
      },
    });
  }

  void sendWidgetSync(String widgetType, Map<String, dynamic> data) {
    if (_status != ConnectionStatus.paired) return;
    _send({
      'type': 'sync',
      'payload': {
        'syncType': widgetType,
        ...data,
      },
    });
  }

  void unpair() {
    storage.clearSession();
    _pairId = null;
    _partnerId = null;
    _partnerOnline = false;
    _partnerText = '';
    _pairingCode = null;
    _partnerDisplayName = null;
    _partnerMood = null;
    _partnerCanvasData = null;
    _status = ConnectionStatus.connected;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null &&
        (_status == ConnectionStatus.connected ||
         _status == ConnectionStatus.paired)) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        debugPrint('[WS] Send failed: $e');
      }
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'type': 'ping'});
    });
  }

  void _handleDisconnect() {
    _pingTimer?.cancel();
    _channel = null;
    // Prevent re-entrant disconnect handling
    if (_status == ConnectionStatus.disconnected) return;
    _status = ConnectionStatus.disconnected;
    _partnerOnline = false;
    // Show reconnecting banner in SyncScreen while we attempt to restore
    if (storage.isPaired) {
      _isReconnecting = true;
    }
    notifyListeners();

    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 30));
    if (_reconnectAttempts < 5) _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_status == ConnectionStatus.disconnected) {
        connect();
      }
    });
  }

  void disconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _status = ConnectionStatus.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cancel timers and subscriptions first to prevent callbacks firing
    // after stream controllers are closed
    _wallpaperDebounce?.cancel();
    _wallpaperDebounce = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _bgServiceSub?.cancel();
    _bgServiceSub = null;
    // Close stream controllers
    _reactionController.close();
    _nudgeController.close();
    _widgetSyncController.close();
    _wallpaperPromptController.close();
    _canvasSyncController.close();
    // Disconnect WebSocket last
    _channel?.sink.close();
    _channel = null;
    _status = ConnectionStatus.disconnected;
    super.dispose();
  }
}
