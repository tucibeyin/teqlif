import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Uygulama genelinde kullanılan resim önbelleği.
/// DefaultCacheManager'ın 7 günlük TTL'ini 2 güne düşürür;
/// maksimum 300 dosya tutar.
class TeqlifCacheManager extends CacheManager {
  static const _key = 'teqlifImgCache';

  static final TeqlifCacheManager _instance = TeqlifCacheManager._internal();
  factory TeqlifCacheManager() => _instance;

  TeqlifCacheManager._internal()
      : super(Config(
          _key,
          stalePeriod: const Duration(days: 2),
          maxNrOfCacheObjects: 300,
        ));

  /// URL hash'e bağlı avatar cache anahtarı (CACHE-04).
  /// URL değiştiğinde anahtar değişir → stale avatar sorunu ortadan kalkar.
  static String avatarCacheKey(dynamic userId, String? url) {
    if (url == null || url.isEmpty) return 'user_${userId}_avatar_empty';
    return 'user_${userId}_avatar_${url.hashCode}';
  }
}
