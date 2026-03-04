import 'package:flutter_test/flutter_test.dart';
import 'package:locksync/models/space.dart';
import 'package:locksync/models/member.dart';

void main() {
  group('Space', () {
    test('serialises and deserialises', () {
      final space = Space(
        spaceId: 'space-123',
        createdAt: DateTime(2024, 6, 1),
        hostDeviceId: 'device-abc',
        spaceName: 'Our Space',
      );
      final json = space.toJson();
      final restored = Space.fromJson(json);

      expect(restored.spaceId, equals(space.spaceId));
      expect(restored.spaceName, equals('Our Space'));
      expect(restored.hostDeviceId, equals(space.hostDeviceId));
    });

    test('copyWith preserves unspecified fields', () {
      final space = Space(
        spaceId: 'space-123',
        createdAt: DateTime(2024, 6, 1),
        hostDeviceId: 'device-abc',
      );
      final updated = space.copyWith(spaceName: 'Renamed');
      expect(updated.spaceId, equals(space.spaceId));
      expect(updated.spaceName, equals('Renamed'));
    });
  });

  group('Member', () {
    test('isConnected returns true only for connected status', () {
      final connected = Member(
        memberId: 'm-1',
        deviceId: 'd-1',
        deviceName: 'Phone',
        spaceId: 'space-1',
        connectionStatus: 'connected',
        lastSeen: DateTime.now(),
      );
      final disconnected = connected.copyWith(
          connectionStatus: 'disconnected');

      expect(connected.isConnected, isTrue);
      expect(disconnected.isConnected, isFalse);
    });

    test('serialises and deserialises', () {
      final member = Member(
        memberId: 'm-1',
        deviceId: 'd-1',
        deviceName: 'My Phone',
        spaceId: 'space-1',
        connectionStatus: 'connected',
        lastSeen: DateTime(2024, 6, 1, 12, 0),
      );
      final json = member.toJson();
      final restored = Member.fromJson(json);

      expect(restored.deviceName, equals('My Phone'));
      expect(restored.connectionStatus, equals('connected'));
    });
  });
}
