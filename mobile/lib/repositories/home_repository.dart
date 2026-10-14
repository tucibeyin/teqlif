import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:teqlif/core/network/api_client.dart';
import '../models/listing_filter_state.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

class HomeFeedPage {
  final List<dynamic> listings;
  final int totalPages;
  final int? minId;

  const HomeFeedPage({
    required this.listings,
    required this.totalPages,
    this.minId,
  });
}

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
  static const _kBoxName      = 'homeCache';
  static const _kKeyFeed      = 'home_feed_recent';
  static const _kKeyHesitated = 'feed_hesitated';
  static const _kKeyVersion   = 'home_cache_version';
  static const _kKeyTimestamp = 'home_cache_timestamp';
  // §12.8 — bumped to 3: homeCache now stores ID lists, entities in api_cache
  static const _kCacheVersion = 3;
  static const _kCacheTtlMs   = 15 * 60 * 1000;
  static const _kMaxCached    = 60; // 3 sayfa × 20 ilan
  static const _kEntityTtl    = Duration(hours: 2);

  final ApiClient _client;
  final CacheService _cache;

  HomeRepository(this._client, this._cache);

  // ── HTTP ─────────────────────────────────────────────────────────────────────

  Future<HomeFeedPage> fetchRecent({int page = 0}) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('unauthenticated');
    final uri = Uri.parse('${_client.config.baseUrl}/feed/recent?page=$page');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    return _parsePage(resp.body, page);
  }

  Future<HomeFeedPage> fetchSinceId(int sinceId) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('unauthenticated');
    final uri = Uri.parse('${_client.config.baseUrl}/feed/recent?since_id=$sinceId');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    return _parsePage(resp.body, 0);
  }

  Future<List<dynamic>> fetchHesitated() async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    final uri = Uri.parse('${_client.config.baseUrl}/feed/hesitated');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode != 200) return [];
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchFiltered(ListingFilterState filter) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('unauthenticated');
    final params = <String, String>{};
    if (filter.category != null)    params['category']    = filter.category!;
    if (filter.subcategory != null) params['subcategory'] = filter.subcategory!;
    if (filter.city != null)        params['location']    = filter.city!;
    if (filter.condition != null)   params['condition']   = filter.condition!;
    if (filter.sortBy != null)      params['sort_by']     = filter.sortBy!;
    if (filter.minPrice != null)    params['min_price']   = filter.minPrice!.toStringAsFixed(0);
    if (filter.maxPrice != null)    params['max_price']   = filter.maxPrice!.toStringAsFixed(0);
    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      params['q'] = filter.searchQuery!;
    }
    if (filter.dateFrom != null) {
      params['date_from'] = filter.dateFrom!.toIso8601String().substring(0, 10);
    }
    if (filter.dateTo != null) {
      params['date_to'] = filter.dateTo!.toIso8601String().substring(0, 10);
    }
    final uri = Uri.parse('${_client.config.baseUrl}/listings')
        .replace(queryParameters: params);
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    return jsonDecode(resp.body) as List<dynamic>;
  }

  // §12.5 + §12.8 — Merged listeyi diske yazar (entity store + ID listesi).
  Future<HomeFeedPage> loadMore({required int page, int? maxId}) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('unauthenticated');
    final uri = maxId != null
        ? Uri.parse('${_client.config.baseUrl}/feed/recent?max_id=$maxId')
        : Uri.parse('${_client.config.baseUrl}/feed/recent?page=$page');
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

    final feedPage = _parsePage(resp.body, page);
    final existing = (await loadCache())?.recentListings ?? <dynamic>[];
    final merged   = [...existing, ...feedPage.listings]
        .fold<List<dynamic>>([], (acc, e) =>
            acc.any((x) => x['id'] == e['id']) ? acc : [...acc, e])
        .take(_kMaxCached)
        .toList();
    await saveFeed(merged);

    return feedPage;
  }

  Future<void> deleteHesitated(int listingId) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.delete(
        Uri.parse('${_client.config.baseUrl}/feed/hesitated/$listingId'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
    } catch (_) {}
  }

  // ── Disk Cache (§12.8 — ID-list format) ──────────────────────────────────────

  Future<Box> _box() => Hive.openBox(_kBoxName);

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

      // §12.8 — ID listesini entity store'dan resolve et
      final decoded       = jsonDecode(feedRaw) as List<dynamic>;
      final List<dynamic> recent;
      if (decoded.isNotEmpty && decoded.first is int) {
        // Yeni format: ID listesi → entity store'dan resolve
        recent = decoded
            .whereType<int>()
            .map((id) => _cache.getEntity('listing', id))
            .whereType<Map<String, dynamic>>()
            .toList();
      } else {
        // Eski format: tam JSON (migration sonrası bu dal kullanılmaz)
        recent = decoded;
      }

      List<dynamic> hesitated = [];
      if (hesitatedRaw != null) {
        try {
          hesitated = jsonDecode(hesitatedRaw) as List<dynamic>;
        } catch (_) {}
      }

      return HomeCache(
        recentListings:    recent,
        hesitatedListings: hesitated,
        totalPages:        1,
      );
    } catch (_) {
      return null;
    }
  }

  // §12.8 — Listing listesini entity store'a yazar; homeCache'e ID listesi saklar.
  Future<void> saveFeed(List<dynamic> listings) async {
    final ids = <int>[];
    for (final item in listings) {
      final map = item as Map?;
      final id  = map?['id'] as int?;
      if (id != null) {
        ids.add(id);
        await _cache.saveEntity(
          'listing', id, Map<String, dynamic>.from(map!),
          ttl: _kEntityTtl,
        );
      }
    }
    final box = await _box();
    await box.put(_kKeyFeed, jsonEncode(ids));
    await box.put(_kKeyVersion, _kCacheVersion);
    await box.put(_kKeyTimestamp, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> saveHesitated(List<dynamic> items) =>
      _box().then((b) => b.put(_kKeyHesitated, jsonEncode(items)));

  Future<void> prependFeed(List<dynamic> prepended) async {
    await saveFeed(prepended);
  }

  Future<void> clearCache() async {
    final box = await _box();
    await _reset(box);
  }

  Future<void> _reset(Box box) async {
    await box.clear();
    await box.put(_kKeyVersion, _kCacheVersion);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  HomeFeedPage _parsePage(String body, int page) {
    final parsed = jsonDecode(body);
    final listings = parsed is List
        ? parsed
        : ((parsed['listings'] ?? []) as List<dynamic>);
    final totalPages = parsed is List
        ? (listings.length < 20 ? page : 9999)
        : ((parsed['pagination']?['total_pages'] ?? 1) as int);
    final minId = listings.isNotEmpty
        ? listings.map((e) => e['id'] as int).reduce((a, b) => a < b ? a : b)
        : null;
    return HomeFeedPage(listings: listings, totalPages: totalPages, minId: minId);
  }
}

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  ),
);
