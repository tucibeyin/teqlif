import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/network/api_client.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

class RatingsRepository {
  final ApiClient _client;
  final ApiService _api;
  final CacheService _cache;

  RatingsRepository(this._client, this._api, this._cache);

  // ── Senkron cache okuma ──────────────────────────────────────────────────

  dynamic getCachedReceived() =>
      _cache.getWithStaleness(StorageService.cacheMyRatingsReceived)?.data;

  dynamic getCachedGiven() =>
      _cache.getWithStaleness(StorageService.cacheMyRatingsGiven)?.data;

  // ── Queries ──────────────────────────────────────────────────────────────

  Stream<List<dynamic>> getReceivedRatings() => _api.get<List<dynamic>>(
        url: '${_client.config.baseUrl}/ratings/me/received',
        cacheKey: StorageService.cacheMyRatingsReceived,
        fromJson: (raw) => raw as List,
        cacheTtl: const Duration(minutes: 30),
      );

  Stream<List<dynamic>> getGivenRatings() => _api.get<List<dynamic>>(
        url: '${_client.config.baseUrl}/ratings/me/given',
        cacheKey: StorageService.cacheMyRatingsGiven,
        fromJson: (raw) => raw as List,
        cacheTtl: const Duration(minutes: 30),
      );

  // ── Mutations ────────────────────────────────────────────────────────────

  Future<void> markAsRead() async {
    final token = await StorageService.getToken();
    final headers = await _client.buildApiHeaders(token);
    await _client.call(
      () => http.patch(
        Uri.parse('${_client.config.baseUrl}/ratings/me/mark-read'),
        headers: headers,
      ),
    );
  }

  Future<bool> submitReply(int ratingId, String text) async {
    final token = await StorageService.getToken();
    final headers = await _client.buildApiHeaders(token, json: true);
    await _client.call(
      () => http.post(
        Uri.parse('${_client.config.baseUrl}/ratings/reply/$ratingId'),
        headers: headers,
        body: jsonEncode({'reply': text}),
      ),
    );
    await Future.wait([
      _cache.clearData(StorageService.cacheMyRatingsReceived),
      _cache.clearData(StorageService.cacheMyRatingsGiven),
    ]);
    return true;
  }

  Future<bool> saveRating(int userId, int score, String? comment) async {
    final token = await StorageService.getToken();
    final headers = await _client.buildApiHeaders(token, json: true);
    await _client.call(
      () => http.post(
        Uri.parse('${_client.config.baseUrl}/ratings/$userId'),
        headers: headers,
        body: jsonEncode({
          'score': score,
          'comment': comment?.isEmpty == true ? null : comment,
        }),
      ),
    );
    await Future.wait([
      _cache.clearData(StorageService.cacheMyRatingsReceived),
      _cache.clearData(StorageService.cacheMyRatingsGiven),
    ]);
    return true;
  }
}

final ratingsRepositoryProvider = Provider<RatingsRepository>((ref) => RatingsRepository(
      ref.watch(apiClientProvider),
      ref.watch(apiServiceProvider),
      ref.watch(cacheServiceProvider),
    ));
