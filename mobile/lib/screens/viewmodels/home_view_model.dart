import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:teqlif/core/network/api_client.dart';
import '../../../repositories/home_repository.dart';
import '../../../services/storage_service.dart';
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
      recentListings: recentListings ?? this.recentListings,
      hesitatedListings: hesitatedListings ?? this.hesitatedListings,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isHesitatedLoading: isHesitatedLoading ?? this.isHesitatedLoading,
      hasError: hasError ?? this.hasError,
      filter: filter ?? this.filter,
      lastMaxId: lastMaxId ?? this.lastMaxId,
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
    state = AsyncValue.data(current.copyWith(isLoading: true, hasError: false));

    final token = await StorageService.getToken();
    if (token == null) {
      state = AsyncValue.data(state.value!.copyWith(isLoading: false));
      return;
    }

    try {
      if (current.hasFilter) {
        await _fetchFiltered(token, current.filter);
      } else {
        await Future.wait([
          _fetchRecent(token),
          _fetchHesitated(token),
        ], eagerError: false);
      }
    } catch (e) {
      state = AsyncValue.data(state.value!.copyWith(
        isLoading: false,
        isHesitatedLoading: false,
        hasError: true,
      ));
    }
  }

  Future<void> _fetchRecent(String token) async {
    final resp = await http.get(
      Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/feed/recent?page=0'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (resp.statusCode == 200) {
      final parsed = jsonDecode(resp.body);
      final listings = parsed is List ? parsed : (parsed['listings'] ?? []) as List<dynamic>;
      final totalP = parsed is List
          ? (listings.length < 20 ? 0 : 9999)
          : parsed['pagination']?['total_pages'] ?? 1;
      final minId = listings.isNotEmpty
          ? listings.map((e) => e['id'] as int).reduce((a, b) => a < b ? a : b)
          : null;

      await _repo.saveFeed(resp.body);

      state = AsyncValue.data(state.value!.copyWith(
        recentListings: listings,
        totalPages:     totalP,
        currentPage:    0,
        lastMaxId:      minId,
        isLoading:      false,
        hasError:       false,
      ));
    } else {
      throw Exception('API error: ${resp.statusCode}');
    }
  }

  Future<void> _fetchHesitated(String token) async {
    state = AsyncValue.data(state.value!.copyWith(isHesitatedLoading: true));
    final resp = await http.get(
      Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/feed/hesitated'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (resp.statusCode == 200) {
      await _repo.saveHesitated(resp.body);
      state = AsyncValue.data(state.value!.copyWith(
        hesitatedListings: jsonDecode(resp.body) as List<dynamic>,
        isHesitatedLoading: false,
      ));
    } else {
      state = AsyncValue.data(state.value!.copyWith(isHesitatedLoading: false));
    }
  }

  Future<void> _fetchFiltered(String token, ListingFilterState filter) async {
    final params = <String, String>{};
    if (filter.category != null) params['category'] = filter.category!;
    if (filter.subcategory != null) params['subcategory'] = filter.subcategory!;
    if (filter.city != null) params['location'] = filter.city!;
    if (filter.condition != null) params['condition'] = filter.condition!;
    if (filter.sortBy != null) params['sort_by'] = filter.sortBy!;
    if (filter.minPrice != null) params['min_price'] = filter.minPrice!.toStringAsFixed(0);
    if (filter.maxPrice != null) params['max_price'] = filter.maxPrice!.toStringAsFixed(0);
    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      params['q'] = filter.searchQuery!;
    }
    if (filter.dateFrom != null) {
      params['date_from'] = filter.dateFrom!.toIso8601String().substring(0, 10);
    }
    if (filter.dateTo != null) {
      params['date_to'] = filter.dateTo!.toIso8601String().substring(0, 10);
    }
    final uri = Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/listings')
        .replace(queryParameters: params);

    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

    if (resp.statusCode == 200) {
      state = AsyncValue.data(state.value!.copyWith(
        recentListings: jsonDecode(resp.body) as List,
        isLoading:      false,
        hasError:       false,
      ));
    } else {
      throw Exception('API error: ${resp.statusCode}');
    }
  }

  Future<void> refresh({bool bypassCache = true}) async {
    final current = state.value;
    final token = await StorageService.getToken();

    if (current == null || token == null || current.hasFilter || current.recentListings.isEmpty) {
      await _fetchInitial(bypassCache: bypassCache);
      return;
    }

    try {
      final sinceId = current.recentListings.first['id'];
      final resp = await http.get(
        Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/feed/recent?since_id=$sinceId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);
        final delta = parsed is List ? parsed : parsed['listings'] ?? [];
        if (delta.isNotEmpty) {
          final existingIds = current.recentListings.map((e) => e['id']).toSet();
          final uniqueDelta = delta.where((e) => !existingIds.contains(e['id'])).toList();
          final newListings = [...uniqueDelta, ...current.recentListings];
          state = AsyncValue.data(current.copyWith(recentListings: newListings));
          await _repo.prependFeed(newListings);
        }
      } else {
        await _fetchInitial(bypassCache: bypassCache);
      }

      await _fetchHesitated(token);
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
      final token = await StorageService.getToken();
      if (token == null) {
        state = AsyncValue.data(current.copyWith(isLoadingMore: false));
        return;
      }

      final nextPage = current.currentPage + 1;
      final baseUrl  = ref.read(apiClientProvider).config.baseUrl;
      final uri = current.lastMaxId != null
          ? Uri.parse('$baseUrl/feed/recent?max_id=${current.lastMaxId}')
          : Uri.parse('$baseUrl/feed/recent?page=$nextPage');

      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (resp.statusCode == 200) {
        final parsed        = jsonDecode(resp.body);
        final moreListings  = (parsed is List ? parsed : (parsed['listings'] ?? [])) as List<dynamic>;
        final newTotal      = parsed is List
            ? (moreListings.length < 20 ? nextPage : 9999)
            : parsed['pagination']?['total_pages'] ?? current.totalPages;

        final existingIds = current.recentListings.map((e) => e['id']).toSet();
        final uniqueMore  = moreListings.where((e) => !existingIds.contains(e['id'])).toList();
        final newMinId    = uniqueMore.isNotEmpty
            ? uniqueMore.map((e) => e['id'] as int).reduce((a, b) => a < b ? a : b)
            : current.lastMaxId;

        state = AsyncValue.data(current.copyWith(
          recentListings: [...current.recentListings, ...uniqueMore],
          currentPage:    nextPage,
          totalPages:     newTotal,
          lastMaxId:      newMinId,
          isLoadingMore:  false,
        ));
      } else {
        state = AsyncValue.data(current.copyWith(isLoadingMore: false));
      }
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

    final token = await StorageService.getToken();
    if (token != null) {
      try {
        await http.delete(
          Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/feed/hesitated/$listingId'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        );
      } catch (_) {}
    }
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
