import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/category_service.dart';
import '../../services/listing_service.dart';

class PurchaseDetailViewModel extends AutoDisposeFamilyAsyncNotifier<List<(String, String)>?, String> {
  @override
  FutureOr<List<(String, String)>?> build(String locale) async {
    return ref.read(categoryServiceProvider).getCategories(locale: locale);
  }

  Future<Map<String, dynamic>?> getListing(int listingId) async {
    return ref.read(listingServiceProvider).getListingById(listingId);
  }
}

final purchaseDetailProvider = AsyncNotifierProvider.autoDispose.family<PurchaseDetailViewModel, List<(String, String)>?, String>(
  PurchaseDetailViewModel.new,
);
