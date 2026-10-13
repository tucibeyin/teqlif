import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HomeCache {
  final List<dynamic> recentListings;
  final List<dynamic> hesitatedListings;
  final int totalPages;

  const HomeCache({
    required this.recentListings,
    required this.hesitatedListings,
    required this.totalPages,
  });
}

class HomeRepository {
  static const _kBoxName           = 'homeCache';
  static const _kKeyFeed           = 'home_feed_recent';
  static const _kKeyHesitated      = 'feed_hesitated';
  static const _kKeyVersion        = 'home_cache_version';
  static const _kKeyTimestamp      = 'home_cache_timestamp';
  static const _kCacheVersion      = 2;
  static const _kCacheTtlMs        = 30 * 60 * 1000;

  Future<Box> _box() => Hive.openBox(_kBoxName);

  /// Geçerli cache'i döner. TTL dolmuş, versiyon farklı veya boşsa null.
  Future<HomeCache?> loadCache() async {
    try {
      final box = await _box();
      final version = box.get(_kKeyVersion) as int?;
      if (version != _kCacheVersion) {
        await _reset(box);
        return null;
      }
      final savedAt = box.get(_kKeyTimestamp) as int?;
      if (savedAt != null) {
        final age = DateTime.now().millisecondsSinceEpoch - savedAt;
        if (age > _kCacheTtlMs) {
          await _reset(box);
          return null;
        }
      }
      final feedRaw      = box.get(_kKeyFeed) as String?;
      final hesitatedRaw = box.get(_kKeyHesitated) as String?;
      if (feedRaw == null) return null;

      List<dynamic> recent   = [];
      int totalPages         = 1;
      List<dynamic> hesitated = [];

      try {
        final parsed = jsonDecode(feedRaw);
        if (parsed is List) {
          recent = parsed;
        } else {
          recent     = (parsed['listings'] ?? []) as List<dynamic>;
          totalPages = parsed['pagination']?['total_pages'] ?? 1;
        }
      } catch (_) {}

      if (hesitatedRaw != null) {
        try {
          hesitated = jsonDecode(hesitatedRaw) as List<dynamic>;
        } catch (_) {}
      }

      return HomeCache(
        recentListings:    recent,
        hesitatedListings: hesitated,
        totalPages:        totalPages,
      );
    } catch (_) {
      return null;
    }
  }

  /// Yeni feed JSON'ını ve timestamp'i kaydeder.
  Future<void> saveFeed(String feedJson) async {
    final box = await _box();
    await box.put(_kKeyFeed, feedJson);
    await box.put(_kKeyVersion, _kCacheVersion);
    await box.put(_kKeyTimestamp, DateTime.now().millisecondsSinceEpoch);
  }

  /// Hesitated feed JSON'ını kaydeder.
  Future<void> saveHesitated(String json) => _box().then((b) => b.put(_kKeyHesitated, json));

  /// Mevcut feed listesine yeni ilanları başa ekleyerek kaydeder.
  Future<void> prependFeed(List<dynamic> prepended) async {
    final box = await _box();
    await box.put(_kKeyFeed, jsonEncode(prepended));
    await box.put(_kKeyTimestamp, DateTime.now().millisecondsSinceEpoch);
  }

  /// Cache'i temizler ve versiyon numarasını sıfırlar.
  Future<void> clearCache() async {
    final box = await _box();
    await _reset(box);
  }

  Future<void> _reset(Box box) async {
    await box.clear();
    await box.put(_kKeyVersion, _kCacheVersion);
  }
}

final homeRepositoryProvider = Provider<HomeRepository>((_) => HomeRepository());
