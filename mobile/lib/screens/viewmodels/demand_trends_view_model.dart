import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';
import '../../models/listing_filter_state.dart';

class DemandTrendsState {
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> trends;
  final ListingFilterState filter;

  const DemandTrendsState({
    this.loading = true,
    this.error,
    this.trends = const [],
    this.filter = const ListingFilterState(),
  });

  DemandTrendsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<Map<String, dynamic>>? trends,
    ListingFilterState? filter,
  }) {
    return DemandTrendsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      trends: trends ?? this.trends,
      filter: filter ?? this.filter,
    );
  }
}

class DemandTrendsViewModel extends AutoDisposeNotifier<DemandTrendsState> {
  @override
  DemandTrendsState build() {
    Future.microtask(() => load());
    return const DemandTrendsState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final data = await AnalyticsService.demandTrends(
        weeks: 8,
        category: state.filter.category,
        subcategory: state.filter.subcategory,
      );
      if (data == null) {
        state = state.copyWith(error: 'no_data', loading: false);
        return;
      }
      final raw = (data['trends'] as List?) ?? [];
      state = state.copyWith(
        trends: raw.cast<Map<String, dynamic>>(),
        loading: false,
      );
    } catch (_) {
      state = state.copyWith(error: 'error', loading: false);
    }
  }

  void updateFilter(ListingFilterState filter) {
    state = state.copyWith(filter: filter);
    load();
  }
}

final demandTrendsProvider = NotifierProvider.autoDispose<DemandTrendsViewModel, DemandTrendsState>(
  () => DemandTrendsViewModel(),
);
