import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';

// ── Best Stream Time ──

class BestStreamTimeState {
  final Map<String, dynamic>? data;
  final bool loading;
  final bool hasError;
  final bool showAllSlots;

  const BestStreamTimeState({
    this.data,
    this.loading = true,
    this.hasError = false,
    this.showAllSlots = false,
  });

  BestStreamTimeState copyWith({
    Map<String, dynamic>? data,
    bool? loading,
    bool? hasError,
    bool? showAllSlots,
  }) {
    return BestStreamTimeState(
      data: data ?? this.data,
      loading: loading ?? this.loading,
      hasError: hasError ?? this.hasError,
      showAllSlots: showAllSlots ?? this.showAllSlots,
    );
  }
}

class BestStreamTimeViewModel extends AutoDisposeNotifier<BestStreamTimeState> {
  @override
  BestStreamTimeState build() {
    Future.microtask(() => load());
    return const BestStreamTimeState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, hasError: false);
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/pro/best-stream-time'),
        headers: await buildApiHeaders(token),
      );
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        state = state.copyWith(data: d, loading: false);
      } else {
        throw Exception('Veri alınamadı');
      }
    } catch (_) {
      state = state.copyWith(hasError: true, loading: false);
    }
  }

  void toggleShowAllSlots() {
    state = state.copyWith(showAllSlots: !state.showAllSlots);
  }
}

final bestStreamTimeProvider = NotifierProvider.autoDispose<BestStreamTimeViewModel, BestStreamTimeState>(
  () => BestStreamTimeViewModel(),
);

// ── Conversion Breakdown ──

class ConversionBreakdownState {
  final List<dynamic> data;
  final bool loading;
  final bool hasError;
  final bool showAll;

  const ConversionBreakdownState({
    this.data = const [],
    this.loading = true,
    this.hasError = false,
    this.showAll = false,
  });

  ConversionBreakdownState copyWith({
    List<dynamic>? data,
    bool? loading,
    bool? hasError,
    bool? showAll,
  }) {
    return ConversionBreakdownState(
      data: data ?? this.data,
      loading: loading ?? this.loading,
      hasError: hasError ?? this.hasError,
      showAll: showAll ?? this.showAll,
    );
  }
}

class ConversionBreakdownViewModel extends AutoDisposeNotifier<ConversionBreakdownState> {
  @override
  ConversionBreakdownState build() {
    Future.microtask(() => load());
    return const ConversionBreakdownState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, hasError: false);
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/pro/conversion-breakdown'),
        headers: await buildApiHeaders(token),
      );
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body) as List<dynamic>;
        state = state.copyWith(data: d, loading: false);
      } else {
        throw Exception('Veri alınamadı');
      }
    } catch (_) {
      state = state.copyWith(hasError: true, loading: false);
    }
  }

  void toggleShowAll() {
    state = state.copyWith(showAll: !state.showAll);
  }
}

final conversionBreakdownProvider = NotifierProvider.autoDispose<ConversionBreakdownViewModel, ConversionBreakdownState>(
  () => ConversionBreakdownViewModel(),
);
