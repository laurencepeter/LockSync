import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  static const _keyDeviceId = 'locksync_device_id';
  static const _keyAccessToken = 'locksync_access_token';
  static const _keyRefreshToken = 'locksync_refresh_token';
  static const _keyPairId = 'locksync_pair_id';
  static const _keyPartnerId = 'locksync_partner_id';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String getDeviceId() {
    var id = _prefs.getString(_keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  String? get accessToken => _prefs.getString(_keyAccessToken);
  String? get refreshToken => _prefs.getString(_keyRefreshToken);
  String? get pairId => _prefs.getString(_keyPairId);
  String? get partnerId => _prefs.getString(_keyPartnerId);

  bool get isPaired => accessToken != null && pairId != null;

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String pairId,
    required String partnerId,
  }) async {
    await _prefs.setString(_keyAccessToken, accessToken);
    await _prefs.setString(_keyRefreshToken, refreshToken);
    await _prefs.setString(_keyPairId, pairId);
    await _prefs.setString(_keyPartnerId, partnerId);
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _prefs.setString(_keyAccessToken, accessToken);
    await _prefs.setString(_keyRefreshToken, refreshToken);
  }

  Future<void> clearSession() async {
    await _prefs.remove(_keyAccessToken);
    await _prefs.remove(_keyRefreshToken);
    await _prefs.remove(_keyPairId);
    await _prefs.remove(_keyPartnerId);
  }
}
