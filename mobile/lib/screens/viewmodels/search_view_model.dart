import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../config/api.dart';
import '../../../models/stream.dart';
import '../../../services/analytics_service.dart';
import '../../../services/api_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/stream_service.dart';

class SearchState {
  // Search data
  final String query;
  final bool hasQuery;
  final bool isSearching;
  final bool isSemanticSearch;
  final bool showAllUsers;
  final bool isAlertCreating;
  final List<Map<String, dynamic>> userResults;
  final List<Map<String, dynamic>> listingResults;
  final List<StreamOut> streamResults;

  // Explore data
  final bool exploreLoading;
  final bool exploreNetworkError;
  final bool isLoggedIn;
  final List<dynamic> exploreListings; // For You feed — yatay scroll
  final List<dynamic> allPersonalizedListings; // Personalized feed tam buffer (100 ilan)
  final List<dynamic> recentListings; // Görünen dilim (client-side windowing)
  final List<StreamOut> exploreStreams;
  final List<Map<String, dynamic>> suggestedSellers;
  final List<Map<String, dynamic>> suggestedStreamers;

  // Pagination for Explore
  final int forYouPage;
  final bool forYouExhausted;
  final bool forYouLoadingMore;
  final int recentPage;
  final bool recentExhausted;
  final bool recentLoadingMore;
  final Set<int> forYouIds;

  const SearchState({
    this.query = '',
    this.hasQuery = false,
    this.isSearching = false,
    this.isSemanticSearch = false,
    this.showAllUsers = false,
    this.isAlertCreating = false,
    this.userResults = const [],
    this.listingResults = const [],
    this.streamResults = const [],
    this.exploreLoading = true,
    this.exploreNetworkError = false,
    this.isLoggedIn = false,
    this.exploreListings = const [],
    this.allPersonalizedListings = const [],
    this.recentListings = const [],
    this.exploreStreams = const [],
    this.suggestedSellers = const [],
    this.suggestedStreamers = const [],
    this.forYouPage = 0,
    this.forYouExhausted = false,
    this.forYouLoadingMore = false,
    this.recentPage = 0,
    this.recentExhausted = false,
    this.recentLoadingMore = false,
    this.forYouIds = const {},
  });

  SearchState copyWith({
    String? query,
    bool? hasQuery,
    bool? isSearching,
    bool? isSemanticSearch,
    bool? showAllUsers,
    bool? isAlertCreating,
    List<Map<String, dynamic>>? userResults,
    List<Map<String, dynamic>>? listingResults,
    List<StreamOut>? streamResults,
    bool? exploreLoading,
    bool? exploreNetworkError,
    bool? isLoggedIn,
    List<dynamic>? exploreListings,
    List<dynamic>? allPersonalizedListings,
    List<dynamic>? recentListings,
    List<StreamOut>? exploreStreams,
    List<Map<String, dynamic>>? suggestedSellers,
    List<Map<String, dynamic>>? suggestedStreamers,
    int? forYouPage,
    bool? forYouExhausted,
    bool? forYouLoadingMore,
    int? recentPage,
    bool? recentExhausted,
    bool? recentLoadingMore,
    Set<int>? forYouIds,
  }) {
    return SearchState(
      query: query ?? this.query,
      hasQuery: hasQuery ?? this.hasQuery,
      isSearching: isSearching ?? this.isSearching,
      isSemanticSearch: isSemanticSearch ?? this.isSemanticSearch,
      showAllUsers: showAllUsers ?? this.showAllUsers,
      isAlertCreating: isAlertCreating ?? this.isAlertCreating,
      userResults: userResults ?? this.userResults,
      listingResults: listingResults ?? this.listingResults,
      streamResults: streamResults ?? this.streamResults,
      exploreLoading: exploreLoading ?? this.exploreLoading,
      exploreNetworkError: exploreNetworkError ?? this.exploreNetworkError,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      exploreListings: exploreListings ?? this.exploreListings,
      allPersonalizedListings: allPersonalizedListings ?? this.allPersonalizedListings,
      recentListings: recentListings ?? this.recentListings,
      exploreStreams: exploreStreams ?? this.exploreStreams,
      suggestedSellers: suggestedSellers ?? this.suggestedSellers,
      suggestedStreamers: suggestedStreamers ?? this.suggestedStreamers,
      forYouPage: forYouPage ?? this.forYouPage,
      forYouExhausted: forYouExhausted ?? this.forYouExhausted,
      forYouLoadingMore: forYouLoadingMore ?? this.forYouLoadingMore,
      recentPage: recentPage ?? this.recentPage,
      recentExhausted: recentExhausted ?? this.recentExhausted,
      recentLoadingMore: recentLoadingMore ?? this.recentLoadingMore,
      forYouIds: forYouIds ?? this.forYouIds,
    );
  }
}

