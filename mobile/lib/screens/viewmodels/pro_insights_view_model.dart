import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';
import '../../models/pro_insights_data.dart';
import '../../models/listing_filter_state.dart';
class ProInsightsState {
  final ProInsightsData? data;
  final ProMetrics? metrics;
  final bool loading;
  final bool hasError;
  final Map<String, bool> showAll;
  final ListingFilterState hotLeadsFilter;
  final ListingFilterState priceIntelFilter;
  final String priceIntelSignal;

  const ProInsightsState({
    this.data,
    this.metrics,
    this.loading = true,
    this.hasError = false,
    this.showAll = const {},
    this.hotLeadsFilter = const ListingFilterState(),
    this.priceIntelFilter = const ListingFilterState(),
    this.priceIntelSignal = '',
  });

  ProInsightsState copyWith({
    ProInsightsData? data,
    ProMetrics? metrics,
    bool? loading,
    bool? hasError,
    Map<String, bool>? showAll,
    ListingFilterState? hotLeadsFilter,
    ListingFilterState? priceIntelFilter,
    String? priceIntelSignal,
  }) {
    return ProInsightsState(
      data: data ?? this.data,
      metrics: metrics ?? this.metrics,
      loading: loading ?? this.loading,
      hasError: hasError ?? this.hasError,
      showAll: showAll ?? this.showAll,
      hotLeadsFilter: hotLeadsFilter ?? this.hotLeadsFilter,
      priceIntelFilter: priceIntelFilter ?? this.priceIntelFilter,
      priceIntelSignal: priceIntelSignal ?? this.priceIntelSignal,
    );
  }
}

class ProInsightsViewModel extends AutoDisposeNotifier<ProInsightsState> {
  @override
  ProInsightsState build() {
    Future.microtask(() => load());
    return const ProInsightsState();
  }

  Future<void> load({bool bypassCache = false}) async {
    state = state.copyWith(loading: state.data == null ? true : state.loading, hasError: false);
    final sd = state.hotLeadsFilter.dateFrom?.toIso8601String().substring(0, 10);
    final ed = state.hotLeadsFilter.dateTo?.toIso8601String().substring(0, 10);

    // We use streams but they emit once usually or we take latest
    Future<void> loadIns() async {
      try {
        await for (final d in AnalyticsService.getProInsights(startDate: sd, endDate: ed, bypassCache: bypassCache)) {
          state = state.copyWith(data: d, loading: false);
        }
      } catch (e) {
        if (state.data == null) {
          state = state.copyWith(loading: false, hasError: true);
        }
      }
    }

    Future<void> loadMet() async {
      try {
        await for (final m in AnalyticsService.getProMetrics(bypassCache: bypassCache)) {
          state = state.copyWith(metrics: m);
        }
      } catch (_) {}
    }

    await Future.wait([loadIns(), loadMet()]);
  }

  void updateHotLeadsFilter(ListingFilterState f) {
    final dateChanged = f.dateFrom != state.hotLeadsFilter.dateFrom || f.dateTo != state.hotLeadsFilter.dateTo;
    
    var newShowAll = Map<String, bool>.from(state.showAll);
    newShowAll['hotLeads'] = false;
    
    ListingFilterState newPriceFilter = state.priceIntelFilter;
    if (dateChanged) {
      newPriceFilter = state.priceIntelFilter.copyWith(dateFrom: f.dateFrom, dateTo: f.dateTo);
    }
    
    state = state.copyWith(
      hotLeadsFilter: f,
      priceIntelFilter: newPriceFilter,
      showAll: newShowAll,
    );

    if (dateChanged) {
      state = state.copyWith(data: null, metrics: null);
      load();
    }
  }

  void updatePriceIntelFilter(ListingFilterState f) {
    final dateChanged = f.dateFrom != state.priceIntelFilter.dateFrom || f.dateTo != state.priceIntelFilter.dateTo;
    
    var newShowAll = Map<String, bool>.from(state.showAll);
    newShowAll['priceIntel'] = false;

    ListingFilterState newHotFilter = state.hotLeadsFilter;
    if (dateChanged) {
      newHotFilter = state.hotLeadsFilter.copyWith(dateFrom: f.dateFrom, dateTo: f.dateTo);
    }

    state = state.copyWith(
      priceIntelFilter: f,
      hotLeadsFilter: newHotFilter,
      showAll: newShowAll,
    );

    if (dateChanged) {
      state = state.copyWith(data: null, metrics: null);
      load();
    }
  }

  void updatePriceIntelSignal(String signal) {
    var newShowAll = Map<String, bool>.from(state.showAll);
    newShowAll['priceIntel'] = false;
    state = state.copyWith(priceIntelSignal: signal, showAll: newShowAll);
  }

  void toggleShowAll(String key) {
    var newShowAll = Map<String, bool>.from(state.showAll);
    newShowAll[key] = !(newShowAll[key] ?? false);
    state = state.copyWith(showAll: newShowAll);
  }
}

final proInsightsProvider = NotifierProvider.autoDispose<ProInsightsViewModel, ProInsightsState>(
  () => ProInsightsViewModel(),
);
