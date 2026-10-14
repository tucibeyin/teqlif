import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/network/api_client.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

class NotificationPrefsRepository {
  final ApiClient _client;
  final ApiService _api;
  final CacheService _cache;

  NotificationPrefsRepository(this._client, this._api, this._cache);

  // ── Senkron cache okuma ──────────────────────────────────────────────────

  dynamic getCached() =>
      _cache.getWithStaleness(StorageService.cacheNotificationSettings)?.data;

  // ── Query ────────────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> getPrefs() => _api.get<Map<String, dynamic>>(
        url: '${_client.config.baseUrl}/auth/notification-prefs',
        cacheKey: StorageService.cacheNotificationSettings,
        fromJson: (raw) => Map<String, dynamic>.from(raw as Map),
        cacheTtl: const Duration(hours: 1),
      );

  // ── Mutation ─────────────────────────────────────────────────────────────

  Future<void> patchPrefs(Map<String, dynamic> payload) async {
    final token = await StorageService.getToken();
    final headers = await _client.buildApiHeaders(token, json: true);
    await _client.call(
      () => http.patch(
        Uri.parse('${_client.config.baseUrl}/auth/notification-prefs'),
        headers: headers,
        body: jsonEncode(payload),
      ),
    );
    await _cache.clearData(StorageService.cacheNotificationSettings);
  }
}

final notificationPrefsRepositoryProvider =
    Provider<NotificationPrefsRepository>((ref) => NotificationPrefsRepository(
          ref.watch(apiClientProvider),
          ref.watch(apiServiceProvider),
          ref.watch(cacheServiceProvider),
        ));