class SearchViewModel extends AutoDisposeAsyncNotifier<SearchState> {
  StreamSubscription<List<StreamOut>>? _streamsSub;
  int _searchToken = 0;

  static const int _kPersonalizedChunkSize = 12;

  @override
  FutureOr<SearchState> build() async {
    ref.onDispose(() {
      _streamsSub?.cancel();
    });
    
    final token = await StorageService.getToken();
    final loggedIn = token != null;
    
    Future.microtask(() => _loadExplore());
    
    return SearchState(isLoggedIn: loggedIn, exploreLoading: true);
  }

  // --- Explore Load Methods ---
  Future<void> _loadExplore({bool bypassCache = false}) async {
    state = AsyncValue.data(state.value?.copyWith(
      exploreLoading: true,
      exploreNetworkError: false,
      forYouPage: 0,
      forYouExhausted: false,
    ) ?? const SearchState(exploreLoading: true));

    final token = await StorageService.getToken();
    final loggedIn = token != null;
    state = AsyncValue.data(state.value!.copyWith(isLoggedIn: loggedIn));

    bool firstDataArrived = false;
    void maybeStopLoading() {
      if (!firstDataArrived) {
        firstDataArrived = true;
        final current = state.value;
        if (current != null) {
          state = AsyncValue.data(current.copyWith(exploreLoading: false));
        }
      }
    }

    _loadExploreStreams(bypassCache, maybeStopLoading);

    _loadExploreForYou(
      loggedIn: loggedIn,
      bypassCache: bypassCache,
      onData: maybeStopLoading,
    );

    if (loggedIn) {
      _loadSuggestedSellers();
      StreamService.getSuggestedStreamers().then((streamers) {
        final current = state.value;
        if (current != null) {
          state = AsyncValue.data(current.copyWith(suggestedStreamers: streamers));
        }
      });
      _loadExploreRecent(bypassCache: bypassCache, onData: maybeStopLoading);
    } else {
      maybeStopLoading();
    }
  }

  Future<void> refreshExplore({bool bypassCache = true}) async {
    final current = state.value;
    final token = await StorageService.getToken();
    final loggedIn = token != null;
    
    // Eğer veriler boşsa fallback olarak tam yükleme yap
    if (current == null || 
        (loggedIn && current.exploreListings.isEmpty) || 
        (!loggedIn && current.recentListings.isEmpty)) {
      _loadExplore(bypassCache: bypassCache);
      return;
    }
    
    // Canlı yayınları ve önerilen satıcıları asenkron olarak arka planda yenile
    _loadExploreStreams(bypassCache, () {});
    if (loggedIn) {
      _loadSuggestedSellers();
      StreamService.getSuggestedStreamers().then((streamers) {
        final current = state.value;
        if (current != null) {
          state = AsyncValue.data(current.copyWith(suggestedStreamers: streamers));
        }
      });
      // Personalized grid: SWR ile yenile (stale briefly → taze)
      _loadExploreRecent(bypassCache: false, onData: () {});
    }

    try {
      if (loggedIn) {
        // 1. Delta Fetching: For-You Feed (Giriş yapmış kullanıcılar)
        final sinceId = current.exploreListings.first['id'];
        final resp = await http.get(Uri.parse('$kBaseUrl/feed/for-you?since_id=$sinceId'), headers: {
          'Authorization': 'Bearer $token',
        });
        
        if (resp.statusCode == 200) {
          final parsed = jsonDecode(resp.body);
          final delta = parsed is List ? parsed : parsed['listings'] ?? [];
          if (delta.isNotEmpty) {
            final existingIds = state.value!.exploreListings.map((e) => e['id']).toSet();
            final uniqueDelta = (delta as List).where((e) => !existingIds.contains(e['id'])).toList();
            if (uniqueDelta.isNotEmpty) {
              state = AsyncValue.data(state.value!.copyWith(
                exploreListings: [...uniqueDelta, ...state.value!.exploreListings],
              ));
            }
          }
        } else {
           _loadExplore(bypassCache: bypassCache);
        }
      } else {
        // 2. Delta Fetching: Recent Feed (Misafir kullanıcılar)
        final sinceId = current.recentListings.first['id'];
        final resp = await http.get(Uri.parse('$kBaseUrl/feed/recent?since_id=$sinceId'));
        
        if (resp.statusCode == 200) {
          final parsed = jsonDecode(resp.body);
          final delta = parsed is List ? parsed : parsed['listings'] ?? [];
          if (delta.isNotEmpty) {
            // Yeni ilanları listenin en üstüne ekle (prepend)
            state = AsyncValue.data(state.value!.copyWith(
              recentListings: [...delta, ...state.value!.recentListings],
            ));
          }
        } else {
           _loadExplore(bypassCache: bypassCache);
        }
      }
    } catch (e) {
      // Herhangi bir ağ hatasında tam yüklemeye fallback yap
      _loadExplore(bypassCache: bypassCache);
    }
  }

