import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../models/listing_filter_state.dart';

class PurchasesState {
  final List<Map<String, dynamic>> purchases;
  final List<(String, String)>? categories;
  final ListingFilterState filter;

  const PurchasesState({
    this.purchases = const [],
    this.categories,
    this.filter = const ListingFilterState(),
  });

  PurchasesState copyWith({
    List<Map<String, dynamic>>? purchases,
    List<(String, String)>? categories,
    ListingFilterState? filter,
  }) {
    return PurchasesState(
      purchases: purchases ?? this.purchases,
      categories: categories ?? this.categories,
      filter: filter ?? this.filter,
    );
  }
}

class PurchasesViewModel extends AutoDisposeAsyncNotifier<PurchasesState> {
  @override
  FutureOr<PurchasesState> build() async {
    return _fetchData();
  }

  Future<PurchasesState> _fetchData() async {
    final purchases = await AuthService.getMyPurchases();
    final categories = state.valueOrNull?.categories;
    final filter = state.valueOrNull?.filter ?? const ListingFilterState();
    return PurchasesState(purchases: purchases, categories: categories, filter: filter);
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchData());
  }

  void updateFilter(ListingFilterState filter) {
    if (state.value != null) {
      state = AsyncValue.data(state.value!.copyWith(filter: filter));
    }
  }

  void setCategories(List<(String, String)> categories) {
    if (state.value != null) {
      state = AsyncValue.data(state.value!.copyWith(categories: categories));
    }
  }
}

final purchasesProvider = AsyncNotifierProvider.autoDispose<PurchasesViewModel, PurchasesState>(
  PurchasesViewModel.new,
);
