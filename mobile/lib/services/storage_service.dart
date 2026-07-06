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

  /// [data] (List veya Map) → TTL sarmalayıcısıyla JSON olarak sakla.
  /// [ttl]: varsayılan 5 dakika. Mesajlar için 2 dakika kullanılabilir.
  static Future<void> cacheData(
    String key,
    dynamic data, {
    Duration ttl = const Duration(minutes: 5),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final wrapper = {
      '_d': data,
      '_t': DateTime.now().millisecondsSinceEpoch,
      '_x': ttl.inMilliseconds,
    };
    await prefs.setString(key, jsonEncode(wrapper));
  }

  /// Saklanan veriyi döner. TTL aşılmışsa null döner (sanki hiç yokmuş gibi).
  static Future<dynamic> getCachedData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      // Yeni TTL formatı: {"_d": data, "_t": savedAt, "_x": ttlMs}
      if (decoded is Map && decoded.containsKey('_t') && decoded.containsKey('_d')) {
        final savedAt = (decoded['_t'] as num).toInt();
        final ttlMs = (decoded['_x'] as num?)?.toInt() ?? 300000;
        final age = DateTime.now().millisecondsSinceEpoch - savedAt;
        if (age > ttlMs) return null; // süresi dolmuş
        return decoded['_d'];
      }
      // Eski format (TTL'siz) — geçerli kabul et, bir sonraki yazımda yeni formata geçer
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Mevcut oturumdaki kullanıcının ID'sini JWT token üzerinden çözer.
  static Future<int?> getCurrentUserId() async {
    final token = await getToken();
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = jsonDecode(payload);
      return int.tryParse(map['sub'].toString());
    } catch (_) {
      return null;
    }
  }

  static const _userEmailKey = 'teqlif_user_email';
  static const _userNameKey = 'teqlif_user_name';
  static const _userFullNameKey = 'teqlif_user_fullname';
  static const _userPremiumKey = 'teqlif_user_premium';
  static const _userPlanTypeKey = 'teqlif_user_plan_type';
  static const _userIdKey = 'teqlif_user_id';
  static const _userOnboardingKey = 'teqlif_user_onboarding';
  static const _userIsVerifiedKey = 'teqlif_user_is_verified';
  static const _userPhoneVerifiedKey = 'teqlif_user_phone_verified';

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
    required bool isPremium,
    String? planType,
    bool? onboardingCompleted,
    bool? isVerified,
    bool? phoneVerified,
  }) async {
    final futures = <Future<void>>[
      _secureStorage.write(key: _userIdKey, value: id.toString()),
      _secureStorage.write(key: _userEmailKey, value: email),
      _secureStorage.write(key: _userNameKey, value: username),
      _secureStorage.write(key: _userFullNameKey, value: fullName),
      _secureStorage.write(key: _userPremiumKey, value: isPremium.toString()),
    ];
    if (planType != null) {
      futures.add(_secureStorage.write(key: _userPlanTypeKey, value: planType));
    }
    if (onboardingCompleted != null) {
      futures.add(_secureStorage.write(key: _userOnboardingKey, value: onboardingCompleted.toString()));
    }
    if (isVerified != null) {
      futures.add(_secureStorage.write(key: _userIsVerifiedKey, value: isVerified.toString()));
    }
    if (phoneVerified != null) {
      futures.add(_secureStorage.write(key: _userPhoneVerifiedKey, value: phoneVerified.toString()));
    }
    await Future.wait(futures);
  }

  static Future<Map<String, dynamic>?> getUserInfo() async {
    final id = await _secureStorage.read(key: _userIdKey);
    if (id == null) return null;
    final email = await _secureStorage.read(key: _userEmailKey);
    final username = await _secureStorage.read(key: _userNameKey);
    final fullName = await _secureStorage.read(key: _userFullNameKey);
    final isPremium = await _secureStorage.read(key: _userPremiumKey);
    final planType = await _secureStorage.read(key: _userPlanTypeKey);
    final onboardingCompleted = await _secureStorage.read(key: _userOnboardingKey);
    final isVerified = await _secureStorage.read(key: _userIsVerifiedKey);
    final phoneVerified = await _secureStorage.read(key: _userPhoneVerifiedKey);
    return {
      'id': int.tryParse(id) ?? 0,
      'email': email ?? '',
      'username': username ?? '',
      'full_name': fullName ?? '',
      'is_premium': isPremium == 'true',
      'plan_type': planType,
      'onboarding_completed': onboardingCompleted == 'true',
      'is_verified': isVerified == 'true',
      'phone_verified': phoneVerified == 'true',
    };
  }

  // ── Avatar URL — in-memory cache (disk'e de yazılır, startup'ta restore edilir) ──
  static const _avatarUrlKey = 'teqlif_avatar_url';
  static String? _cachedAvatarUrl;

  /// Startup'ta bir kez çağrılır; SharedPreferences'tan URL'yi memory'e yükler.
  static Future<void> restoreAvatarUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedAvatarUrl = prefs.getString(_avatarUrlKey);
  }

  /// Profil API'sinden URL geldiğinde kaydet; hem memory hem disk güncellenir.
  static Future<void> saveAvatarUrl(String? url) async {
    _cachedAvatarUrl = url;
    final prefs = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      await prefs.setString(_avatarUrlKey, url);
    } else {
      await prefs.remove(_avatarUrlKey);
    }
  }

  /// Senkron getter — initState'de beklemeden kullanılabilir.
  static String? get cachedAvatarUrl => _cachedAvatarUrl;

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
