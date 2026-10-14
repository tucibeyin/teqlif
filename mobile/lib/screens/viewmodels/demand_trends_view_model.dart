import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';
import '../../services/cache_service.dart';
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
  CacheService get _cache => ref.read(cacheServiceProvider);

  String _cacheKey() =>
      'cache_demand_trends_${state.filter.category ?? ''}_${state.filter.subcategory ?? ''}';

  @override
  DemandTrendsState build() {
    // Başlangıç filtresi default (kategori yok) — key sabit
    final cached = _cache.getWithStaleness('cache_demand_trends__')?.data;
    final trends = cached != null
        ? ((cached as Map<String, dynamic>)['trends'] as List? ?? [])
            .cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    Future.microtask(() => load());

    return DemandTrendsState(
      trends: trends,
      loading: trends.isEmpty,
    );
  }

  Future<void> load() async {
    final hasCached = state.trends.isNotEmpty;
    if (!hasCached) state = state.copyWith(loading: true, clearError: true);
    try {
      final data = await ref.read(analyticsServiceProvider).demandTrends(
        weeks: 8,
        category: state.filter.category,
        subcategory: state.filter.subcategory,
      );
      if (data == null) {
        if (!hasCached) state = state.copyWith(error: 'no_data', loading: false);
        return;
      }
      final raw = (data['trends'] as List?) ?? [];
      final trends = raw.cast<Map<String, dynamic>>();
      state = state.copyWith(trends: trends, loading: false);
      await _cache.saveData(_cacheKey(), data, ttl: const Duration(minutes: 30));
    } catch (_) {
      if (!hasCached) state = state.copyWith(error: 'error', loading: false);
    }
  }

  void updateFilter(ListingFilterState filter) {
    state = state.copyWith(filter: filter, trends: const [], loading: true);
    load();
  }
}

final demandTrendsProvider = NotifierProvider.autoDispose<DemandTrendsViewModel, DemandTrendsState>(
  () => DemandTrendsViewModel(),
);
