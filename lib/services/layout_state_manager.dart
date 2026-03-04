import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../models/layout_state.dart';
import '../models/home_element.dart';
import '../models/sync_event.dart';
import 'local_storage_service.dart';

/// Manages the authoritative local [LayoutState] and produces [SyncEvent]s.
///
/// Acts as the single source of truth for the canvas. The UI reads state
/// from this notifier and calls mutating methods (add/update/delete) which:
///   1. Update local state immediately.
///   2. Persist to storage.
///   3. Emit a [SyncEvent] via [eventStream] for the [SyncEngine] to broadcast.
class LayoutStateManager extends ChangeNotifier {
  LayoutStateManager({
    required LocalStorageService storage,
    required String deviceId,
  })  : _storage = storage,
        _deviceId = deviceId;

  final LocalStorageService _storage;
  final String _deviceId;
  final _uuid = const Uuid();

  LayoutState _layout = LayoutState.empty('uninitialized');
  LayoutState get layout => _layout;

  final _eventController = StreamController<SyncEvent>.broadcast();

  /// Stream of locally-produced [SyncEvent]s to be broadcast by [SyncEngine].
  Stream<SyncEvent> get eventStream => _eventController.stream;

  // ── Initialization ────────────────────────────────────────────────

  Future<void> initForSpace(String spaceId) async {
    final stored = await _storage.getLayout(spaceId);
    if (stored != null) {
      _layout = stored;
    } else {
      _layout = LayoutState.empty(spaceId);
      await _storage.saveLayout(_layout);
    }
    notifyListeners();
  }

  // ── Local mutations (create → persist → emit event) ───────────────

  Future<SyncEvent> addElement(HomeElement element) async {
    _layout = _layout.withAddedElement(element);
    await _storage.saveLayout(_layout);
    notifyListeners();

    final event = SyncEvent(
      eventId: _uuid.v4(),
      elementId: element.elementId,
      changeType: AppConstants.changeAdd,
      payload: {'element': element.toJson()},
      timestamp: element.updatedAt,
      originatingDevice: _deviceId,
    );
    _eventController.add(event);
    return event;
  }

  Future<SyncEvent> updateElement(HomeElement element) async {
    // Stamp with current time before applying.
    final stamped = element.withUpdatedTimestamp();
    _layout = _layout.withUpdatedElement(stamped);
    await _storage.saveLayout(_layout);
    notifyListeners();

    final event = SyncEvent(
      eventId: _uuid.v4(),
      elementId: stamped.elementId,
      changeType: AppConstants.changeUpdate,
      payload: {'element': stamped.toJson()},
      timestamp: stamped.updatedAt,
      originatingDevice: _deviceId,
    );
    _eventController.add(event);
    return event;
  }

  Future<SyncEvent> deleteElement(String elementId) async {
    _layout = _layout.withRemovedElement(elementId);
    await _storage.saveLayout(_layout);
    notifyListeners();

    final event = SyncEvent(
      eventId: _uuid.v4(),
      elementId: elementId,
      changeType: AppConstants.changeDelete,
      payload: {},
      timestamp: DateTime.now(),
      originatingDevice: _deviceId,
    );
    _eventController.add(event);
    return event;
  }

  Future<SyncEvent> changeBackground(int colorArgb) async {
    _layout = _layout.withBackgroundColor(colorArgb);
    await _storage.saveLayout(_layout);
    notifyListeners();

    final event = SyncEvent(
      eventId: _uuid.v4(),
      elementId: '',
      changeType: AppConstants.changeBackgroundChange,
      payload: {'color': colorArgb},
      timestamp: DateTime.now(),
      originatingDevice: _deviceId,
    );
    _eventController.add(event);
    return event;
  }

  // ── Remote event application (from SyncEngine) ────────────────────

  /// Applies a [SyncEvent] received from a remote peer.
  /// Uses Last-Write-Wins for update conflicts.
  Future<void> applyRemoteEvent(SyncEvent event) async {
    switch (event.changeType) {
      case AppConstants.changeAdd:
        final el = HomeElement.fromJson(
            event.payload['element'] as Map<String, dynamic>);
        // Don't add if already present (idempotent).
        if (_layout.findElement(el.elementId) == null) {
          _layout = _layout.withAddedElement(el);
        }

      case AppConstants.changeUpdate:
        final el = HomeElement.fromJson(
            event.payload['element'] as Map<String, dynamic>);
        final existing = _layout.findElement(el.elementId);
        if (existing == null) {
          // Element doesn't exist locally yet → treat as add.
          _layout = _layout.withAddedElement(el);
        } else {
          // LWW: only apply if the incoming version is newer.
          if (event.timestamp.isAfter(existing.updatedAt) ||
              event.timestamp.isAtSameMomentAs(existing.updatedAt)) {
            _layout = _layout.withUpdatedElement(el);
          }
        }

      case AppConstants.changeDelete:
        _layout = _layout.withRemovedElement(event.elementId);

      case AppConstants.changeBackgroundChange:
        final color = event.payload['color'] as int?;
        if (color != null) _layout = _layout.withBackgroundColor(color);
    }

    await _storage.saveLayout(_layout);
    notifyListeners();
  }

  /// Replaces the entire layout with a [LayoutState] snapshot (late-join).
  Future<void> applySnapshot(LayoutState snapshot) async {
    _layout = snapshot;
    await _storage.saveLayout(_layout);
    notifyListeners();
  }

  @override
  void dispose() {
    _eventController.close();
    super.dispose();
  }
}
