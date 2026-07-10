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
}
