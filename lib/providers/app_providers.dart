import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/device_utils.dart';
import '../models/space.dart';
import '../models/member.dart';
import '../models/layout_state.dart';
import '../models/sync_event.dart';
import '../services/local_storage_service.dart';
import '../services/peer_connection_service.dart';
import '../services/signaling_service.dart';
import '../services/layout_state_manager.dart';
import '../sync/sync_engine.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Infrastructure Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialized [LocalStorageService] — injected at startup via override.
final localStorageProvider = Provider<LocalStorageService>((ref) {
  throw UnimplementedError(
      'localStorageProvider must be overridden with an initialized instance.');
});

final _uuid = const Uuid();

/// The stable device ID for this installation (generated once, persisted).
final deviceIdProvider = FutureProvider<String>((ref) async {
  final storage = ref.read(localStorageProvider);
  var id = await storage.getDeviceId();
  if (id == null || id.isEmpty) {
    id = _uuid.v4();
    await storage.saveDeviceId(id);
  }
  return id;
});

/// The user-configured device name.
final deviceNameProvider = FutureProvider<String>((ref) async {
  final storage = ref.read(localStorageProvider);
  var name = await storage.getDeviceName();
  if (name == null || name.isEmpty) {
    name = DeviceUtils.generateDeviceName();
    await storage.saveDeviceName(name);
  }
  return name;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Space State
// ═══════════════════════════════════════════════════════════════════════════════

class SpaceNotifier extends StateNotifier<Space?> {
  SpaceNotifier(this._storage) : super(null);

  final LocalStorageService _storage;

  Future<void> loadFromStorage() async {
    final spaceId = await _storage.getCurrentSpaceId();
    if (spaceId == null) return;
    final space = await _storage.getSpace(spaceId);
    state = space;
  }

  Future<void> setSpace(Space space) async {
    await _storage.saveSpace(space);
    await _storage.saveCurrentSpaceId(space.spaceId);
    state = space;
  }

  Future<void> clearSpace() async {
    await _storage.clearCurrentSpaceId();
    state = null;
  }
}

final spaceProvider = StateNotifierProvider<SpaceNotifier, Space?>((ref) {
  return SpaceNotifier(ref.read(localStorageProvider));
});

// ═══════════════════════════════════════════════════════════════════════════════
// Members State
// ═══════════════════════════════════════════════════════════════════════════════

class MembersNotifier extends StateNotifier<List<Member>> {
  MembersNotifier(this._storage) : super([]);

  final LocalStorageService _storage;

  Future<void> loadForSpace(String spaceId) async {
    state = await _storage.getMembers(spaceId);
  }

  Future<void> upsertMember(Member member) async {
    final existing = state.any((m) => m.deviceId == member.deviceId);
    if (existing) {
      state = state
          .map((m) => m.deviceId == member.deviceId ? member : m)
          .toList();
    } else {
      state = [...state, member];
    }
    // Persist
    final spaceId = state.isNotEmpty ? member.spaceId : null;
    if (spaceId != null) await _storage.saveMembers(spaceId, state);
  }

  Future<void> markDisconnected(String deviceId) async {
    state = state.map((m) {
      if (m.deviceId != deviceId) return m;
      return m.copyWith(
          connectionStatus: 'disconnected', lastSeen: DateTime.now());
    }).toList();
  }

  void clear() => state = [];
}

final membersProvider =
    StateNotifierProvider<MembersNotifier, List<Member>>((ref) {
  return MembersNotifier(ref.read(localStorageProvider));
});

// ═══════════════════════════════════════════════════════════════════════════════
// Connection State
// ═══════════════════════════════════════════════════════════════════════════════

final connectionStatusProvider =
    StateProvider<PeerConnectionStatus>((ref) => PeerConnectionStatus.disconnected);

final connectionRoleProvider =
    StateProvider<ConnectionRole>((ref) => ConnectionRole.none);

// ═══════════════════════════════════════════════════════════════════════════════
// Services (created once per app lifecycle)
// ═══════════════════════════════════════════════════════════════════════════════

final peerConnectionServiceProvider =
    Provider<PeerConnectionService?>((ref) => null);

final layoutStateManagerProvider =
    ChangeNotifierProvider<LayoutStateManager?>((ref) => null);

final syncEngineProvider = Provider<SyncEngine?>((ref) => null);

/// Holds the layout data as plain state for UI rebuilds.
final layoutProvider = StateProvider<LayoutState?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════════════
// App Controller — owns all runtime service instances
// ═══════════════════════════════════════════════════════════════════════════════

/// Top-level application controller that wires all services together.
class AppController extends ChangeNotifier {
  AppController(this._storage);

  final LocalStorageService _storage;

  PeerConnectionService? _connection;
  LayoutStateManager? _layoutManager;
  SyncEngine? _syncEngine;

  PeerConnectionService? get connection => _connection;
  LayoutStateManager? get layoutManager => _layoutManager;
  SyncEngine? get syncEngine => _syncEngine;

  StreamSubscription<PeerConnectionStatus>? _statusSub;
  StreamSubscription<Map<String, String>>? _memberJoinedSub;

  // Callbacks set by the provider layer.
  void Function(PeerConnectionStatus)? onStatusChanged;
  void Function(Member)? onMemberJoined;

  bool _running = false;
  bool get isRunning => _running;

  Future<void> startAsHost({
    required Space space,
    required String deviceId,
    required String deviceName,
    required int port,
    required String localIp,
  }) async {
    await _teardown();

    _connection = PeerConnectionService(
        deviceId: deviceId, deviceName: deviceName);
    _layoutManager = LayoutStateManager(storage: _storage, deviceId: deviceId);
    await _layoutManager!.initForSpace(space.spaceId);

    _syncEngine = SyncEngine(
      deviceId: deviceId,
      connectionService: _connection!,
      layoutManager: _layoutManager!,
      storageService: _storage,
    );
    _syncEngine!.initialize();

    await _connection!.startHostServer(
        localIp: localIp, port: port, host: '0.0.0.0');

    _wireStreams(space);
    _running = true;
    notifyListeners();
  }

  Future<void> startAsClient({
    required Space space,
    required String deviceId,
    required String deviceName,
    required String wsUrl,
  }) async {
    await _teardown();

    _connection = PeerConnectionService(
        deviceId: deviceId, deviceName: deviceName);
    _layoutManager = LayoutStateManager(storage: _storage, deviceId: deviceId);
    await _layoutManager!.initForSpace(space.spaceId);

    _syncEngine = SyncEngine(
      deviceId: deviceId,
      connectionService: _connection!,
      layoutManager: _layoutManager!,
      storageService: _storage,
    );
    _syncEngine!.initialize();

    await _connection!.connectToHost(wsUrl);

    _wireStreams(space);
    _syncEngine!.requestSnapshot();
    _running = true;
    notifyListeners();
  }

  void _wireStreams(Space space) {
    _statusSub = _connection!.statusStream.listen((s) {
      onStatusChanged?.call(s);
    });
    _memberJoinedSub = _connection!.memberJoined.listen((info) {
      final member = Member(
        memberId: _uuid.v4(),
        deviceId: info['deviceId'] ?? '',
        deviceName: info['deviceName'] ?? 'Unknown',
        spaceId: space.spaceId,
        connectionStatus: 'connected',
        lastSeen: DateTime.now(),
      );
      onMemberJoined?.call(member);
    });
  }

  Future<void> leaveSpace() async {
    await _teardown();
    _running = false;
    notifyListeners();
  }

  Future<void> _teardown() async {
    _syncEngine?.dispose();
    _syncEngine = null;

    await _connection?.disconnect();
    _connection?.dispose();
    _connection = null;

    _layoutManager?.dispose();
    _layoutManager = null;

    await _statusSub?.cancel();
    await _memberJoinedSub?.cancel();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  return AppController(ref.read(localStorageProvider));
});
