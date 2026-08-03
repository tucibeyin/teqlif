import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';

class FollowRequestsState {
  final List<dynamic> receivedRequests;
  final List<dynamic> sentRequests;

  const FollowRequestsState({
    this.receivedRequests = const [],
    this.sentRequests = const [],
  });
}

class FollowRequestsViewModel extends AutoDisposeAsyncNotifier<FollowRequestsState> {
  @override
  FutureOr<FollowRequestsState> build() async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Unauthenticated');
    }

    final futures = await Future.wait([
      http.get(
        Uri.parse('$kBaseUrl/follows/requests'),
        headers: {'Authorization': 'Bearer $token'},
      ),
      http.get(
        Uri.parse('$kBaseUrl/follows/requests/sent'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    ]);

    if (futures[0].statusCode == 200 && futures[1].statusCode == 200) {
      return FollowRequestsState(
        receivedRequests: jsonDecode(futures[0].body) as List,
        sentRequests: jsonDecode(futures[1].body) as List,
      );
    } else {
      throw Exception('Failed to load requests');
    }
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    try {
      final token = await StorageService.getToken();
      if (token == null) throw Exception('Unauthenticated');

      final futures = await Future.wait([
        http.get(
          Uri.parse('$kBaseUrl/follows/requests'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(
          Uri.parse('$kBaseUrl/follows/requests/sent'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);

      if (futures[0].statusCode == 200 && futures[1].statusCode == 200) {
        state = AsyncValue.data(FollowRequestsState(
          receivedRequests: jsonDecode(futures[0].body) as List,
          sentRequests: jsonDecode(futures[1].body) as List,
        ));
      } else {
        state = AsyncValue.error(Exception('Failed to load'), StackTrace.current);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> handleReceivedAction(int followerId, String action) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) throw Exception('Unauthenticated');
      
      final uri = Uri.parse('$kBaseUrl/follows/$followerId/$action');
      final resp = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (resp.statusCode == 200) {
        final current = state.value;
        if (current != null) {
          final updatedReceived = List.from(current.receivedRequests)
            ..removeWhere((req) => req['id'] == followerId);
          state = AsyncValue.data(FollowRequestsState(
            receivedRequests: updatedReceived,
            sentRequests: current.sentRequests,
          ));
        }
      } else {
        throw Exception('Action failed');
      }
    } catch (e) {
      throw Exception('Action failed');
    }
  }

  Future<void> handleSentWithdraw(int targetUserId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) throw Exception('Unauthenticated');
      
      final uri = Uri.parse('$kBaseUrl/follows/$targetUserId');
      final resp = await http.delete(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (resp.statusCode == 200) {
        final current = state.value;
        if (current != null) {
          final updatedSent = List.from(current.sentRequests)
            ..removeWhere((req) => req['id'] == targetUserId);
          state = AsyncValue.data(FollowRequestsState(
            receivedRequests: current.receivedRequests,
            sentRequests: updatedSent,
          ));
        }
      } else {
        throw Exception('Action failed');
      }
    } catch (e) {
      throw Exception('Action failed');
    }
  }
}

final followRequestsProvider = AsyncNotifierProvider.autoDispose<FollowRequestsViewModel, FollowRequestsState>(
  () => FollowRequestsViewModel(),
);
