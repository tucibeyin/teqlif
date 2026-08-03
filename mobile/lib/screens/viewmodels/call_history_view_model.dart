import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../models/call_history_item.dart';
import '../../config/api.dart';
import '../../services/storage_service.dart';

class CallHistoryFilterState {
  final List<CallHistoryItem> items;
  final bool hasMore;
  final int page;
  final bool loadingMore;

  const CallHistoryFilterState({
    this.items = const [],
    this.hasMore = true,
    this.page = 1,
    this.loadingMore = false,
  });

  CallHistoryFilterState copyWith({
    List<CallHistoryItem>? items,
    bool? hasMore,
    int? page,
    bool? loadingMore,
  }) {
    return CallHistoryFilterState(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

class CallHistoryViewModel extends AutoDisposeFamilyAsyncNotifier<CallHistoryFilterState, String> {
  @override
  FutureOr<CallHistoryFilterState> build(String arg) async {
    return await _fetchPage(1);
  }

  Future<CallHistoryFilterState> _fetchPage(int page) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('$kBaseUrl/calls/history?page=$page&per_page=20&filter=$arg');
    
    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (resp.statusCode == 200) {
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final newItems = (data['items'] as List)
          .map((e) => CallHistoryItem.fromMap(e as Map<String, dynamic>))
          .toList();

      return CallHistoryFilterState(
        items: newItems,
        hasMore: data['has_more'] as bool,
        page: page + 1,
      );
    } else {
      throw Exception('Failed to load call history');
    }
  }

  Future<void> loadMore() async {
    final currentState = state.value;
    if (currentState == null || !currentState.hasMore || currentState.loadingMore) return;

    state = AsyncValue.data(currentState.copyWith(loadingMore: true));

    try {
      final newState = await _fetchPage(currentState.page);
      state = AsyncValue.data(currentState.copyWith(
        items: [...currentState.items, ...newState.items],
        hasMore: newState.hasMore,
        page: newState.page,
        loadingMore: false,
      ));
    } catch (e, st) {
      state = AsyncValue.data(currentState.copyWith(loadingMore: false));
      // Optionally surface error to UI via toast in the View, not overriding state.
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final newState = await _fetchPage(1);
      state = AsyncValue.data(newState);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final callHistoryProvider = AsyncNotifierProvider.autoDispose.family<CallHistoryViewModel, CallHistoryFilterState, String>(
  () => CallHistoryViewModel(),
);
