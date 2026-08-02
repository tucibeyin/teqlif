import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
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
    );
  }
}

class HomeViewModel extends AutoDisposeAsyncNotifier<HomeState> {
  static const _kCacheKeyFeed = 'home_feed_recent';
  static const _kCacheKeyHesitated = 'feed_hesitated';

  @override
  FutureOr<HomeState> build() async {
    // SWR pattern: Load cache first, then API
    _loadFromCache();
    await _fetchInitial();
    return state.value ?? const HomeState();
  }

  Future<void> _loadFromCache() async {
    try {
      final cacheBox = await Hive.openBox('homeCache');
      final cachedFeed = cacheBox.get(_kCacheKeyFeed);
      final cachedHesitated = cacheBox.get(_kCacheKeyHesitated);

      final current = state.value ?? const HomeState();
      
      List<dynamic> recent = current.recentListings;
      List<dynamic> hesitated = current.hesitatedListings;
      int totalP = current.totalPages;

      if (cachedFeed != null) {
        try {
          final parsed = jsonDecode(cachedFeed);
          if (parsed is List) {
            recent = parsed;
          } else if (parsed['listings'] != null) {
            recent = parsed['listings'];
            totalP = parsed['pagination']?['total_pages'] ?? 1;
          }
        } catch (_) {}
      }

      if (cachedHesitated != null) {
        try {
          hesitated = jsonDecode(cachedHesitated) as List<dynamic>;
        } catch (_) {}
      }

      state = AsyncValue.data(current.copyWith(
        recentListings: recent,
        hesitatedListings: hesitated,
        totalPages: totalP,
      ));
    } catch (_) {}
  }

  Future<void> _fetchInitial({bool bypassCache = false}) async {
    final current = state.value ?? const HomeState();
    
    // UI Loading state, ama veriler cache'ten geldiyse ekranda duruyor olacak.
    state = AsyncValue.data(current.copyWith(
      isLoading: true,
      hasError: false,
    ));

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
    final resp = await http.get(Uri.parse('$kBaseUrl/feed/recent?page=1'), headers: {
      'Authorization': 'Bearer $token',
    });

    if (resp.statusCode == 200) {
      final parsed = jsonDecode(resp.body);
      final listings = parsed is List ? parsed : parsed['listings'] ?? [];
      final totalP = parsed is List ? 1 : parsed['pagination']?['total_pages'] ?? 1;

      final cacheBox = await Hive.openBox('homeCache');
      cacheBox.put(_kCacheKeyFeed, resp.body);

      state = AsyncValue.data(state.value!.copyWith(
        recentListings: listings,
        totalPages: totalP,
        currentPage: 1,
        isLoading: false,
        hasError: false,
      ));
    } else {
      throw Exception('API error: ${resp.statusCode}');
    }
  }

  Future<void> _fetchHesitated(String token) async {
    state = AsyncValue.data(state.value!.copyWith(isHesitatedLoading: true));
    final resp = await http.get(Uri.parse('$kBaseUrl/feed/hesitated'), headers: {
      'Authorization': 'Bearer $token',
    });

    if (resp.statusCode == 200) {
      final hes = jsonDecode(resp.body) as List<dynamic>;
      final cacheBox = await Hive.openBox('homeCache');
      cacheBox.put(_kCacheKeyHesitated, resp.body);
      
      state = AsyncValue.data(state.value!.copyWith(
        hesitatedListings: hes,
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
    final uri = Uri.parse('$kBaseUrl/listings').replace(queryParameters: params);
    
    final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

    if (resp.statusCode == 200) {
      state = AsyncValue.data(state.value!.copyWith(
        recentListings: jsonDecode(resp.body) as List,
        isLoading: false,
        hasError: false,
      ));
    } else {
      throw Exception('API error: ${resp.statusCode}');
    }
  }

  Future<void> refresh({bool bypassCache = true}) async {
    await _fetchInitial(bypassCache: bypassCache);
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
      final resp = await http.get(
        Uri.parse('$kBaseUrl/feed/recent?page=$nextPage'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final parsed = jsonDecode(resp.body);
        final moreListings = parsed is List ? parsed : parsed['listings'] ?? [];
        final newTotal = parsed is List ? 1 : parsed['pagination']?['total_pages'] ?? current.totalPages;

        state = AsyncValue.data(current.copyWith(
          recentListings: [...current.recentListings, ...moreListings],
          currentPage: nextPage,
          totalPages: newTotal,
          isLoadingMore: false,
        ));
      } else {
        state = AsyncValue.data(current.copyWith(isLoadingMore: false));
      }
    } catch (e) {
      state = AsyncValue.data(current.copyWith(isLoadingMore: false));
    }
  }
  
  void applyFilter(ListingFilterState newFilter) {
    if (!newFilter.isEmpty) {
      AnalyticsService.trackEvent('filter_applied', {
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
    
    final newList = current.hesitatedListings.where((e) => (e as Map)['id'] != listingId).toList();
    state = AsyncValue.data(current.copyWith(hesitatedListings: newList));
    
    final token = await StorageService.getToken();
    if (token != null) {
      try {
        await http.delete(
          Uri.parse('$kBaseUrl/feed/hesitated/$listingId'),
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
