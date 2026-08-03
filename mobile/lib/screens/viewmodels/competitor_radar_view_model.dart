import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';
import '../../services/analytics_service.dart';
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
      selectedListing: clearSelectedListing ? null : (selectedListing ?? this.selectedListing),
      radarData: clearRadarData ? null : (radarData ?? this.radarData),
      velocityData: clearVelocityData ? null : (velocityData ?? this.velocityData),
      loadingData: loadingData ?? this.loadingData,
      filter: filter ?? this.filter,
    );
  }
}

class CompetitorRadarViewModel extends AutoDisposeNotifier<CompetitorRadarState> {
  @override
  CompetitorRadarState build() {
    Future.microtask(() => loadListings());
    return const CompetitorRadarState();
  }

  Future<List<Map<String, dynamic>>> _fetchListingsPage(int offset) async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    var url = '$kBaseUrl/listings/my?limit=50&offset=$offset&active=true';
    if (state.filter.searchQuery != null && state.filter.searchQuery!.isNotEmpty) {
      url += '&q=${Uri.encodeComponent(state.filter.searchQuery!)}';
    }
    if (state.filter.category != null && state.filter.category!.isNotEmpty) {
      url += '&category=${Uri.encodeComponent(state.filter.category!)}';
    }
    if (state.filter.dateFrom != null && state.filter.dateTo != null) {
      url += '&date_from=${state.filter.dateFrom!.toIso8601String().substring(0, 10)}';
      url += '&date_to=${state.filter.dateTo!.toIso8601String().substring(0, 10)}';
    }
    try {
      final resp = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<void> loadListings() async {
    state = state.copyWith(listingsLoading: true);
    final results = await _fetchListingsPage(0);
    final prevId = state.selectedListing?['id'];
    final stillHere = prevId != null ? results.any((r) => r['id'] == prevId) : false;
    
    Map<String, dynamic>? nextSelected = state.selectedListing;
    if (!stillHere) {
      nextSelected = results.isNotEmpty ? results.first : null;
    }
    
    state = state.copyWith(
      listings: results,
      listingsLoading: false,
      selectedListing: nextSelected,
      clearSelectedListing: nextSelected == null,
    );
    
    if (nextSelected != null) {
      await loadData();
    }
  }

  Future<void> loadData() async {
    final listing = state.selectedListing;
    if (listing == null) return;
    final id = listing['id'] as int;
    final category = listing['category'] as String? ?? '';
    
    state = state.copyWith(
      loadingData: true,
      clearRadarData: true,
      clearVelocityData: true,
    );
    
    try {
      final results = await Future.wait([
        AnalyticsService.competitorRadar(id),
        AnalyticsService.categoryVelocity(category, listingId: id),
      ]);
      
      state = state.copyWith(
        radarData: results[0],
        velocityData: results[1],
        loadingData: false,
      );
    } catch (_) {
      state = state.copyWith(loadingData: false);
    }
  }
  
  void updateFilter(ListingFilterState filter) {
    state = state.copyWith(filter: filter);
    loadListings();
  }
  
  void selectListing(Map<String, dynamic> listing) {
    if (state.selectedListing != null && state.selectedListing!['id'] == listing['id']) return;
    state = state.copyWith(selectedListing: listing);
    loadData();
  }
}

final competitorRadarProvider = NotifierProvider.autoDispose<CompetitorRadarViewModel, CompetitorRadarState>(
  () => CompetitorRadarViewModel(),
);
