import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _tokenKey = 'teqlif_token';
  static const _refreshTokenKey = 'teqlif_refresh_token';
  // Token ve kimlik bilgileri için güvenli depolama (Keystore/Keychain)
  static final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Kasa (Cache) key sabitleri ────────────────────────────────────────────
  static const cacheMessages      = 'cache_messages';
  static const cacheNotifications = 'cache_notifications';
  static const cacheFeed          = 'cache_feed';
  static const cacheProfile       = 'cache_profile';       // tam user profili (profile_image_url dahil)
  static const cacheUserListings  = 'cache_user_listings'; // kendi ilanları
  static const cacheAuctions      = 'cache_auctions';
  static const cacheStreams       = 'cache_streams';
  static const cacheStories       = 'cache_stories';
  static const cacheMyStories     = 'cache_my_stories';

  /// [data] (List veya Map) → JSON String olarak sakla.
  static Future<void> cacheData(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  /// Saklanan JSON String'i decode ederek döner; yoksa null.
  static Future<dynamic> getCachedData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    return jsonDecode(raw);
  }
  static const _userEmailKey = 'teqlif_user_email';
  static const _userNameKey = 'teqlif_user_name';
  static const _userFullNameKey = 'teqlif_user_fullname';
  static const _userIdKey = 'teqlif_user_id';

  static Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return _secureStorage.read(key: _tokenKey);
  }

  static Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  static Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  static Future<void> saveUserInfo({
    required int id,
    required String email,
    required String username,
    required String fullName,
  }) async {
    await Future.wait([
      _secureStorage.write(key: _userIdKey, value: id.toString()),
      _secureStorage.write(key: _userEmailKey, value: email),
      _secureStorage.write(key: _userNameKey, value: username),
      _secureStorage.write(key: _userFullNameKey, value: fullName),
    ]);
  }

  static Future<Map<String, dynamic>?> getUserInfo() async {
    final id = await _secureStorage.read(key: _userIdKey);
    if (id == null) return null;
    final email = await _secureStorage.read(key: _userEmailKey);
    final username = await _secureStorage.read(key: _userNameKey);
    final fullName = await _secureStorage.read(key: _userFullNameKey);
    return {
      'id': int.tryParse(id) ?? 0,
      'email': email ?? '',
      'username': username ?? '',
      'full_name': fullName ?? '',
    };
  }

  static const _biometricKey = 'teqlif_biometric_enabled';

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, value);
  }

  static Future<void> clear() async {
    await Future.wait([
      _secureStorage.deleteAll(),
      SharedPreferences.getInstance().then((p) => p.clear()),
    ]);
  }

  static const _darkModeKey = 'teqlif_dark_mode';

  static Future<bool> isDarkModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  static Future<void> setDarkModeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }
}
