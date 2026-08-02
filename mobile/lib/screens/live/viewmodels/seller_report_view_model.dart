import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/analytics_service.dart';

class SellerReportViewModel extends AutoDisposeFamilyAsyncNotifier<Map<String, dynamic>?, int> {
  @override
  FutureOr<Map<String, dynamic>?> build(int arg) async {
    return AnalyticsService.getSellerReport(arg);
  }
  
  Future<void> retry() async {
    state = const AsyncValue.loading();
    try {
      final report = await AnalyticsService.getSellerReport(arg);
      state = AsyncValue.data(report);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final sellerReportViewModelProvider = AutoDisposeAsyncNotifierProviderFamily<SellerReportViewModel, Map<String, dynamic>?, int>(() {
  return SellerReportViewModel();
});