  void _loadExploreStreams(bool bypassCache, void Function() onData) {
    _streamsSub?.cancel();
    _streamsSub = StreamService.getActiveStreamsStream(bypassCache: bypassCache).listen((streams) {
      final current = state.value;
      if (current != null) {
        state = AsyncValue.data(current.copyWith(exploreStreams: streams.take(4).toList()));
      }
      onData();
    }, onError: (_) => onData());
  }

  Future<void> _loadSuggestedSellers() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/users/suggested-sellers'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        final current = state.value;
        if (current != null) {
          state = AsyncValue.data(current.copyWith(suggestedSellers: data.cast<Map<String, dynamic>>()));
        }
      }
    } catch (_) {}
  }

  void _loadExploreForYou({
    required bool loggedIn,
    required bool bypassCache,
    required void Function() onData,
  }) {
    final url = loggedIn ? '$kBaseUrl/feed/for-you?page=0' : '$kBaseUrl/listings';
    final cacheKey = loggedIn ? 'explore_for_you' : 'explore_listings';
    final ttl = const Duration(minutes: 5);

    ApiService.get<List<dynamic>>(
      url: url,
      cacheKey: cacheKey,
      cacheTtl: ttl,
      bypassCache: bypassCache,
      fromJson: (raw) => raw as List,
    ).listen((data) {
      final current = state.value;
      if (current == null) return;

      final ids = data
          .whereType<Map<String, dynamic>>()
          .map((e) => e['id'])
          .whereType<int>()
          .toSet();

      final updatedIds = Set<int>.from(current.forYouIds)..addAll(ids);
      
      state = AsyncValue.data(current.copyWith(
        exploreListings: data,
        forYouIds: updatedIds,
        forYouPage: loggedIn ? 1 : current.forYouPage,
        forYouExhausted: loggedIn ? data.length < 20 : current.forYouExhausted,
      ));

      if (loggedIn && ids.isNotEmpty) {
        AnalyticsService.logListingImpressions(
          listingIds: ids.take(10).toList(),
          section: 'for_you',
        );
      }
      onData();
    }, onError: (_) {
      final current = state.value;
      if (current != null) {
        state = AsyncValue.data(current.copyWith(exploreNetworkError: true));
      }
      onData();
    });
  }

  void _loadExploreRecent({
    required bool bypassCache,
    required void Function() onData,
  }) {
    final isLoggedIn = state.value?.isLoggedIn == true;
    final url = isLoggedIn
        ? '$kBaseUrl/feed/personalized?limit=100'
        : '$kBaseUrl/feed/recent?page=0';
    final cacheKey = isLoggedIn ? 'explore_personalized_feed' : 'explore_recent_feed';
    final ttl = isLoggedIn
        ? const Duration(minutes: 15) // Backend Redis affinity TTL ile senkron
        : const Duration(minutes: 5);

    ApiService.get<List<dynamic>>(
      url: url,
      cacheKey: cacheKey,
      cacheTtl: ttl,
      bypassCache: isLoggedIn ? false : bypassCache, // Logged-in her zaman SWR
      fromJson: (raw) => raw as List,
    ).listen((allItems) {
      final current = state.value;
      if (current == null) return;

      if (isLoggedIn) {
        final initialSlice = allItems.take(_kPersonalizedChunkSize).toList();
        state = AsyncValue.data(current.copyWith(
          allPersonalizedListings: allItems,
          recentListings: initialSlice,
          recentPage: 1,
          recentExhausted: allItems.length <= _kPersonalizedChunkSize,
        ));
        final ids = initialSlice
            .whereType<Map<String, dynamic>>()
            .map((e) => e['id'])
            .whereType<int>()
            .take(10)
            .toList();
        if (ids.isNotEmpty) {
          AnalyticsService.logListingImpressions(
            listingIds: ids,
            section: 'personalized_grid',
          );
        }
      } else {
        state = AsyncValue.data(current.copyWith(
          recentListings: allItems,
          recentPage: 1,
          recentExhausted: allItems.length < 20,
        ));
        final ids = allItems
            .whereType<Map<String, dynamic>>()
            .map((e) => e['id'])
            .whereType<int>()
            .take(10)
            .toList();
        if (ids.isNotEmpty) {
          AnalyticsService.logListingImpressions(
            listingIds: ids,
            section: 'recent',
          );
        }
      }
      onData();
    }, onError: (_) {
      final current = state.value;
      if (current != null) {
        state = AsyncValue.data(current.copyWith(exploreNetworkError: true));
      }
      onData();
    });
  }

  Future<void> loadMoreRecentListings() async {
    final current = state.value;
    if (current == null || current.recentExhausted || current.recentLoadingMore || current.hasQuery) return;

    if (current.isLoggedIn) {
      // Client-side windowing — buffer bellekte, API çağrısı yok
      final all = current.allPersonalizedListings;
      final nextCount = current.recentPage * _kPersonalizedChunkSize;
      if (nextCount >= all.length) {
        state = AsyncValue.data(current.copyWith(recentExhausted: true));
        return;
      }
      final nextSlice = all.take(nextCount + _kPersonalizedChunkSize).toList();
      state = AsyncValue.data(current.copyWith(
        recentListings: nextSlice,
        recentPage: current.recentPage + 1,
        recentExhausted: nextSlice.length >= all.length,
      ));
      return;
    }

    // Misafir kullanıcı — /feed/recent API sayfalama
    state = AsyncValue.data(current.copyWith(recentLoadingMore: true));
    try {
      final token = await StorageService.getToken();
      final headers = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
      final excludeParams = current.forYouIds.isNotEmpty
          ? '&exclude_ids=${current.forYouIds.join(',')}'
          : '';
      final url = '$kBaseUrl/feed/recent?page=${current.recentPage}$excludeParams';

      final resp = await http.get(Uri.parse(url), headers: headers);

      final newState = state.value;
      if (newState == null) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        state = AsyncValue.data(newState.copyWith(
          recentListings: [...newState.recentListings, ...data],
          recentPage: newState.recentPage + 1,
          recentExhausted: data.length < 20,
          recentLoadingMore: false,
        ));
      } else {
        state = AsyncValue.data(newState.copyWith(
          recentExhausted: true,
          recentLoadingMore: false,
        ));
      }
    } catch (_) {
      final newState = state.value;
      if (newState != null) {
        state = AsyncValue.data(newState.copyWith(recentLoadingMore: false));
      }
    }
  }

  Future<void> loadMoreForYou() async {
    final current = state.value;
    if (current == null || !current.isLoggedIn || current.forYouExhausted || current.forYouLoadingMore || current.hasQuery) {
      return;
    }
    
    state = AsyncValue.data(current.copyWith(forYouLoadingMore: true));
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        state = AsyncValue.data(state.value!.copyWith(forYouLoadingMore: false));
        return;
      }
      
      final resp = await http.get(
        Uri.parse('$kBaseUrl/feed/for-you?page=${current.forYouPage}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      final newState = state.value;
      if (newState == null) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        final existingIds = newState.exploreListings.map((e) => e['id']).toSet();
        final uniqueData = data.where((e) => !existingIds.contains(e['id'])).toList();
        state = AsyncValue.data(newState.copyWith(
          exploreListings: [...newState.exploreListings, ...uniqueData],
          forYouPage: newState.forYouPage + 1,
          forYouExhausted: data.length < 20,
          forYouLoadingMore: false,
        ));
      } else {
        state = AsyncValue.data(newState.copyWith(
          forYouExhausted: true,
          forYouLoadingMore: false,
        ));
      }
    } catch (_) {
      final newState = state.value;
      if (newState != null) {
        state = AsyncValue.data(newState.copyWith(forYouLoadingMore: false));
      }
    }
  }

  // --- Search Methods ---
  void onQueryChanged(String query) {
    if (query.isEmpty) {
      final current = state.value;
      if (current != null) {
        state = AsyncValue.data(current.copyWith(
          query: '',
          hasQuery: false,
          userResults: [],
          listingResults: [],
          streamResults: [],
          isSemanticSearch: false,
          showAllUsers: false,
        ));
      }
      return;
    }
    
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(
        query: query,
        hasQuery: true,
      ));
    }
  }

  Future<void> search(String query) async {
    final myToken = ++_searchToken;
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(isSearching: true));
    }

    try {
      final token = await StorageService.getToken();
      final headers = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
      final resp = await http.get(
        Uri.parse('$kBaseUrl/search/all').replace(queryParameters: {'q': query}),
        headers: headers,
      );

      if (myToken != _searchToken) return;

      final newState = state.value;
      if (newState == null) return;

      if (resp.statusCode != 200) {
        state = AsyncValue.data(newState.copyWith(isSearching: false));
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final listingResults = (data['listings'] as List).cast<Map<String, dynamic>>();
      final userResults = (data['users'] as List).cast<Map<String, dynamic>>();
      final streamResults = (data['streams'] as List)
          .map((s) => StreamOut.fromJson(s as Map<String, dynamic>))
          .toList();

      final resultCount = listingResults.length + userResults.length + streamResults.length;

      state = AsyncValue.data(newState.copyWith(
        userResults: userResults,
        listingResults: listingResults,
        streamResults: streamResults,
        isSemanticSearch: data['search_type'] == 'semantic',
        showAllUsers: false,
        isSearching: false,
      ));

      AnalyticsService.trackSearch(query: query, resultCount: resultCount);
      if (resultCount == 0) {
        AnalyticsService.trackEvent('search_no_results', {'query': query});
      }
    } catch (_) {
      if (myToken == _searchToken) {
        final newState = state.value;
        if (newState != null) {
          state = AsyncValue.data(newState.copyWith(isSearching: false));
        }
      }
    }
  }

  void setShowAllUsers(bool show) {
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(showAllUsers: show));
    }
  }

  Future<bool> createSearchAlert(String query) async {
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(isAlertCreating: true));
    }
    bool success = false;
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/search-alerts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'query': query}),
      );
      success = (resp.statusCode == 201);
    } catch (_) {
      success = false;
    } finally {
      final newState = state.value;
      if (newState != null) {
        state = AsyncValue.data(newState.copyWith(isAlertCreating: false));
      }
    }
    return success;
  }

  Future<void> markNotInterested(int listingId, String section) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.post(
        Uri.parse('$kBaseUrl/feed/not-interested/$listingId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 204) {
        final current = state.value;
        if (current == null) return;

        if (section == 'for_you') {
          final nForYou = List<dynamic>.from(current.exploreListings)..removeWhere((e) => (e as Map)['id'] == listingId);
          final nIds = Set<int>.from(current.forYouIds)..remove(listingId);
          state = AsyncValue.data(current.copyWith(
            exploreListings: nForYou,
            forYouIds: nIds,
          ));
        } else {
          final nRecent = List<dynamic>.from(current.recentListings)..removeWhere((e) => (e as Map)['id'] == listingId);
          state = AsyncValue.data(current.copyWith(recentListings: nRecent));
        }
      }
    } catch (_) {}
  }
}

final searchViewModelProvider =
    AsyncNotifierProvider.autoDispose<SearchViewModel, SearchState>(() {
  return SearchViewModel();
});
