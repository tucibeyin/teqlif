import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';
import '../../models/listing_filter_state.dart';

class LiveStreamHistoryState {
  final List<dynamic> streams;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool hasError;
  final int? selectedStreamId;
  final String? cursor;
  final ListingFilterState filter;

  const LiveStreamHistoryState({
    this.streams = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.hasError = false,
    this.selectedStreamId,
    this.cursor,
    this.filter = const ListingFilterState(),
  });

  LiveStreamHistoryState copyWith({
    List<dynamic>? streams,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    bool? hasError,
    int? selectedStreamId,
    bool clearSelectedStreamId = false,
    String? cursor,
    bool clearCursor = false,
    ListingFilterState? filter,
  }) {
    return LiveStreamHistoryState(
      streams: streams ?? this.streams,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      hasError: hasError ?? this.hasError,
      selectedStreamId: clearSelectedStreamId ? null : (selectedStreamId ?? this.selectedStreamId),
      cursor: clearCursor ? null : (cursor ?? this.cursor),
      filter: filter ?? this.filter,
    );
  }
}

class LiveStreamHistoryViewModel extends AutoDisposeNotifier<LiveStreamHistoryState> {
  @override
  LiveStreamHistoryState build() {
    Future.microtask(() => fetchHistory());
    return const LiveStreamHistoryState(isLoading: false);
  }

  Future<void> fetchHistory({bool loadMore = false}) async {
    if (!loadMore) {
      state = state.copyWith(
        isLoading: true,
        hasError: false,
        streams: [],
        clearCursor: true,
        hasMore: true,
      );
    } else {
      state = state.copyWith(isLoadingMore: true);
    }

    try {
      final token = await StorageService.getToken();
      String url = '$kBaseUrl/streams/my-history?limit=20';
      if (state.cursor != null) url += '&cursor=${state.cursor}';

      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final newStreams = jsonDecode(resp.body) as List;
        final currentStreams = List<dynamic>.from(state.streams);
        
        String? newCursor = state.cursor;
        if (newStreams.isNotEmpty) {
          currentStreams.addAll(newStreams);
          newCursor = newStreams.last['started_at'] as String?;
        }
        
        state = state.copyWith(
          streams: currentStreams,
          cursor: newCursor,
          hasMore: newStreams.length >= 20,
          isLoading: false,
          isLoadingMore: false,
        );
      } else {
        throw Exception('Failed to load');
      }
    } catch (e) {
      state = state.copyWith(
        hasError: !loadMore ? true : state.hasError,
        isLoading: false,
        isLoadingMore: false,
      );
    }
  }

  void selectStream(int? id) {
    state = state.copyWith(
      selectedStreamId: id,
      clearSelectedStreamId: id == null,
    );
  }

  void updateFilter(ListingFilterState filter) {
    state = state.copyWith(filter: filter);
  }
  
  List<dynamic> get filteredStreams {
    var result = state.streams;
    if (state.filter.searchQuery != null && state.filter.searchQuery!.isNotEmpty) {
      final q = state.filter.searchQuery!.toLowerCase();
      result = result.where((s) => (s['title'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    if (state.filter.category != null && state.filter.category!.isNotEmpty) {
      result = result.where((s) => s['category'] == state.filter.category).toList();
    }
    if (state.filter.subcategory != null && state.filter.subcategory!.isNotEmpty) {
      result = result.where((s) => s['subcategory'] == state.filter.subcategory).toList();
    }
    if (state.filter.dateFrom != null && state.filter.dateTo != null) {
      final start = state.filter.dateFrom!;
      final end = state.filter.dateTo!.add(const Duration(days: 1));
      result = result.where((s) {
        final raw = s['started_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    return result;
  }
}

final liveStreamHistoryProvider = NotifierProvider.autoDispose<LiveStreamHistoryViewModel, LiveStreamHistoryState>(
  () => LiveStreamHistoryViewModel(),
);
