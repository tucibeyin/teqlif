import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cache_service.dart';

class StorageService {
  static const _tokenKey = 'teqlif_token';
  static const _refreshTokenKey = 'teqlif_refresh_token';
  // Token ve kimlik bilgileri için güvenli depolama (Keystore/Keychain)
  static final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // In-memory token cache.
  //
  // Android EncryptedSharedPreferences (= Keystore-backed) can transiently
  // return null for existing keys when the device is locked, in Doze mode,
  // or on certain OEM Keystore implementations.  Without a cache every
  // apiCall() reads from storage, so a single transient null propagates as:
  //   getToken()==null → no Authorization header → backend 401
  //   → tryRefresh() → getRefreshToken()==null (same transient)
  //   → refreshed=false → authFailedStream → logout + deleteAll()
  //   → tokens are now permanently gone
  //
  // The cache is populated on the first successful storage read and on every
  // save/refresh. It lives for the process lifetime (resets on app restart,
  // which always re-reads from storage on the next authenticated call).
  static String? _cachedToken;
  static String? _cachedRefreshToken;
  // CACHE-02 opt: JWT her getter çağrısında tekrar parse edilmez; O(1) okuma.
  static int? _cachedUserId;

  // ── Cache key yardımcısı (CACHE-02) ──────────────────────────────────────
  /// Aktif kullanıcının ID'siyle namespace'lenmiş api_cache anahtarı döner.
  /// Login öncesi (token yüklenmemiş) 'anon' kullanır; bu durum hassas veri
  /// içermez çünkü auth gerektiren endpoint'ler login sonrası çağrılır.
  static String userScopedKey(String baseKey) {
    final uid = currentUserIdSync ?? 'anon';
    return 'u_${uid}_$baseKey';
  }

  // ── Kasa (Cache) key sabitleri ────────────────────────────────────────────
  // Kullanıcıya özel olanlar static getter — her çağrıda aktif kullanıcı
  // ID'siyle namespace'lenir (CACHE-02). Call site değişmez; Dart syntax aynı.
  static String get cacheMessages         => userScopedKey('cache_messages');
  static String get cacheMessageRequests  => userScopedKey('cache_message_requests');
  static String get cacheNotifications    => userScopedKey('cache_notifications');
  static const cacheFeed                  = 'cache_feed'; // kullanılmıyor; global tutuldu
  static String get cacheProfile          => userScopedKey('cache_profile');
  static String get cacheUserListings     => userScopedKey('cache_user_listings');
  static String get cacheAuctions         => userScopedKey('cache_auctions');
  static String get cacheStreams          => userScopedKey('cache_streams');
  static String get cacheStories          => userScopedKey('cache_stories');
  static String get cacheMyStories        => userScopedKey('cache_my_stories');
  static String get cacheSales            => userScopedKey('cache_sales');
  static String get cacheMyRatingsReceived     => userScopedKey('cache_my_ratings_received');
  static String get cacheMyRatingsGiven        => userScopedKey('cache_my_ratings_given');
  static String get cacheNotificationSettings  => userScopedKey('cache_notification_settings');
  static String get cacheBlockedUsers          => userScopedKey('cache_blocked_users');
  static String get cacheWalletData            => userScopedKey('user_wallet_data');

  // DM thread cache — dinamik anahtarlar (currentUserId + otherUserId) (CACHE-02)
  static String cacheThreadKey(int otherUserId) {
    final uid = currentUserIdSync ?? 'anon';
    return 'u_${uid}_chat_$otherUserId';
  }
  static String cacheDmImageKey(int msgId) {
    final uid = currentUserIdSync ?? 'anon';
    return 'u_${uid}_dm_img_$msgId';
  }
  static String cacheDmThumbKey(int msgId) {
    final uid = currentUserIdSync ?? 'anon';
    return 'u_${uid}_dm_thumb_$msgId';
  }

