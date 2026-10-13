import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/network/api_client.dart';
import '../../services/cache_service.dart';
import '../../services/storage_service.dart';

class BlockedUsersState {
  final List<dynamic> blockedUsers;
  const BlockedUsersState({this.blockedUsers = const []});
}

class BlockedUsersViewModel extends AutoDisposeAsyncNotifier<BlockedUsersState> {
  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return ref.read(apiClientProvider).buildApiHeaders(token, json: true);
  }

  @override
  FutureOr<BlockedUsersState> build() async {
    // SWR: cache varsa hemen göster
    final cached = CacheService.getData(StorageService.cacheBlockedUsers);
    if (cached != null) {
      state = AsyncValue.data(BlockedUsersState(blockedUsers: cached as List));
    }

    final resp = await http.get(
      Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/users/blocked'),
      headers: await _headers(),
    );
    if (resp.statusCode == 200) {
      final users = jsonDecode(resp.body) as List;
      await CacheService.saveData(StorageService.cacheBlockedUsers, users,
          ttl: const Duration(minutes: 10));
      return BlockedUsersState(blockedUsers: users);
    } else {
      if (cached != null) return state.value!;
      throw Exception('Failed to load blocked users');
    }
  }

  Future<void> unblock(String username, int userId) async {
    try {
      final resp = await http.delete(
        Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/users/${Uri.encodeComponent(username)}/block'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200 || resp.statusCode == 404) {
        final current = state.value;
        if (current != null) {
          final updated = List.from(current.blockedUsers)..removeWhere((u) => u['id'] == userId);
          state = AsyncValue.data(BlockedUsersState(blockedUsers: updated));
          await CacheService.saveData(StorageService.cacheBlockedUsers, updated,
              ttl: const Duration(minutes: 10));
        }
      } else {
        throw Exception('Failed to unblock');
      }
    } catch (e) {
      throw Exception('Unblock failed');
    }
  }
}

final blockedUsersProvider = AsyncNotifierProvider.autoDispose<BlockedUsersViewModel, BlockedUsersState>(
  () => BlockedUsersViewModel(),
);
