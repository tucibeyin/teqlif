import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/category_service.dart';
import '../../services/listing_service.dart';

class SaleDetailViewModel extends AutoDisposeFamilyAsyncNotifier<List<(String, String)>?, String> {
  @override
  FutureOr<List<(String, String)>?> build(String locale) async {
    return CategoryService.getCategories(locale: locale);
  }

  Future<Map<String, dynamic>?> getListing(int listingId) async {
    return ListingService.getListingById(listingId);
  }
}

final saleDetailProvider = AsyncNotifierProvider.autoDispose.family<SaleDetailViewModel, List<(String, String)>?, String>(
  SaleDetailViewModel.new,
);
