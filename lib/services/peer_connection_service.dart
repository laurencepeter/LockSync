import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../core/constants/app_constants.dart';

// ── Message model ────────────────────────────────────────────────────────────

/// A typed message exchanged between peers over WebSocket.
class PeerMessage {
  final String type;
  final Map<String, dynamic> payload;

  const PeerMessage({required this.type, required this.payload});

  factory PeerMessage.fromJson(Map<String, dynamic> json) => PeerMessage(
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      );

  Map<String, dynamic> toJson() => {'type': type, 'payload': payload};

  String encode() => jsonEncode(toJson());

  static PeerMessage? tryDecode(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      return PeerMessage.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}

// ── Roles ─────────────────────────────────────────────────────────────────────

enum ConnectionRole { host, client, none }

enum PeerConnectionStatus { disconnected, connecting, connected }

// ── Service ───────────────────────────────────────────────────────────────────

/// Manages peer-to-peer WebSocket communication.
///
/// **Host mode**: starts a dart:io HttpServer on [defaultWsPort], accepts
/// incoming WebSocket connections, and rebroadcasts all messages to every
/// other connected peer.
///
/// **Client mode**: connects to the host via a ws:// URL obtained from the
/// QR/connection code, automatically reconnects on disconnect.
class PeerConnectionService {
  PeerConnectionService({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;

  // ── State ─────────────────────────────────────────────────────────

  ConnectionRole _role = ConnectionRole.none;
  PeerConnectionStatus _status = PeerConnectionStatus.disconnected;

  ConnectionRole get role => _role;
  PeerConnectionStatus get status => _status;
  bool get isConnected => _status == PeerConnectionStatus.connected;

  // ── Host state ────────────────────────────────────────────────────

  HttpServer? _httpServer;

  /// All currently connected client WebSocket instances (host only).
  final List<WebSocket> _clientSockets = [];

  // ── Client state ──────────────────────────────────────────────────

  WebSocketChannel? _clientChannel;
  String? _hostWsUrl;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  // ── Streams ───────────────────────────────────────────────────────

  final _messageController =
      StreamController<PeerMessage>.broadcast();
  final _statusController =
      StreamController<PeerConnectionStatus>.broadcast();
  final _memberJoinedController =
      StreamController<Map<String, String>>.broadcast();
  final _memberLeftController =
      StreamController<String>.broadcast();

  Stream<PeerMessage> get messages => _messageController.stream;
  Stream<PeerConnectionStatus> get statusStream => _statusController.stream;
  Stream<Map<String, String>> get memberJoined => _memberJoinedController.stream;
  Stream<String> get memberLeft => _memberLeftController.stream;

  // ── Host API ──────────────────────────────────────────────────────

  /// Starts a WebSocket server. Returns the local ws:// URL.
  Future<String> startHostServer({
    String host = '0.0.0.0',
    int port = AppConstants.defaultWsPort,
    required String localIp,
  }) async {
    _role = ConnectionRole.host;
    _setStatus(PeerConnectionStatus.connected);

    _httpServer = await HttpServer.bind(host, port);

    _httpServer!.transform(WebSocketTransformer()).listen(
      _onClientConnected,
      onError: (e) => print('[PeerService] Server error: $e'),
    );

    _startPingTimer();

    final wsUrl = 'ws://$localIp:$port';
    print('[PeerService] Host started at $wsUrl');
    return wsUrl;
  }

  void _onClientConnected(WebSocket ws) {
    print('[PeerService] New client connected');
    _clientSockets.add(ws);

    // Notify sync engine that a new peer joined.
    _memberJoinedController.add({'deviceId': '', 'deviceName': 'Unknown'});

    ws.listen(
      (data) {
        final msg = PeerMessage.tryDecode(data);
        if (msg == null) return;

        // Capture member info from MEMBER_UPDATE before rebroadcasting.
        if (msg.type == AppConstants.msgMemberUpdate) {
          final deviceId = msg.payload['deviceId'] as String? ?? '';
          final deviceName = msg.payload['deviceName'] as String? ?? '';
          _memberJoinedController.add(
              {'deviceId': deviceId, 'deviceName': deviceName});
        }

        if (msg.type == AppConstants.msgPing) {
          _sendToSocket(
              ws,
              PeerMessage(
                type: AppConstants.msgPong,
                payload: {'deviceId': deviceId},
              ));
          return;
        }

        // Forward to all other clients + expose via stream.
        _rebroadcastExcept(ws, data as String);
        _messageController.add(msg);
      },
      onDone: () {
        _clientSockets.remove(ws);
        print('[PeerService] Client disconnected');
      },
      onError: (e) {
        _clientSockets.remove(ws);
        print('[PeerService] Client error: $e');
      },
      cancelOnError: true,
    );
  }

  void _rebroadcastExcept(WebSocket sender, String raw) {
    for (final ws in List<WebSocket>.from(_clientSockets)) {
      if (!identical(ws, sender)) {
        try {
          ws.add(raw);
        } catch (_) {}
      }
    }
  }

  // ── Client API ────────────────────────────────────────────────────

  /// Connects to a host at [wsUrl]. Retries automatically on disconnect.
  Future<void> connectToHost(String wsUrl) async {
    _role = ConnectionRole.client;
    _hostWsUrl = wsUrl;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _setStatus(PeerConnectionStatus.connecting);
    try {
      _clientChannel = IOWebSocketChannel.connect(
        Uri.parse(_hostWsUrl!),
        connectTimeout: const Duration(seconds: 10),
      );

      // Wait for the connection to be established.
      await _clientChannel!.ready;

      _setStatus(PeerConnectionStatus.connected);
      _reconnectAttempts = 0;
      _startPingTimer();

      // Announce ourselves to the host.
      sendMessage(PeerMessage(
        type: AppConstants.msgMemberUpdate,
        payload: {'deviceId': deviceId, 'deviceName': deviceName},
      ));

      _clientChannel!.stream.listen(
        (data) {
          final msg = PeerMessage.tryDecode(data);
          if (msg == null) return;
          if (msg.type == AppConstants.msgPong) return;
          _messageController.add(msg);
        },
        onDone: () {
          print('[PeerService] Host disconnected — scheduling reconnect');
          _pingTimer?.cancel();
          _setStatus(PeerConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        onError: (e) {
          print('[PeerService] Connection error: $e');
          _pingTimer?.cancel();
          _setStatus(PeerConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('[PeerService] Connect failed: $e');
      _setStatus(PeerConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) {
      print('[PeerService] Max reconnect attempts reached');
      return;
    }
    final delay = AppConstants.reconnectBaseDelayMs *
        (1 << _reconnectAttempts.clamp(0, 6));
    _reconnectAttempts++;
    print('[PeerService] Reconnecting in ${delay}ms (attempt $_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), _doConnect);
  }

  // ── Messaging ─────────────────────────────────────────────────────

  /// Sends a message to all peers (host broadcasts; client sends to host).
  void sendMessage(PeerMessage message) {
    if (_role == ConnectionRole.host) {
      // Expose locally + broadcast to clients.
      _messageController.add(message);
      final raw = message.encode();
      for (final ws in List<WebSocket>.from(_clientSockets)) {
        try {
          ws.add(raw);
        } catch (_) {}
      }
    } else if (_role == ConnectionRole.client) {
      try {
        _clientChannel?.sink.add(message.encode());
      } catch (_) {}
    }
  }

  void _sendToSocket(WebSocket ws, PeerMessage message) {
    try {
      ws.add(message.encode());
    } catch (_) {}
  }

  // ── Ping / keep-alive ─────────────────────────────────────────────

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(AppConstants.pingInterval, (_) {
      if (_role == ConnectionRole.client) {
        try {
          _clientChannel?.sink.add(PeerMessage(
            type: AppConstants.msgPing,
            payload: {'deviceId': deviceId},
          ).encode());
        } catch (_) {}
      }
    });
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  void _setStatus(PeerConnectionStatus s) {
    _status = s;
    _statusController.add(s);
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    if (_role == ConnectionRole.client) {
      await _clientChannel?.sink.close();
      _clientChannel = null;
    } else if (_role == ConnectionRole.host) {
      for (final ws in List<WebSocket>.from(_clientSockets)) {
        try {
          await ws.close();
        } catch (_) {}
      }
      _clientSockets.clear();
      await _httpServer?.close(force: true);
      _httpServer = null;
    }
    _role = ConnectionRole.none;
    _setStatus(PeerConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
    _memberJoinedController.close();
    _memberLeftController.close();
  }
}
