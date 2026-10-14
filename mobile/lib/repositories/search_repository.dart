import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:teqlif/core/network/api_client.dart';
import '../services/storage_service.dart';

class SearchFeedPage {
  final List<dynamic> listings;
  final bool exhausted;

  const SearchFeedPage({required this.listings, required this.exhausted});
}

class SearchRepository {
  static const _kBoxName         = 'searchCache';
  static const _kKeyForYou       = 'search_for_you';
  static const _kKeyRecent       = 'search_recent';
  static const _kMaxCached       = 60;

  final ApiClient _client;

  SearchRepository(this._client);

  // ── loadMoreForYou — §12.5 disk kalıcılığı ───────────────────────────────────

  Future<SearchFeedPage> loadMoreForYou({required int page}) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('unauthenticated');
    final resp = await http.get(
      Uri.parse('${_client.config.baseUrl}/feed/for-you?page=$page'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final data       = jsonDecode(resp.body) as List<dynamic>;
    final exhausted  = data.length < 20;
    await _appendCache(_kKeyForYou, data);
    return SearchFeedPage(listings: data, exhausted: exhausted);
  }

  // ── loadMoreRecent — §12.5 disk kalıcılığı ───────────────────────────────────

  Future<SearchFeedPage> loadMoreRecent({
    required int page,
    Set<int> excludeIds = const {},
  }) async {
    final token      = await StorageService.getToken();
    final headers    = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
    final exclude    = excludeIds.isNotEmpty ? '&exclude_ids=${excludeIds.join(',')}' : '';
    final url        = '${_client.config.baseUrl}/feed/recent?page=$page$exclude';
    final resp       = await http.get(Uri.parse(url), headers: headers);
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    final data       = jsonDecode(resp.body) as List<dynamic>;
    final exhausted  = data.length < 20;
    await _appendCache(_kKeyRecent, data);
    return SearchFeedPage(listings: data, exhausted: exhausted);
  }

  // ── Disk Cache ────────────────────────────────────────────────────────────────

  Future<void> _appendCache(String key, List<dynamic> newItems) async {
    try {
      final box      = await Hive.openBox(_kBoxName);
      final existing = _decodeList(box.get(key) as String?);
      final merged   = [...existing, ...newItems]
          .fold<List<dynamic>>([], (acc, e) =>
              acc.any((x) => x['id'] == e['id']) ? acc : [...acc, e])
          .take(_kMaxCached)
          .toList();
      await box.put(key, jsonEncode(merged));
    } catch (_) {}
  }

  List<dynamic> _decodeList(String? raw) {
    if (raw == null) return [];
    try { return jsonDecode(raw) as List<dynamic>; } catch (_) { return []; }
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(apiClientProvider)),
);
