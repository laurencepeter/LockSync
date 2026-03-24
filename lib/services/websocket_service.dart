import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  void _handleAppResumed() {
    if (_status == ConnectionStatus.disconnected ||
        (_channel == null && storage.isPaired)) {
      _isReconnecting = true;
      notifyListeners();
      connect().then((_) {
        // After reconnect, delay briefly then clear reconnecting flag
        Future.delayed(const Duration(milliseconds: 500), () {
          _isReconnecting = false;
          notifyListeners();
        });
      });
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
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
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
      await _channel!.ready;
      _status = ConnectionStatus.connected;
      _reconnectAttempts = 0;
      _startPing();
      notifyListeners();

      if (storage.isPaired) {
        authenticate();
      }
    } catch (e) {
      debugPrint('[WS] Connect failed: $e');
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
        break;
      case 'reaction':
        _reactionController.add(payload);
        break;
      case 'grocery':
      case 'watchlist':
      case 'reminder':
      case 'countdown':
        // Widget data syncs — forward to listeners
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
    _send({
      'type': 'sync',
      'payload': {
        'syncType': 'canvas',
        'canvasData': canvasData,
        if (text != null) 'text': text,
      },
    });
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
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
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
    _status = ConnectionStatus.disconnected;
    _partnerOnline = false;
    notifyListeners();

    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 30));
    if (_reconnectAttempts < 5) _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
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
    _reactionController.close();
    _nudgeController.close();
    _widgetSyncController.close();
    disconnect();
    super.dispose();
  }
}
