import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
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
  Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  FutureOr<FollowListState> build(FollowListArgs arg) async {
    final segment = arg.type == FollowListType.followers ? 'followers' : 'following';
    final headers = await _authHeaders();
    final resp = await http.get(
      Uri.parse('$kBaseUrl/follows/${arg.userId}/$segment'),
      headers: headers,
    );
    if (resp.statusCode == 200) {
      return FollowListState(users: jsonDecode(resp.body) as List);
    } else {
      throw Exception('Failed to load');
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
      final uri = Uri.parse('$kBaseUrl/follows/$userId');
      final resp = isFollowing
          ? await http.delete(uri, headers: headers)
          : await http.post(uri, headers: headers);
      
      if (resp.statusCode >= 400) {
        // Revert on error
        users[index]['is_following'] = isFollowing;
        state = AsyncValue.data(FollowListState(users: users));
      }
    } catch (_) {
      // Revert on error
      users[index]['is_following'] = isFollowing;
      state = AsyncValue.data(FollowListState(users: users));
    }
  }
}

final followListProvider = AsyncNotifierProvider.autoDispose.family<FollowListViewModel, FollowListState, FollowListArgs>(
  () => FollowListViewModel(),
);
