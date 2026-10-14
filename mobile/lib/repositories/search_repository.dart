import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:teqlif/core/network/api_client.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

class SearchFeedPage {
  final List<dynamic> listings;
  final bool exhausted;

  const SearchFeedPage({required this.listings, required this.exhausted});
}

class SearchRepository {
  static const _kBoxName   = 'searchCache';
  static const _kKeyForYou = 'search_for_you';
  static const _kKeyRecent = 'search_recent';
  static const _kMaxCached = 60;
  static const _kEntityTtl = Duration(hours: 2);

  final ApiClient _client;
  final CacheService _cache;

  SearchRepository(this._client, this._cache);

  // ── loadMoreForYou — §12.5 + §12.8 ──────────────────────────────────────────

  Future<SearchFeedPage> loadMoreForYou({required int page}) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('unauthenticated');
    final resp = await http.get(
      Uri.parse('${_client.config.baseUrl}/feed/for-you?page=$page'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final data      = jsonDecode(resp.body) as List<dynamic>;
    final exhausted = data.length < 20;
    await _appendCache(_kKeyForYou, data);
    return SearchFeedPage(listings: data, exhausted: exhausted);
  }

  // ── loadMoreRecent — §12.5 + §12.8 ───────────────────────────────────────────

  Future<SearchFeedPage> loadMoreRecent({
    required int page,
    Set<int> excludeIds = const {},
  }) async {
    final token   = await StorageService.getToken();
    final headers = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
    final exclude = excludeIds.isNotEmpty ? '&exclude_ids=${excludeIds.join(',')}' : '';
    final resp    = await http.get(
      Uri.parse('${_client.config.baseUrl}/feed/recent?page=$page$exclude'),
      headers: headers,
    );
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final data      = jsonDecode(resp.body) as List<dynamic>;
    final exhausted = data.length < 20;
    await _appendCache(_kKeyRecent, data);
    return SearchFeedPage(listings: data, exhausted: exhausted);
  }

  // ── Disk Cache ────────────────────────────────────────────────────────────────

  Future<void> _appendCache(String key, List<dynamic> newItems) async {
    try {
      // §12.8 — entity store'a yaz
      for (final item in newItems) {
        final id = (item as Map?)?['id'] as int?;
        if (id != null) {
          await _cache.saveEntity('listing', id,
              Map<String, dynamic>.from(item!), ttl: _kEntityTtl);
        }
      }

      // searchCache box'a ID listesi yaz
      final box      = await Hive.openBox(_kBoxName);
      final existing = _decodeIds(box.get(key) as String?);
      final newIds   = newItems
          .whereType<Map>()
          .map((e) => e['id'] as int?)
          .whereType<int>()
          .toList();
      final merged   = {...existing, ...newIds}.take(_kMaxCached).toList();
      await box.put(key, jsonEncode(merged));
    } catch (_) {}
  }

  List<int> _decodeIds(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).whereType<int>().toList();
    } catch (_) {
      return [];
    }
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  ),
);
