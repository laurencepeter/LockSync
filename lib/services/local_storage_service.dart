import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/space.dart';
import '../models/member.dart';
import '../models/layout_state.dart';
import '../models/sync_event.dart';

/// Manages all persistent local storage using Hive boxes.
///
/// All data is stored as JSON strings in untyped boxes to avoid code
/// generation requirements while retaining full schema flexibility.
class LocalStorageService {
  late Box<String> _spacesBox;
  late Box<String> _membersBox;
  late Box<String> _layoutsBox;
  late Box<String> _eventsBox;
  late Box<String> _settingsBox;

  /// Must be called once before any other method (typically in main()).
  Future<void> initialize() async {
    await Hive.initFlutter();
    _spacesBox = await Hive.openBox<String>(AppConstants.spacesBox);
    _membersBox = await Hive.openBox<String>(AppConstants.membersBox);
    _layoutsBox = await Hive.openBox<String>(AppConstants.layoutsBox);
    _eventsBox = await Hive.openBox<String>(AppConstants.pendingEventsBox);
    _settingsBox = await Hive.openBox<String>(AppConstants.settingsBox);
  }

  // ── Settings ──────────────────────────────────────────────────────

  Future<String?> getDeviceId() async =>
      _settingsBox.get(AppConstants.keyDeviceId);

  Future<void> saveDeviceId(String id) async =>
      _settingsBox.put(AppConstants.keyDeviceId, id);

  Future<String?> getDeviceName() async =>
      _settingsBox.get(AppConstants.keyDeviceName);

  Future<void> saveDeviceName(String name) async =>
      _settingsBox.put(AppConstants.keyDeviceName, name);

  Future<String?> getCurrentSpaceId() async =>
      _settingsBox.get(AppConstants.keyCurrentSpaceId);

  Future<void> saveCurrentSpaceId(String id) async =>
      _settingsBox.put(AppConstants.keyCurrentSpaceId, id);

  Future<void> clearCurrentSpaceId() async =>
      _settingsBox.delete(AppConstants.keyCurrentSpaceId);

  // ── Space ─────────────────────────────────────────────────────────

  Future<void> saveSpace(Space space) async {
    await _spacesBox.put(space.spaceId, jsonEncode(space.toJson()));
  }

  Future<Space?> getSpace(String spaceId) async {
    final raw = _spacesBox.get(spaceId);
    if (raw == null) return null;
    return Space.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<Space>> getAllSpaces() async {
    return _spacesBox.values
        .map((raw) {
          try {
            return Space.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Space>()
        .toList();
  }

  Future<void> deleteSpace(String spaceId) async {
    await _spacesBox.delete(spaceId);
  }

  // ── Members ───────────────────────────────────────────────────────

  /// Persists a list of members for a space (replaces existing).
  Future<void> saveMembers(String spaceId, List<Member> members) async {
    final json = jsonEncode(members.map((m) => m.toJson()).toList());
    await _membersBox.put(spaceId, json);
  }

  Future<List<Member>> getMembers(String spaceId) async {
    final raw = _membersBox.get(spaceId);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) {
          try {
            return Member.fromJson(e as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Member>()
        .toList();
  }

  // ── Layout ────────────────────────────────────────────────────────

  Future<void> saveLayout(LayoutState layout) async {
    await _layoutsBox.put(layout.layoutId, jsonEncode(layout.toJson()));
  }

  Future<LayoutState?> getLayout(String layoutId) async {
    final raw = _layoutsBox.get(layoutId);
    if (raw == null) return null;
    return LayoutState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  // ── Pending sync events ───────────────────────────────────────────

  Future<void> queueEvent(SyncEvent event) async {
    await _eventsBox.put(event.eventId, jsonEncode(event.toJson()));
  }

  Future<List<SyncEvent>> getPendingEvents() async {
    return _eventsBox.values
        .map((raw) {
          try {
            final e =
                SyncEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
            return e.synced ? null : e;
          } catch (_) {
            return null;
          }
        })
        .whereType<SyncEvent>()
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> markEventSynced(String eventId) async {
    final raw = _eventsBox.get(eventId);
    if (raw == null) return;
    final event =
        SyncEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    await _eventsBox.put(eventId, jsonEncode(event.markSynced().toJson()));
  }

  /// Removes all events that have already been synced.
  Future<void> pruneOldEvents() async {
    final toDelete = _eventsBox.keys.where((key) {
      final raw = _eventsBox.get(key as String);
      if (raw == null) return true;
      try {
        final e = SyncEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        return e.synced;
      } catch (_) {
        return true;
      }
    }).toList();
    await _eventsBox.deleteAll(toDelete);
  }
}
