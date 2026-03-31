import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  static const _keyDeviceId = 'locksync_device_id';
  static const _keyAccessToken = 'locksync_access_token';
  static const _keyRefreshToken = 'locksync_refresh_token';
  static const _keyPairId = 'locksync_pair_id';
  static const _keyPartnerId = 'locksync_partner_id';
  static const _keyDisplayName = 'locksync_display_name';
  static const _keyPartnerName = 'locksync_partner_name';
  static const _keyUserColor = 'locksync_user_color';
  static const _keyUserFont = 'locksync_user_font';
  static const _keyMood = 'locksync_mood';
  static const _keyAutoUpdateWallpaper = 'locksync_auto_update_wallpaper';
  static const _keyAutoWallpaperPrompted = 'locksync_auto_wallpaper_prompted';
  static const _keyOverlayPermissionRequested = 'locksync_overlay_permission_requested';
  static const _keyFullScreenIntentPermissionRequested = 'locksync_fsi_permission_requested';
  static const _keyMenuPrimaryColor = 'locksync_menu_primary_color';
  static const _keyMenuAccentColor = 'locksync_menu_accent_color';
  static const _keyMenuFont = 'locksync_menu_font';
  static const _keyCanvasState = 'locksync_canvas_state';
  static const _keyMemories = 'locksync_memories';
  static const _keyActiveTheme = 'locksync_active_theme';
  static const _keyGroceryList = 'locksync_grocery_list';
  static const _keyWatchlist = 'locksync_watchlist';
  static const _keyReminders = 'locksync_reminders';
  static const _keyCountdowns = 'locksync_countdowns';
  static const _keyMoments = 'locksync_moments';

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

  // Display name
  String? get displayName => _prefs.getString(_keyDisplayName);
  Future<void> setDisplayName(String name) async {
    await _prefs.setString(_keyDisplayName, name);
  }

  String? get partnerName => _prefs.getString(_keyPartnerName);
  Future<void> setPartnerName(String name) async {
    await _prefs.setString(_keyPartnerName, name);
  }

  // User writing style
  int get userColor => _prefs.getInt(_keyUserColor) ?? 0xFF6C5CE7;
  Future<void> setUserColor(int color) async {
    await _prefs.setInt(_keyUserColor, color);
  }

  String get userFont => _prefs.getString(_keyUserFont) ?? 'Inter';
  Future<void> setUserFont(String font) async {
    await _prefs.setString(_keyUserFont, font);
  }

  // Mood
  String get mood => _prefs.getString(_keyMood) ?? '';
  Future<void> setMood(String emoji) async {
    await _prefs.setString(_keyMood, emoji);
  }

  // Settings
  // Defaults to true — lock screen updates are on by default after first
  // permission dialog. Users can turn this off in Settings → Lock Screen.
  bool get autoUpdateWallpaper =>
      _prefs.getBool(_keyAutoUpdateWallpaper) ?? true;
  Future<void> setAutoUpdateWallpaper(bool value) async {
    await _prefs.setBool(_keyAutoUpdateWallpaper, value);
  }

  bool get autoWallpaperPrompted =>
      _prefs.getBool(_keyAutoWallpaperPrompted) ?? false;
  Future<void> setAutoWallpaperPrompted(bool value) async {
    await _prefs.setBool(_keyAutoWallpaperPrompted, value);
  }

  // Permission request tracking (show each dialog only once)
  bool get overlayPermissionRequested =>
      _prefs.getBool(_keyOverlayPermissionRequested) ?? false;
  Future<void> setOverlayPermissionRequested(bool value) async {
    await _prefs.setBool(_keyOverlayPermissionRequested, value);
  }

  bool get fullScreenIntentPermissionRequested =>
      _prefs.getBool(_keyFullScreenIntentPermissionRequested) ?? false;
  Future<void> setFullScreenIntentPermissionRequested(bool value) async {
    await _prefs.setBool(_keyFullScreenIntentPermissionRequested, value);
  }

  // UI customization (color/font overrides set from hidden settings menu)
  // Stored as ints (ARGB) / strings; null means "use app default".
  int? get menuPrimaryColor => _prefs.containsKey(_keyMenuPrimaryColor)
      ? _prefs.getInt(_keyMenuPrimaryColor)
      : null;
  Future<void> setMenuPrimaryColor(int? color) async {
    if (color == null) {
      await _prefs.remove(_keyMenuPrimaryColor);
    } else {
      await _prefs.setInt(_keyMenuPrimaryColor, color);
    }
  }

  int? get menuAccentColor => _prefs.containsKey(_keyMenuAccentColor)
      ? _prefs.getInt(_keyMenuAccentColor)
      : null;
  Future<void> setMenuAccentColor(int? color) async {
    if (color == null) {
      await _prefs.remove(_keyMenuAccentColor);
    } else {
      await _prefs.setInt(_keyMenuAccentColor, color);
    }
  }

  String? get menuFont => _prefs.getString(_keyMenuFont);
  Future<void> setMenuFont(String? font) async {
    if (font == null) {
      await _prefs.remove(_keyMenuFont);
    } else {
      await _prefs.setString(_keyMenuFont, font);
    }
  }

  // Active theme
  String get activeTheme => _prefs.getString(_keyActiveTheme) ?? 'default';
  Future<void> setActiveTheme(String theme) async {
    await _prefs.setString(_keyActiveTheme, theme);
  }

  // Canvas state (JSON serialized)
  String? get canvasState => _prefs.getString(_keyCanvasState);
  Future<void> setCanvasState(String json) async {
    await _prefs.setString(_keyCanvasState, json);
  }

  // Memories (list of JSON snapshots)
  List<Map<String, dynamic>> get memories {
    final raw = _prefs.getString(_keyMemories);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveMemory(Map<String, dynamic> memory) async {
    final list = memories;
    list.insert(0, memory);
    await _prefs.setString(_keyMemories, jsonEncode(list));
  }

  Future<void> deleteMemory(int index) async {
    final list = memories;
    if (index < list.length) {
      list.removeAt(index);
      await _prefs.setString(_keyMemories, jsonEncode(list));
    }
  }

  // Grocery list (local)
  List<Map<String, dynamic>> get groceryList {
    final raw = _prefs.getString(_keyGroceryList);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> setGroceryList(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_keyGroceryList, jsonEncode(list));
  }

  // Watchlist (local)
  List<Map<String, dynamic>> get watchlist {
    final raw = _prefs.getString(_keyWatchlist);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> setWatchlist(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_keyWatchlist, jsonEncode(list));
  }

  // Reminders (local)
  List<Map<String, dynamic>> get reminders {
    final raw = _prefs.getString(_keyReminders);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> setReminders(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_keyReminders, jsonEncode(list));
  }

  // Countdowns (local)
  List<Map<String, dynamic>> get countdowns {
    final raw = _prefs.getString(_keyCountdowns);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> setCountdowns(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_keyCountdowns, jsonEncode(list));
  }

  // Moments (received image/video moments with view-count tracking)
  List<Map<String, dynamic>> getMoments() {
    final raw = _prefs.getString(_keyMoments);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> setMoments(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_keyMoments, jsonEncode(list));
  }

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
    await _prefs.remove(_keyPartnerName);
  }
}
