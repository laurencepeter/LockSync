import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:locksync/models/home_element.dart';
import 'package:locksync/models/layout_state.dart';
import 'package:locksync/models/sync_event.dart';
import 'package:locksync/core/constants/app_constants.dart';

// ── Model unit tests ─────────────────────────────────────────────────────────

void main() {
  group('HomeElement', () {
    test('serialises and deserialises correctly', () {
      final el = HomeElement.create(
        elementId: 'el-1',
        type: AppConstants.elementTextNote,
        position: const ElementPosition(x: 10, y: 20),
        properties: {'text': 'hello', 'color': 0xFFFFFFFF, 'fontSize': 16.0},
      );

      final json = el.toJson();
      final restored = HomeElement.fromJson(json);

      expect(restored.elementId, equals(el.elementId));
      expect(restored.type, equals(AppConstants.elementTextNote));
      expect(restored.position.x, equals(10.0));
      expect(restored.position.y, equals(20.0));
      expect(restored.properties['text'], equals('hello'));
    });

    test('copyWith updates only specified fields', () {
      final el = HomeElement.create(
        elementId: 'el-1',
        type: AppConstants.elementTextNote,
        position: const ElementPosition(x: 0, y: 0),
      );
      final moved = el.copyWith(
        position: const ElementPosition(x: 50, y: 75),
      );

      expect(moved.elementId, equals(el.elementId));
      expect(moved.position.x, equals(50.0));
      expect(moved.position.y, equals(75.0));
    });
  });

  group('LayoutState', () {
    late LayoutState layout;

    setUp(() {
      layout = LayoutState.empty('space-1');
    });

    test('empty layout has no elements', () {
      expect(layout.elements, isEmpty);
      expect(layout.version, equals(0));
    });

    test('withAddedElement increments version', () {
      final el = HomeElement.create(
        elementId: 'el-1',
        type: AppConstants.elementTextNote,
        position: const ElementPosition(x: 0, y: 0),
      );
      final updated = layout.withAddedElement(el);
      expect(updated.elements.length, equals(1));
      expect(updated.version, equals(1));
    });

    test('withRemovedElement removes only the target', () {
      final el1 = HomeElement.create(
        elementId: 'el-1',
        type: AppConstants.elementTextNote,
        position: const ElementPosition(x: 0, y: 0),
      );
      final el2 = HomeElement.create(
        elementId: 'el-2',
        type: AppConstants.elementDrawingCanvas,
        position: const ElementPosition(x: 100, y: 100),
      );
      final withTwo = layout.withAddedElement(el1).withAddedElement(el2);
      final withOne = withTwo.withRemovedElement('el-1');
      expect(withOne.elements.length, equals(1));
      expect(withOne.elements.first.elementId, equals('el-2'));
    });

    test('withUpdatedElement applies LWW correctly', () {
      final now = DateTime.now();
      final el = HomeElement(
        elementId: 'el-1',
        type: AppConstants.elementTextNote,
        position: const ElementPosition(x: 0, y: 0),
        size: const ElementSize(width: 160, height: 100),
        properties: {'text': 'original'},
        updatedAt: now,
      );
      final withEl = layout.withAddedElement(el);

      // Newer version should win.
      final newer = el.copyWith(
        properties: {'text': 'updated'},
        updatedAt: now.add(const Duration(milliseconds: 100)),
      );
      final updated = withEl.withUpdatedElement(newer);
      expect(updated.elements.first.properties['text'], equals('updated'));

      // Older version should NOT overwrite.
      final older = el.copyWith(
        properties: {'text': 'stale'},
        updatedAt: now.subtract(const Duration(milliseconds: 100)),
      );
      final notUpdated = updated.withUpdatedElement(older);
      expect(notUpdated.elements.first.properties['text'], equals('updated'));
    });

    test('serialises and deserialises full layout', () {
      final el = HomeElement.create(
        elementId: 'el-1',
        type: AppConstants.elementDrawingCanvas,
        position: const ElementPosition(x: 50, y: 60),
        properties: {'strokes': []},
      );
      final full = layout.withAddedElement(el).withBackgroundColor(0xFF1A1A2E);
      final json = full.toJson();
      final restored = LayoutState.fromJson(json);

      expect(restored.layoutId, equals(full.layoutId));
      expect(restored.version, equals(full.version));
      expect(restored.elements.length, equals(1));
      expect(restored.backgroundColor, equals(0xFF1A1A2E));
    });
  });

  group('SyncEvent', () {
    test('serialises and deserialises correctly', () {
      final event = SyncEvent(
        eventId: 'evt-1',
        elementId: 'el-1',
        changeType: AppConstants.changeAdd,
        payload: {'element': {}},
        timestamp: DateTime(2024, 1, 15, 12, 0, 0),
        originatingDevice: 'device-abc',
      );

      final json = event.toJson();
      final restored = SyncEvent.fromJson(json);

      expect(restored.eventId, equals('evt-1'));
      expect(restored.changeType, equals(AppConstants.changeAdd));
      expect(restored.originatingDevice, equals('device-abc'));
      expect(restored.synced, isFalse);
    });

    test('markSynced produces synced=true copy', () {
      final event = SyncEvent(
        eventId: 'evt-1',
        elementId: 'el-1',
        changeType: AppConstants.changeUpdate,
        payload: {},
        timestamp: DateTime.now(),
        originatingDevice: 'device-abc',
        synced: false,
      );

      final synced = event.markSynced();
      expect(synced.synced, isTrue);
      expect(synced.eventId, equals(event.eventId));
    });
  });

  group('Sync loop prevention', () {
    test('self-originated events must be ignored', () {
      const myDeviceId = 'my-device';
      final receivedEvents = <SyncEvent>[];

      final event = SyncEvent(
        eventId: 'evt-1',
        elementId: 'el-1',
        changeType: AppConstants.changeUpdate,
        payload: {},
        timestamp: DateTime.now(),
        originatingDevice: myDeviceId, // Same device!
      );

      // Simulated sync engine filter.
      void handleRemoteEvent(SyncEvent e, String deviceId) {
        if (e.originatingDevice == deviceId) return; // Filter self.
        receivedEvents.add(e);
      }

      handleRemoteEvent(event, myDeviceId);
      expect(receivedEvents, isEmpty);

      // A foreign event should pass through.
      final foreignEvent = event.markSynced(); // same data, just reuse
      final foreign = SyncEvent(
        eventId: 'evt-2',
        elementId: 'el-1',
        changeType: AppConstants.changeUpdate,
        payload: {},
        timestamp: DateTime.now(),
        originatingDevice: 'other-device',
      );
      handleRemoteEvent(foreign, myDeviceId);
      expect(receivedEvents.length, equals(1));
    });
  });

  group('Last-Write-Wins conflict resolution', () {
    test('newer timestamp wins', () {
      final base = DateTime(2024, 1, 15, 12, 0, 0);

      final elA = HomeElement(
        elementId: 'el-1',
        type: AppConstants.elementTextNote,
        position: const ElementPosition(x: 0, y: 0),
        size: const ElementSize(width: 160, height: 100),
        properties: {'text': 'Device A version'},
        updatedAt: base,
      );

      // Device B update arrives with a later timestamp.
      final elB = elA.copyWith(
        properties: {'text': 'Device B version'},
        updatedAt: base.add(const Duration(milliseconds: 500)),
      );

      // LWW resolution.
      final winner = elB.updatedAt.isAfter(elA.updatedAt) ? elB : elA;
      expect(winner.properties['text'], equals('Device B version'));
    });

    test('older timestamp loses', () {
      final base = DateTime(2024, 1, 15, 12, 0, 0);

      final elLocal = HomeElement(
        elementId: 'el-1',
        type: AppConstants.elementTextNote,
        position: const ElementPosition(x: 0, y: 0),
        size: const ElementSize(width: 160, height: 100),
        properties: {'text': 'Local newer version'},
        updatedAt: base.add(const Duration(seconds: 1)),
      );

      final elRemote = elLocal.copyWith(
        properties: {'text': 'Remote stale version'},
        updatedAt: base, // Older.
      );

      final winner = elRemote.updatedAt.isAfter(elLocal.updatedAt)
          ? elRemote
          : elLocal;
      expect(winner.properties['text'], equals('Local newer version'));
    });
  });
}
