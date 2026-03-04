import 'package:equatable/equatable.dart';

/// Represents a shared collaborative space between connected devices.
class Space extends Equatable {
  final String spaceId;
  final DateTime createdAt;
  final String hostDeviceId;
  final String? spaceName;

  const Space({
    required this.spaceId,
    required this.createdAt,
    required this.hostDeviceId,
    this.spaceName,
  });

  factory Space.fromJson(Map<String, dynamic> json) => Space(
        spaceId: json['spaceId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        hostDeviceId: json['hostDeviceId'] as String,
        spaceName: json['spaceName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'spaceId': spaceId,
        'createdAt': createdAt.toIso8601String(),
        'hostDeviceId': hostDeviceId,
        if (spaceName != null) 'spaceName': spaceName,
      };

  Space copyWith({
    String? spaceId,
    DateTime? createdAt,
    String? hostDeviceId,
    String? spaceName,
  }) =>
      Space(
        spaceId: spaceId ?? this.spaceId,
        createdAt: createdAt ?? this.createdAt,
        hostDeviceId: hostDeviceId ?? this.hostDeviceId,
        spaceName: spaceName ?? this.spaceName,
      );

  @override
  List<Object?> get props => [spaceId, createdAt, hostDeviceId, spaceName];
}
