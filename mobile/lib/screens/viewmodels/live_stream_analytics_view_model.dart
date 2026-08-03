import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';

class LiveStreamAnalyticsState {
  final Map<String, dynamic>? data;
  final bool isLoading;
  final bool hasError;

  const LiveStreamAnalyticsState({
    this.data,
    this.isLoading = true,
    this.hasError = false,
  });

  LiveStreamAnalyticsState copyWith({
    Map<String, dynamic>? data,
    bool? isLoading,
    bool? hasError,
  }) {
    return LiveStreamAnalyticsState(
      data: data ?? this.data,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
    );
  }
}

class LiveStreamAnalyticsViewModel extends AutoDisposeFamilyNotifier<LiveStreamAnalyticsState, int> {
  @override
  LiveStreamAnalyticsState build(int arg) {
    Future.microtask(() => fetchAnalytics());
    return const LiveStreamAnalyticsState();
  }

  Future<void> fetchAnalytics() async {
    state = state.copyWith(isLoading: true, hasError: false);
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/seller-report/$arg'),
        headers: await buildApiHeaders(token),
      );
      if (resp.statusCode == 200) {
        state = state.copyWith(
          data: jsonDecode(resp.body) as Map<String, dynamic>,
          isLoading: false,
        );
      } else {
        state = state.copyWith(hasError: true, isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(hasError: true, isLoading: false);
    }
  }
}

final liveStreamAnalyticsProvider = NotifierProvider.autoDispose.family<LiveStreamAnalyticsViewModel, LiveStreamAnalyticsState, int>(
  () => LiveStreamAnalyticsViewModel(),
);
