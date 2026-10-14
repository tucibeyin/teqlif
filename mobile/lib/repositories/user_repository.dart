import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/network/api_client.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';

enum FollowListType { followers, following }

class UserRepository {
  final ApiClient _client;
  final ApiService _api;
  final CacheService _cache;

  UserRepository(this._client, this._api, this._cache);

  // ── Senkron cache okuma — ViewModel build() için ─────────────────────────

  dynamic getCachedBlockedUsers() =>
      _cache.getWithStaleness(StorageService.cacheBlockedUsers)?.data;

  dynamic getCachedFollowList(int userId, FollowListType type) =>
      _cache.getWithStaleness(_followKey(userId, type))?.data;

  // ── Blocked users ────────────────────────────────────────────────────────

  Stream<List<dynamic>> getBlockedUsers() => _api.get<List<dynamic>>(
        url: '${_client.config.baseUrl}/users/blocked',
        cacheKey: StorageService.cacheBlockedUsers,
        fromJson: (raw) => raw as List,
        cacheTtl: const Duration(minutes: 30),
      );

  Future<void> unblockUser(String username) async {
    final token = await StorageService.getToken();
    final headers = await _client.buildApiHeaders(token);
    await _client.call(
      () => http.delete(
        Uri.parse('${_client.config.baseUrl}/users/${Uri.encodeComponent(username)}/block'),
        headers: headers,
      ),
    );
    await _cache.clearData(StorageService.cacheBlockedUsers);
  }

  // ── Follow list ──────────────────────────────────────────────────────────

  Stream<List<dynamic>> getFollowList(int userId, FollowListType type) {
    final segment = type == FollowListType.followers ? 'followers' : 'following';
    return _api.get<List<dynamic>>(
      url: '${_client.config.baseUrl}/follows/$userId/$segment',
      cacheKey: _followKey(userId, type),
      fromJson: (raw) => raw as List,
      cacheTtl: const Duration(minutes: 15),
    );
  }

  Future<bool> toggleFollow(int userId, {required bool isFollowing}) async {
    final token = await StorageService.getToken();
    final headers = await _client.buildApiHeaders(token);
    final uri = Uri.parse('${_client.config.baseUrl}/follows/$userId');
    await _client.call(
      () => isFollowing
          ? http.delete(uri, headers: headers)
          : http.post(uri, headers: headers),
    );
    // Follow listesi değişti — her iki type'ı invalidate et
    await Future.wait([
      _cache.clearData(_followKey(userId, FollowListType.followers)),
      _cache.clearData(_followKey(userId, FollowListType.following)),
    ]);
    return true;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _followKey(int userId, FollowListType type) =>
      'follow_list_${userId}_${type.name}';
}

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository(
      ref.watch(apiClientProvider),
      ref.watch(apiServiceProvider),
      ref.watch(cacheServiceProvider),
    ));
