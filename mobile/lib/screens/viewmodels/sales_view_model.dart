import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/storage_service.dart';
import '../../models/listing_filter_state.dart';

class SalesState {
  final List<Map<String, dynamic>> sales;
  final List<(String, String)>? categories;
  final ListingFilterState filter;

  const SalesState({
    this.sales = const [],
    this.categories,
    this.filter = const ListingFilterState(),
  });

  SalesState copyWith({
    List<Map<String, dynamic>>? sales,
    List<(String, String)>? categories,
    ListingFilterState? filter,
  }) {
    return SalesState(
      sales: sales ?? this.sales,
      categories: categories ?? this.categories,
      filter: filter ?? this.filter,
    );
  }
}

class SalesViewModel extends AutoDisposeAsyncNotifier<SalesState> {
  @override
  FutureOr<SalesState> build() async {
    // SWR: cache varsa hemen göster, arka planda taze veri çek
    final cached = CacheService.getWithStaleness(StorageService.cacheSales);
    if (cached != null) {
      final cachedState = SalesState(
        sales: List<Map<String, dynamic>>.from(
            (cached.data as List).map((e) => Map<String, dynamic>.from(e as Map))),
        filter: state.valueOrNull?.filter ?? const ListingFilterState(),
      );
      state = AsyncValue.data(cachedState);
      if (!cached.isStale) return cachedState; // taze — ağ çağrısına gerek yok
    }
    return _fetchData();
  }

  Future<SalesState> _fetchData() async {
    final sales = await ref.read(authServiceProvider).getMySales();
    await CacheService.saveData(StorageService.cacheSales, sales,
        ttl: const Duration(minutes: 3));
    final categories = state.valueOrNull?.categories;
    final filter = state.valueOrNull?.filter ?? const ListingFilterState();
    return SalesState(sales: sales, categories: categories, filter: filter);
  }

  Future<void> reload() async {
    await CacheService.clearData(StorageService.cacheSales);
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

final salesProvider = AsyncNotifierProvider.autoDispose<SalesViewModel, SalesState>(
  SalesViewModel.new,
);
