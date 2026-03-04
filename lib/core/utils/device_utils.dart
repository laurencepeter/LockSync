import 'dart:convert';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

/// Utilities for device identification and network info.
class DeviceUtils {
  DeviceUtils._();

  static final _networkInfo = NetworkInfo();

  /// Returns this device's local WiFi IP address, or null if unavailable.
  static Future<String?> getLocalIpAddress() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      if (ip != null && ip.isNotEmpty) return ip;
    } catch (_) {}
    // Fall back to iterating network interfaces.
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Generates a human-readable default device name.
  static String generateDeviceName() {
    final suffix = DateTime.now().millisecondsSinceEpoch % 10000;
    if (Platform.isAndroid) return 'Android-$suffix';
    if (Platform.isIOS) return 'iPhone-$suffix';
    if (Platform.isMacOS) return 'Mac-$suffix';
    if (Platform.isWindows) return 'Windows-$suffix';
    if (Platform.isLinux) return 'Linux-$suffix';
    return 'Device-$suffix';
  }

  /// Encodes connection info to a URL-safe base64 string for manual entry.
  static String encodeConnectionCode(Map<String, dynamic> connectionInfo) {
    final json = jsonEncode(connectionInfo);
    return base64Url.encode(utf8.encode(json));
  }

  /// Decodes a manual-entry connection code.
  static Map<String, dynamic>? decodeConnectionCode(String code) {
    try {
      final decoded = utf8.decode(base64Url.decode(code.trim()));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
