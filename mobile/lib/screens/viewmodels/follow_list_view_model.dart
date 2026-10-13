import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:teqlif/core/network/api_client.dart';
import '../../core/app_exception.dart';
import '../../services/cache_service.dart';
import '../../services/storage_service.dart';

enum FollowListType { followers, following }

class FollowListArgs {
  final int userId;
  final FollowListType type;
  
  const FollowListArgs({required this.userId, required this.type});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowListArgs &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          type == other.type;

  @override
  int get hashCode => userId.hashCode ^ type.hashCode;
}

class FollowListState {
  final List<dynamic> users;
  const FollowListState({this.users = const []});
}

class FollowListViewModel extends AutoDisposeFamilyAsyncNotifier<FollowListState, FollowListArgs> {
  CacheService get _cache => ref.read(cacheServiceProvider);

  Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String _cacheKey(FollowListArgs arg) =>
      'follow_list_${arg.userId}_${arg.type.name}';

  @override
  FutureOr<FollowListState> build(FollowListArgs arg) async {
    // SWR: cache varsa hemen göster
    final cached = _cache.getData(_cacheKey(arg));
    if (cached != null) {
      state = AsyncValue.data(FollowListState(users: cached as List));
    }

    final segment = arg.type == FollowListType.followers ? 'followers' : 'following';
    final headers = await _authHeaders();
    final resp = await http.get(
      Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/follows/${arg.userId}/$segment'),
      headers: headers,
    );
    if (resp.statusCode == 200) {
      final users = jsonDecode(resp.body) as List;
      await _cache.saveData(_cacheKey(arg), users,
          ttl: const Duration(minutes: 5));
      return FollowListState(users: users);
    } else {
      if (cached != null) return state.value!; // ağ hatası — cache'i koru
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>? ?? {};
      throw AppException(
        err['message'] as String? ?? '',
        code: err['code'] as String? ?? 'ERR_UNKNOWN',
        statusCode: resp.statusCode,
      );
    }
  }

  Future<void> toggleFollow(int index) async {
    final currentState = state.value;
    if (currentState == null) return;
    
    final users = List<Map<String, dynamic>>.from(currentState.users.map((u) => Map<String, dynamic>.from(u as Map)));
    final user = users[index];
    final isFollowing = user['is_following'] as bool;
    final userId = user['id'] as int;

    // Optimistic update
    users[index]['is_following'] = !isFollowing;
    state = AsyncValue.data(FollowListState(users: users));

    try {
      final headers = await _authHeaders();
      final uri = Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/follows/$userId');
      final resp = isFollowing
          ? await http.delete(uri, headers: headers)
          : await http.post(uri, headers: headers);
      
      if (resp.statusCode >= 400) {
        users[index]['is_following'] = isFollowing;
        state = AsyncValue.data(FollowListState(users: users));
      } else {
        await _cache.saveData(_cacheKey(arg), users,
            ttl: const Duration(minutes: 5));
      }
    } catch (_) {
      users[index]['is_following'] = isFollowing;
      state = AsyncValue.data(FollowListState(users: users));
    }
  }
}

final followListProvider = AsyncNotifierProvider.autoDispose.family<FollowListViewModel, FollowListState, FollowListArgs>(
  () => FollowListViewModel(),
);