  /// JWT payload'dan userId ayrıştırır — tek parse noktası.
  static int? _parseUserIdFromToken(String token) {
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

  /// Mevcut oturumdaki kullanıcının ID'sini döner; gerekirse token'ı diskten yükler.
  static Future<int?> getCurrentUserId() async {
    if (_cachedUserId != null) return _cachedUserId;
    await getToken(); // _cachedUserId'yi doldurur
    return _cachedUserId;
  }

  /// In-memory cached userId — await gerektirmez; O(1).
  /// main.dart'taki warm-up çağrısından sonra her zaman doludur.
  static int? get currentUserIdSync => _cachedUserId;

  static const _userEmailKey = 'teqlif_user_email';
  static const _userNameKey = 'teqlif_user_name';
  static const _userFullNameKey = 'teqlif_user_fullname';
  static const _userPremiumKey = 'teqlif_user_premium';
  static const _userPlanTypeKey = 'teqlif_user_plan_type';
  static const _userIdKey = 'teqlif_user_id';
  static const _userOnboardingKey = 'teqlif_user_onboarding';
  static const _userIsVerifiedKey = 'teqlif_user_is_verified';
  static const _userPhoneVerifiedKey = 'teqlif_user_phone_verified';
  static const _userPrivateKey = 'teqlif_is_private';

  static Future<void> saveToken(String token) async {
    _cachedToken = token;
    _cachedUserId = _parseUserIdFromToken(token);
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    // Retry up to 3 times for Android Keystore transient null reads.
    for (var i = 0; i < 3; i++) {
      final v = await _secureStorage.read(key: _tokenKey);
      if (v != null) {
        _cachedToken = v;
        _cachedUserId = _parseUserIdFromToken(v);
        return v;
      }
      if (i < 2) await Future.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  static Future<void> saveRefreshToken(String token) async {
    _cachedRefreshToken = token;
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  static Future<String?> getRefreshToken() async {
    if (_cachedRefreshToken != null) return _cachedRefreshToken;
    for (var i = 0; i < 3; i++) {
      final v = await _secureStorage.read(key: _refreshTokenKey);
      if (v != null) { _cachedRefreshToken = v; return v; }
      if (i < 2) await Future.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  static Future<void> saveUserInfo({
    required int id,
    required String email,
    required String username,
    required String fullName,
    required String userType,
    String? planType,
    bool? onboardingCompleted,
    bool? isVerified,
    bool? phoneVerified,
    bool? isPrivate,
  }) async {
    final futures = <Future<void>>[
      _secureStorage.write(key: _userIdKey, value: id.toString()),
      _secureStorage.write(key: _userEmailKey, value: email),
      _secureStorage.write(key: _userNameKey, value: username),
      _secureStorage.write(key: _userFullNameKey, value: fullName),
      _secureStorage.write(key: _userPremiumKey, value: userType),
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
    if (isPrivate != null) {
      futures.add(_secureStorage.write(key: _userPrivateKey, value: isPrivate.toString()));
    }
    await Future.wait(futures);
  }

  static Future<Map<String, dynamic>?> getUserInfo() async {
    final id = await _secureStorage.read(key: _userIdKey);
    if (id == null) return null;
    final email = await _secureStorage.read(key: _userEmailKey);
    final username = await _secureStorage.read(key: _userNameKey);
    final fullName = await _secureStorage.read(key: _userFullNameKey);
    final userType = await _secureStorage.read(key: _userPremiumKey);
    final planType = await _secureStorage.read(key: _userPlanTypeKey);
    final onboardingCompleted = await _secureStorage.read(key: _userOnboardingKey);
    final isVerified = await _secureStorage.read(key: _userIsVerifiedKey);
    final phoneVerified = await _secureStorage.read(key: _userPhoneVerifiedKey);
    final isPrivate = await _secureStorage.read(key: _userPrivateKey);
    return {
      'id': int.tryParse(id) ?? 0,
      'email': email ?? '',
      'username': username ?? '',
      'full_name': fullName ?? '',
      'user_type': userType ?? 'standard',
      'plan_type': planType,
      'onboarding_completed': onboardingCompleted == 'true',
      'is_verified': isVerified == 'true',
      'phone_verified': phoneVerified == 'true',
      'is_private': isPrivate == 'true',
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
    _cachedToken = null;
    _cachedRefreshToken = null;
    _cachedUserId = null;
    await Future.wait([
      _secureStorage.deleteAll(),
      SharedPreferences.getInstance().then((p) => p.clear()),
      _clearHiveBoxes(),
    ]);
  }

  static Future<void> _clearHiveBoxes() async {
    // homeCache şifresiz; doğrudan açılabilir.
    try {
      if (Hive.isBoxOpen('homeCache')) {
        await Hive.box('homeCache').clear();
      } else {
        await (await Hive.openBox('homeCache')).clear();
      }
    } catch (_) {}
    // api_cache AES-256 şifreli; CacheService'in açık tuttuğu box üzerinden temizle.
    // Hive.openBox('api_cache') şifre anahtarı olmadan çağrılırsa HiveError fırlatır
    // ve catch(_ ){} içinde yutularak logout cache temizliği sessizce başarısız olur.
    try {
      await CacheService.clearBox();
    } catch (_) {}
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

  static const _privacyBannerShownKey = 'teqlif_privacy_banner_shown';

  static Future<bool> getPrivacyBannerShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_privacyBannerShownKey) ?? false;
  }

  static Future<void> setPrivacyBannerShown(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privacyBannerShownKey, val);
  }
}
