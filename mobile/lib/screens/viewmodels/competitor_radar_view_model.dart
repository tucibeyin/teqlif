import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';
import '../../services/cache_service.dart';
import '../../services/listing_service.dart';
import '../../models/listing_filter_state.dart';

class CompetitorRadarState {
  final List<Map<String, dynamic>> listings;
  final bool listingsLoading;
  final Map<String, dynamic>? selectedListing;
  final Map<String, dynamic>? radarData;
  final Map<String, dynamic>? velocityData;
  final bool loadingData;
  final ListingFilterState filter;

  const CompetitorRadarState({
    this.listings = const [],
    this.listingsLoading = true,
    this.selectedListing,
    this.radarData,
    this.velocityData,
    this.loadingData = false,
    this.filter = const ListingFilterState(),
  });

  CompetitorRadarState copyWith({
    List<Map<String, dynamic>>? listings,
    bool? listingsLoading,
    Map<String, dynamic>? selectedListing,
    bool clearSelectedListing = false,
    Map<String, dynamic>? radarData,
    bool clearRadarData = false,
    Map<String, dynamic>? velocityData,
    bool clearVelocityData = false,
    bool? loadingData,
    ListingFilterState? filter,
  }) {
    return CompetitorRadarState(
      listings: listings ?? this.listings,
      listingsLoading: listingsLoading ?? this.listingsLoading,
      selectedListing:
          clearSelectedListing ? null : (selectedListing ?? this.selectedListing),
      radarData: clearRadarData ? null : (radarData ?? this.radarData),
      velocityData: clearVelocityData ? null : (velocityData ?? this.velocityData),
      loadingData: loadingData ?? this.loadingData,
      filter: filter ?? this.filter,
    );
  }
}

class CompetitorRadarViewModel extends AutoDisposeNotifier<CompetitorRadarState> {
  CacheService get _cache => ref.read(cacheServiceProvider);

  static String _radarKey(int id) => 'cache_radar_$id';
  static String _velocityKey(int id) => 'cache_velocity_$id';

  StreamSubscription<List<Map<String, dynamic>>>? _listingsSub;

  @override
  CompetitorRadarState build() {
    final listingService = ref.read(listingServiceProvider);
    final cachedListings = listingService.getCachedMyActiveListings();
    final listings = cachedListings != null
        ? (cachedListings as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    Map<String, dynamic>? selectedListing =
        listings.isNotEmpty ? listings.first : null;
    Map<String, dynamic>? radarData;
    Map<String, dynamic>? velocityData;

    if (selectedListing != null) {
      final id = selectedListing['id'] as int;
      radarData =
          _cache.getWithStaleness(_radarKey(id))?.data as Map<String, dynamic>?;
      velocityData =
          _cache.getWithStaleness(_velocityKey(id))?.data as Map<String, dynamic>?;
    }

    ref.onDispose(() => _listingsSub?.cancel());

    Future.microtask(() => loadListings());

    return CompetitorRadarState(
      listings: listings,
      listingsLoading: listings.isEmpty,
      selectedListing: selectedListing,
      radarData: radarData,
      velocityData: velocityData,
      loadingData: selectedListing != null && radarData == null,
    );
  }

  Future<void> loadListings() async {
    final hasCache = state.listings.isNotEmpty;
    if (!hasCache) state = state.copyWith(listingsLoading: true);

    _listingsSub?.cancel();
    _listingsSub = ref
        .read(listingServiceProvider)
        .getMyActiveListings(
          query: state.filter.searchQuery,
          category: state.filter.category,
          subcategory: state.filter.subcategory,
        )
        .listen(
      (results) {
        final prevId = state.selectedListing?['id'];
        final stillHere =
            prevId != null ? results.any((r) => r['id'] == prevId) : false;
        final nextSelected =
            stillHere ? state.selectedListing : (results.isNotEmpty ? results.first : null);

        state = state.copyWith(
          listings: results,
          listingsLoading: false,
          selectedListing: nextSelected,
          clearSelectedListing: nextSelected == null,
        );

        if (nextSelected != null) {
          loadData();
        }
      },
      onError: (_) {
        state = state.copyWith(listingsLoading: false);
      },
    );
  }

  Future<void> loadData() async {
    final listing = state.selectedListing;
    if (listing == null) return;
    final id = listing['id'] as int;
    final category = listing['category'] as String? ?? '';

    final cachedRadar =
        _cache.getWithStaleness(_radarKey(id))?.data as Map<String, dynamic>?;
    final cachedVelocity =
        _cache.getWithStaleness(_velocityKey(id))?.data as Map<String, dynamic>?;

    if (cachedRadar != null) {
      state = state.copyWith(
        radarData: cachedRadar,
        velocityData: cachedVelocity,
        loadingData: false,
      );
    } else {
      state = state.copyWith(
          loadingData: true, clearRadarData: true, clearVelocityData: true);
    }

    try {
      final results = await Future.wait([
        ref.read(analyticsServiceProvider).competitorRadar(id),
        ref.read(analyticsServiceProvider).categoryVelocity(category, listingId: id),
      ]);

      state = state.copyWith(
        radarData: results[0],
        velocityData: results[1],
        loadingData: false,
      );
      if (results[0] != null) {
        await _cache.saveData(_radarKey(id), results[0], ttl: const Duration(minutes: 30));
      }
      if (results[1] != null) {
        await _cache.saveData(_velocityKey(id), results[1],
            ttl: const Duration(minutes: 30));
      }
    } catch (_) {
      state = state.copyWith(loadingData: false);
    }
  }

  void updateFilter(ListingFilterState filter) {
    state = state.copyWith(filter: filter);
    loadListings();
  }

  void selectListing(Map<String, dynamic> listing) {
    if (state.selectedListing != null &&
        state.selectedListing!['id'] == listing['id']) {
      return;
    }
    state = state.copyWith(selectedListing: listing);
    loadData();
  }
}

final competitorRadarProvider =
    NotifierProvider.autoDispose<CompetitorRadarViewModel, CompetitorRadarState>(
  () => CompetitorRadarViewModel(),
);
