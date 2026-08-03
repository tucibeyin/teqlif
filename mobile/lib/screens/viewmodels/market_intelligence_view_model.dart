import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';

class MarketIntelligenceState {
  final int searchDays;
  final bool loading;
  final bool hasError;
  final Map<String, dynamic>? trends;
  final Map<String, dynamic>? demand;

  const MarketIntelligenceState({
    this.searchDays = 7,
    this.loading = true,
    this.hasError = false,
    this.trends,
    this.demand,
  });

  MarketIntelligenceState copyWith({
    int? searchDays,
    bool? loading,
    bool? hasError,
    Map<String, dynamic>? trends,
    Map<String, dynamic>? demand,
  }) {
    return MarketIntelligenceState(
      searchDays: searchDays ?? this.searchDays,
      loading: loading ?? this.loading,
      hasError: hasError ?? this.hasError,
      trends: trends ?? this.trends,
      demand: demand ?? this.demand,
    );
  }
}

class MarketIntelligenceViewModel extends AutoDisposeNotifier<MarketIntelligenceState> {
  @override
  MarketIntelligenceState build() {
    return const MarketIntelligenceState(loading: false);
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, hasError: false);
    
    try {
      final results = await Future.wait([
        AnalyticsService.getMarketTrends(),
        AnalyticsService.getDemandRadar(days: state.searchDays),
      ]);
      
      final trends = results[0];
      final demand = results[1];

      if (trends == null && demand == null) {
        state = state.copyWith(loading: false, hasError: true);
        return;
      }

      state = state.copyWith(
        loading: false,
        hasError: false,
        trends: trends,
        demand: demand,
      );
    } catch (_) {
      state = state.copyWith(loading: false, hasError: true);
    }
  }

  Future<void> reloadDemand(int days) async {
    state = state.copyWith(searchDays: days);
    try {
      final data = await AnalyticsService.getDemandRadar(days: days);
      state = state.copyWith(demand: data);
    } catch (_) {
      // ignore
    }
  }
}

final marketIntelligenceProvider = NotifierProvider.autoDispose<MarketIntelligenceViewModel, MarketIntelligenceState>(
  () => MarketIntelligenceViewModel(),
);
