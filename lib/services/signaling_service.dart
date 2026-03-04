import 'dart:convert';
import '../core/utils/device_utils.dart';
import '../models/space.dart';

/// Connection payload embedded in the QR code or manual connection code.
///
/// This is the only "signaling" data needed — it tells joining devices
/// exactly where to connect. No server required.
class ConnectionInfo {
  /// Protocol version for forward compatibility.
  final int version;
  final String spaceId;
  final String hostIp;
  final int port;
  final String hostDeviceId;
  final String? hostDeviceName;

  const ConnectionInfo({
    required this.version,
    required this.spaceId,
    required this.hostIp,
    required this.port,
    required this.hostDeviceId,
    this.hostDeviceName,
  });

  String get wsUrl => 'ws://$hostIp:$port';

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) => ConnectionInfo(
        version: (json['v'] as num?)?.toInt() ?? 1,
        spaceId: json['spaceId'] as String,
        hostIp: json['host'] as String,
        port: (json['port'] as num).toInt(),
        hostDeviceId: json['hostDeviceId'] as String,
        hostDeviceName: json['hostDeviceName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'v': version,
        'spaceId': spaceId,
        'host': hostIp,
        'port': port,
        'hostDeviceId': hostDeviceId,
        if (hostDeviceName != null) 'hostDeviceName': hostDeviceName,
      };

  /// Returns a compact JSON string suitable for embedding in a QR code.
  String toQrData() => jsonEncode(toJson());

  /// Returns a base64url-encoded string for manual text entry.
  String toConnectionCode() =>
      DeviceUtils.encodeConnectionCode(toJson());
}

/// Manages the creation and parsing of connection information.
///
/// This is the only "signaling" layer — it constructs and decodes
/// QR / manual connection codes. All actual data transfer happens
/// device-to-device via [PeerConnectionService].
class SignalingService {
  const SignalingService();

  /// Builds connection info for a host creating a new space.
  Future<ConnectionInfo?> buildConnectionInfo({
    required Space space,
    required int port,
    String? hostDeviceName,
  }) async {
    final ip = await DeviceUtils.getLocalIpAddress();
    if (ip == null) return null;
    return ConnectionInfo(
      version: 1,
      spaceId: space.spaceId,
      hostIp: ip,
      port: port,
      hostDeviceId: space.hostDeviceId,
      hostDeviceName: hostDeviceName,
    );
  }

  /// Parses connection info from a QR code payload (JSON string).
  ConnectionInfo? parseQrData(String qrData) {
    try {
      final map = jsonDecode(qrData) as Map<String, dynamic>;
      return ConnectionInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Parses connection info from a manually entered base64url code.
  ConnectionInfo? parseConnectionCode(String code) {
    final map = DeviceUtils.decodeConnectionCode(code);
    if (map == null) return null;
    try {
      return ConnectionInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
