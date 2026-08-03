import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';

class AdReportViewModel extends AutoDisposeFamilyAsyncNotifier<Map<String, dynamic>?, int> {
  @override
  FutureOr<Map<String, dynamic>?> build(int arg) async {
    return AnalyticsService.getCampaignReport(arg);
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => AnalyticsService.getCampaignReport(arg));
  }
}

final adReportProvider = AsyncNotifierProvider.autoDispose.family<AdReportViewModel, Map<String, dynamic>?, int>(
  AdReportViewModel.new,
);
