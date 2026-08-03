import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';

class MyRatingsState {
  final List<dynamic> receivedRatings;
  final List<dynamic> givenRatings;

  const MyRatingsState({
    this.receivedRatings = const [],
    this.givenRatings = const [],
  });
}

class MyRatingsViewModel extends AutoDisposeAsyncNotifier<MyRatingsState> {
  @override
  FutureOr<MyRatingsState> build() async {
    _markAsRead(); // fire and forget
    return _fetchRatings();
  }

  Future<void> _markAsRead() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.patch(
        Uri.parse('$kBaseUrl/ratings/me/mark-read'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {}
  }

  Future<MyRatingsState> _fetchRatings() async {
    final token = await StorageService.getToken();
    if (token == null) return const MyRatingsState();
    
    final futures = await Future.wait([
      http.get(Uri.parse('$kBaseUrl/ratings/me/received'), headers: {'Authorization': 'Bearer $token'}),
      http.get(Uri.parse('$kBaseUrl/ratings/me/given'), headers: {'Authorization': 'Bearer $token'}),
    ]);
    
    List<dynamic> received = [];
    List<dynamic> given = [];
    
    if (futures[0].statusCode == 200) {
      received = jsonDecode(futures[0].body);
    }
    if (futures[1].statusCode == 200) {
      given = jsonDecode(futures[1].body);
    }
    return MyRatingsState(receivedRatings: received, givenRatings: given);
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchRatings());
  }

  Future<bool> submitReply(int ratingId, String text) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return false;
      final resp = await http.post(
        Uri.parse('$kBaseUrl/ratings/reply/$ratingId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reply': text}),
      );
      if (resp.statusCode == 200) {
        reload();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveRating(int userId, int score, String? comment) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return false;
      final resp = await http.post(
        Uri.parse('$kBaseUrl/ratings/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'score': score,
          'comment': comment?.isEmpty == true ? null : comment,
        }),
      );
      if (resp.statusCode == 200) {
        reload();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

final myRatingsProvider = AsyncNotifierProvider.autoDispose<MyRatingsViewModel, MyRatingsState>(
  MyRatingsViewModel.new,
);
