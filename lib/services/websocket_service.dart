import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, paired }

class WebSocketService extends ChangeNotifier {
  final StorageService storage;

  // Configure this to your VPS domain
  // For local dev: ws://localhost:8080
  // For production: wss://locksync.yourdomain.com
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

  ConnectionStatus get status => _status;
  String? get pairingCode => _pairingCode;
  String? get pairId => _pairId;
  String? get partnerId => _partnerId;
  bool get partnerOnline => _partnerOnline;
  String get partnerText => _partnerText;
  String? get errorMessage => _errorMessage;

  WebSocketService({required this.storage});

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
      // Await the WebSocket handshake before marking as connected.
      // On Android (dart:io), the connection is fully async — without this,
      // the status is set to connected before the TCP/TLS handshake completes,
      // causing authenticate() messages to be dropped and triggering an
      // immediate disconnect/reconnect loop. On web this is a no-op.
      await _channel!.ready;
      _status = ConnectionStatus.connected;
      _reconnectAttempts = 0;
      _startPing();
      notifyListeners();

      // If we have a saved session, try to re-authenticate
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
        _status = ConnectionStatus.paired;
        notifyListeners();
        break;

      case 'token_refreshed':
        storage.updateTokens(
          accessToken: msg['accessToken'] as String,
          refreshToken: msg['refreshToken'] as String,
        );
        break;

      case 'sync':
        _partnerText = (msg['payload']?['text'] as String?) ?? _partnerText;
        notifyListeners();
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
          // Session is dead, need to re-pair
          storage.clearSession();
          _status = ConnectionStatus.connected;
        }
        notifyListeners();
        break;
    }
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
      'payload': {'text': text},
    });
  }

  void unpair() {
    storage.clearSession();
    _pairId = null;
    _partnerId = null;
    _partnerOnline = false;
    _partnerText = '';
    _pairingCode = null;
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
    final wasPaired = _status == ConnectionStatus.paired;
    _status = ConnectionStatus.disconnected;
    _partnerOnline = false;
    notifyListeners();

    // Auto-reconnect with exponential backoff, retries indefinitely
    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 30));
    if (_reconnectAttempts < 5) _reconnectAttempts++; // cap counter so delay stays at 30s max
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
    disconnect();
    super.dispose();
  }
}
