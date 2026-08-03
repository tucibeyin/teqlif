import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';

class BlockedUsersState {
  final List<dynamic> blockedUsers;
  const BlockedUsersState({this.blockedUsers = const []});
}

class BlockedUsersViewModel extends AutoDisposeAsyncNotifier<BlockedUsersState> {
  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return buildApiHeaders(token, json: true);
  }

  @override
  FutureOr<BlockedUsersState> build() async {
    final resp = await http.get(
      Uri.parse('$kBaseUrl/users/blocked'),
      headers: await _headers(),
    );
    if (resp.statusCode == 200) {
      return BlockedUsersState(blockedUsers: jsonDecode(resp.body) as List);
    } else {
      throw Exception('Failed to load blocked users');
    }
  }

  Future<void> unblock(String username, int userId) async {
    try {
      final resp = await http.delete(
        Uri.parse('$kBaseUrl/users/${Uri.encodeComponent(username)}/block'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200 || resp.statusCode == 404) {
        final current = state.value;
        if (current != null) {
          final updated = List.from(current.blockedUsers)..removeWhere((u) => u['id'] == userId);
          state = AsyncValue.data(BlockedUsersState(blockedUsers: updated));
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
