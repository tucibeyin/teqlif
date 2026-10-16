import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/home_repository.dart';
import '../../../services/analytics_service.dart';
import '../../../models/listing_filter_state.dart';

class HomeState {
  final List<dynamic> recentListings;
  final List<dynamic> hesitatedListings;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isHesitatedLoading;
  final bool hasError;
  final ListingFilterState filter;
  final int? lastMaxId;

  const HomeState({
    this.recentListings = const [],
    this.hesitatedListings = const [],
    this.currentPage = 1,
    this.totalPages = 1,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.isHesitatedLoading = false,
    this.hasError = false,
    this.filter = const ListingFilterState(),
    this.lastMaxId,
  });

  bool get hasFilter => !filter.isEmpty;
  bool get isExhausted => currentPage >= totalPages;

  HomeState copyWith({
    List<dynamic>? recentListings,
    List<dynamic>? hesitatedListings,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isHesitatedLoading,
    bool? hasError,
    ListingFilterState? filter,
    int? lastMaxId,
  }) {
    return HomeState(
      recentListings:     recentListings     ?? this.recentListings,
      hesitatedListings:  hesitatedListings  ?? this.hesitatedListings,
      currentPage:        currentPage        ?? this.currentPage,
      totalPages:         totalPages         ?? this.totalPages,
      isLoading:          isLoading          ?? this.isLoading,
      isLoadingMore:      isLoadingMore      ?? this.isLoadingMore,
      isHesitatedLoading: isHesitatedLoading ?? this.isHesitatedLoading,
      hasError:           hasError           ?? this.hasError,
      filter:             filter             ?? this.filter,
      lastMaxId:          lastMaxId          ?? this.lastMaxId,
    );
  }
}

class HomeViewModel extends AutoDisposeAsyncNotifier<HomeState> {
  HomeRepository get _repo => ref.read(homeRepositoryProvider);

  @override
  FutureOr<HomeState> build() async {
    await _loadFromCache();
    await _fetchInitial();
    return state.value ?? const HomeState();
  }

  Future<void> _loadFromCache() async {
    final cached = await _repo.loadCache();
    if (cached == null) return;
    final current = state.value ?? const HomeState();
    state = AsyncValue.data(current.copyWith(
      recentListings:    cached.recentListings,
      hesitatedListings: cached.hesitatedListings,
      totalPages:        cached.totalPages,
    ));
  }

  Future<void> _fetchInitial({bool bypassCache = false}) async {
    final current = state.value ?? const HomeState();
    final hasCache = current.recentListings.isNotEmpty;
    state = AsyncValue.data(current.copyWith(isLoading: !hasCache, hasError: false));

    try {
      if (current.hasFilter) {
        await _fetchFiltered(current.filter);
      } else {
        await Future.wait([
          _fetchRecent(),
          _fetchHesitated(),
        ], eagerError: false);
      }
    } catch (e) {
      state = AsyncValue.data(state.value!.copyWith(
        isLoading:          false,
        isHesitatedLoading: false,
        hasError:           true,
      ));
    }
  }

  Future<void> _fetchRecent() async {
    final page = await _repo.fetchRecent(page: 0);
    await _repo.saveFeed(page.listings);
    state = AsyncValue.data(state.value!.copyWith(
      recentListings: page.listings,
      totalPages:     page.totalPages,
      currentPage:    0,
      lastMaxId:      page.minId,
      isLoading:      false,
      hasError:       false,
    ));
  }

  Future<void> _fetchHesitated() async {
    final hasCache = state.value?.hesitatedListings.isNotEmpty ?? false;
    state = AsyncValue.data(state.value!.copyWith(isHesitatedLoading: !hasCache));
    try {
      final items = await _repo.fetchHesitated();
      await _repo.saveHesitated(items);
      state = AsyncValue.data(state.value!.copyWith(
        hesitatedListings:  items,
        isHesitatedLoading: false,
      ));
    } catch (_) {
      state = AsyncValue.data(state.value!.copyWith(isHesitatedLoading: false));
    }
  }

  Future<void> _fetchFiltered(ListingFilterState filter) async {
    final items = await _repo.fetchFiltered(filter);
    state = AsyncValue.data(state.value!.copyWith(
      recentListings: items,
      isLoading:      false,
      hasError:       false,
    ));
  }

  Future<void> refresh({bool bypassCache = true}) async {
    final current = state.value;
    if (current == null || current.hasFilter || current.recentListings.isEmpty) {
      await _fetchInitial(bypassCache: bypassCache);
      return;
    }

    try {
      final sinceId = current.recentListings.first['id'] as int;
      final delta   = await _repo.fetchSinceId(sinceId);
      if (delta.listings.isNotEmpty) {
        final existingIds = current.recentListings.map((e) => e['id']).toSet();
        final unique      = delta.listings.where((e) => !existingIds.contains(e['id'])).toList();
        final merged      = [...unique, ...current.recentListings];
        state = AsyncValue.data(current.copyWith(recentListings: merged));
        await _repo.prependFeed(merged);
      }
      await _fetchHesitated();
    } catch (e) {
      await _fetchInitial(bypassCache: bypassCache);
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoadingMore || current.isExhausted || current.hasFilter) return;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true));

    try {
      final nextPage = current.currentPage + 1;
      final page     = await _repo.loadMore(page: nextPage, maxId: current.lastMaxId);

      final existingIds = current.recentListings.map((e) => e['id']).toSet();
      final unique      = page.listings.where((e) => !existingIds.contains(e['id'])).toList();
      // next_cursor backend'den geliyor: organik minimum ID.
      // Interest enjeksiyonu cursor'ı artık bozmaz.
      final newMinId = page.minId ?? current.lastMaxId;

      state = AsyncValue.data(current.copyWith(
        recentListings: [...current.recentListings, ...unique],
        currentPage:    nextPage,
        totalPages:     page.totalPages,
        lastMaxId:      newMinId,
        isLoadingMore:  false,
      ));
    } catch (e) {
      state = AsyncValue.data(state.value!.copyWith(isLoadingMore: false));
    }
  }

  void applyFilter(ListingFilterState newFilter) {
    if (!newFilter.isEmpty) {
      ref.read(analyticsServiceProvider).trackEvent('filter_applied', {
        if (newFilter.category != null) 'category': newFilter.category!,
        'source': 'home',
      });
    }
    state = AsyncValue.data(state.value!.copyWith(filter: newFilter));
    _fetchInitial(bypassCache: true);
  }

  void clearFilters() {
    state = AsyncValue.data(state.value!.copyWith(filter: const ListingFilterState()));
    _fetchInitial(bypassCache: true);
  }

  Future<void> removeHesitated(int listingId) async {
    final current = state.value;
    if (current == null) return;
    final newList = current.hesitatedListings
        .where((e) => (e as Map)['id'] != listingId)
        .toList();
    state = AsyncValue.data(current.copyWith(hesitatedListings: newList));
    await _repo.deleteHesitated(listingId);
  }

  void removeRecent(int index) {
    final current = state.value;
    if (current != null) {
      final newList = List<dynamic>.from(current.recentListings)..removeAt(index);
      state = AsyncValue.data(current.copyWith(recentListings: newList));
    }
  }
}

final homeViewModelProvider =
    AsyncNotifierProvider.autoDispose<HomeViewModel, HomeState>(() {
  return HomeViewModel();
});
