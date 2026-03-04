import 'package:equatable/equatable.dart';

/// Represents a device connected to a shared Space.
class Member extends Equatable {
  final String memberId;
  final String deviceId;
  final String deviceName;
  final String spaceId;

  /// 'connected' | 'disconnected' | 'away'
  final String connectionStatus;
  final DateTime lastSeen;

  const Member({
    required this.memberId,
    required this.deviceId,
    required this.deviceName,
    required this.spaceId,
    required this.connectionStatus,
    required this.lastSeen,
  });

  bool get isConnected => connectionStatus == 'connected';

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        memberId: json['memberId'] as String,
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String? ?? 'Unknown Device',
        spaceId: json['spaceId'] as String,
        connectionStatus: json['connectionStatus'] as String? ?? 'disconnected',
        lastSeen: DateTime.parse(json['lastSeen'] as String),
      );

  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'spaceId': spaceId,
        'connectionStatus': connectionStatus,
        'lastSeen': lastSeen.toIso8601String(),
      };

  Member copyWith({
    String? memberId,
    String? deviceId,
    String? deviceName,
    String? spaceId,
    String? connectionStatus,
    DateTime? lastSeen,
  }) =>
      Member(
        memberId: memberId ?? this.memberId,
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        spaceId: spaceId ?? this.spaceId,
        connectionStatus: connectionStatus ?? this.connectionStatus,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  @override
  List<Object?> get props =>
      [memberId, deviceId, deviceName, spaceId, connectionStatus, lastSeen];
}
