import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';
import '../../services/notification_service.dart';
import '../../models/listing_filter_state.dart';

class PublicProfileArgs {
  final String username;
  final int? userId;
  const PublicProfileArgs({required this.username, this.userId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileArgs &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          userId == other.userId;

  @override
  int get hashCode => username.hashCode ^ userId.hashCode;
}

class PublicProfileState {
  final Map<String, dynamic>? user;
  final List<dynamic> listings;
  final bool isOwnProfile;
  final String followStatus;
  final bool isPrivate;
  final bool isBlocked;
  final bool canCall;
  final String? canCallReason;
  final Map<String, dynamic>? ratingSummary;
  final ListingFilterState filter;
  final bool followLoading;

  const PublicProfileState({
    this.user,
    this.listings = const [],
    this.isOwnProfile = false,
    this.followStatus = 'none',
    this.isPrivate = false,
    this.isBlocked = false,
    this.canCall = false,
    this.canCallReason,
    this.ratingSummary,
    this.filter = const ListingFilterState(),
    this.followLoading = false,
  });

  PublicProfileState copyWith({
    Map<String, dynamic>? user,
    List<dynamic>? listings,
    bool? isOwnProfile,
    String? followStatus,
    bool? isPrivate,
    bool? isBlocked,
    bool? canCall,
    String? canCallReason,
    Map<String, dynamic>? ratingSummary,
    ListingFilterState? filter,
    bool? followLoading,
  }) {
    return PublicProfileState(
      user: user ?? this.user,
      listings: listings ?? this.listings,
      isOwnProfile: isOwnProfile ?? this.isOwnProfile,
      followStatus: followStatus ?? this.followStatus,
      isPrivate: isPrivate ?? this.isPrivate,
      isBlocked: isBlocked ?? this.isBlocked,
      canCall: canCall ?? this.canCall,
      canCallReason: canCallReason ?? this.canCallReason,
      ratingSummary: ratingSummary ?? this.ratingSummary,
      filter: filter ?? this.filter,
      followLoading: followLoading ?? this.followLoading,
    );
  }
}

class PublicProfileViewModel extends AutoDisposeFamilyAsyncNotifier<PublicProfileState, PublicProfileArgs> {
  Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  FutureOr<PublicProfileState> build(PublicProfileArgs arg) async {
    final data = await NotificationService.getUserByUsername(arg.username);
    final info = await StorageService.getUserInfo();
    final isOwn = info != null && info['username'] == arg.username;

    List<dynamic> listings = [];
    String followStatus = 'none';
    bool isPrivate = false;
    bool isBlocked = false;
    bool canCall = false;
    String? canCallReason;
    Map<String, dynamic>? ratingSummary;

    if (data != null) {
      final userId = data['id'] as int;

      try {
        final headers = await _authHeaders();
        final resp = await http.get(
          Uri.parse('$kBaseUrl/listings?user_id=$userId'),
          headers: headers,
        );
        if (resp.statusCode == 200) listings = jsonDecode(resp.body) as List;
      } catch (_) {}

      if (!isOwn && info != null) {
        followStatus = (data['follow_status'] as String?) ?? 'none';
        isPrivate = (data['is_private'] as bool?) ?? false;
        isBlocked = (data['is_blocked'] as bool?) ?? false;
        canCall = (data['can_call'] as bool?) ?? false;
        canCallReason = data['can_call_reason'] as String?;
      }

      try {
        final headers = await _authHeaders();
        final resp = await http.get(
          Uri.parse('$kBaseUrl/ratings/$userId/summary'),
          headers: headers,
        );
        if (resp.statusCode == 200) {
          ratingSummary = jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (_) {}
    }

    return PublicProfileState(
      user: data,
      listings: listings,
      isOwnProfile: isOwn,
      followStatus: followStatus,
      isPrivate: isPrivate,
      isBlocked: isBlocked,
      canCall: canCall,
      canCallReason: canCallReason,
      ratingSummary: ratingSummary,
    );
  }

  void updateFilter(ListingFilterState filter) {
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(filter: filter));
    }
  }

  Future<void> reloadRatingSummary() async {
    final current = state.value;
    if (current == null || current.user == null) return;
    final userId = current.user!['id'] as int;
    
    try {
      final headers = await _authHeaders();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/ratings/$userId/summary'),
        headers: headers,
      );
      if (resp.statusCode == 200) {
        state = AsyncValue.data(current.copyWith(
          ratingSummary: jsonDecode(resp.body) as Map<String, dynamic>,
        ));
      }
    } catch (_) {}
  }

  Future<void> toggleFollow() async {
    final current = state.value;
    if (current == null || current.user == null) return;
    
    state = AsyncValue.data(current.copyWith(followLoading: true));
    
    final userId = current.user!['id'] as int;
    try {
      final headers = await _authHeaders();
      String newStatus = current.followStatus;
      if (current.followStatus != 'none') {
        await http.delete(
          Uri.parse('$kBaseUrl/follows/$userId'),
          headers: headers,
        );
        newStatus = 'none';
      } else {
        final resp = await http.post(
          Uri.parse('$kBaseUrl/follows/$userId'),
          headers: headers,
        );
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          newStatus = body['status'] as String? ?? 'accepted';
        }
      }
      
      final fresh = await NotificationService.getUserByUsername(arg.username);
      
      final st = state.value;
      if (st != null) {
        state = AsyncValue.data(st.copyWith(
          followStatus: newStatus,
          user: fresh,
          followLoading: false,
        ));
      }
    } catch (_) {
      final st = state.value;
      if (st != null) {
        state = AsyncValue.data(st.copyWith(followLoading: false));
      }
    }
  }

  Future<void> toggleBlock() async {
    final current = state.value;
    if (current == null || current.user == null) return;
    
    try {
      final headers = await _authHeaders();
      if (current.isBlocked) {
        await http.delete(
          Uri.parse('$kBaseUrl/users/${Uri.encodeComponent(arg.username)}/block'),
          headers: headers,
        );
        state = AsyncValue.data(current.copyWith(isBlocked: false));
      } else {
        await http.post(
          Uri.parse('$kBaseUrl/users/${Uri.encodeComponent(arg.username)}/block'),
          headers: headers,
        );
        state = AsyncValue.data(current.copyWith(isBlocked: true));
      }
    } catch (_) {
      throw Exception('Block toggle failed');
    }
  }

  Future<void> saveRating(int score, String comment) async {
    final current = state.value;
    if (current == null || current.user == null) return;
    final userId = current.user!['id'] as int;
    
    final headers = await _authHeaders();
    final resp = await http.post(
      Uri.parse('$kBaseUrl/ratings/$userId'),
      headers: headers,
      body: jsonEncode({
        'score': score,
        'comment': comment.isEmpty ? null : comment,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to save rating');
    }
  }
}

final publicProfileProvider = AsyncNotifierProvider.autoDispose.family<PublicProfileViewModel, PublicProfileState, PublicProfileArgs>(
  () => PublicProfileViewModel(),
);

class RatingsListArgs {
  final int userId;
  const RatingsListArgs(this.userId);
  @override bool operator ==(Object other) => identical(this, other) || other is RatingsListArgs && userId == other.userId;
  @override int get hashCode => userId.hashCode;
}

final ratingsListProvider = FutureProvider.autoDispose.family<List<dynamic>, RatingsListArgs>((ref, arg) async {
  final token = await StorageService.getToken();
  final headers = {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  final resp = await http.get(Uri.parse('$kBaseUrl/ratings/${arg.userId}'), headers: headers);
  if (resp.statusCode == 200) {
    return jsonDecode(resp.body) as List<dynamic>;
  }
  return [];
});
