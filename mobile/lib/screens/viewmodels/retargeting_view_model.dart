import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../services/storage_service.dart';
import '../../services/analytics_service.dart';
import '../../services/cache_service.dart';
import '../../models/listing_filter_state.dart';

class RetargetingState {
  final Map<String, dynamic>? selectedListing;
  final Map<String, dynamic>? audienceData;
  final bool loadingAudience;
  final bool sending;
  final bool sent;
  final int sentCount;
  final int blastCooldownSeconds;
  
  final int? selectedReportListingId;
  final List<Map<String, dynamic>> reportListings;
  final AsyncValue<Map<String, dynamic>> reportData;
  
  final ListingFilterState reportFilter;
  final ListingFilterState campaignFilter;

  const RetargetingState({
    this.selectedListing,
    this.audienceData,
    this.loadingAudience = false,
    this.sending = false,
    this.sent = false,
    this.sentCount = 0,
    this.blastCooldownSeconds = 0,
    this.selectedReportListingId,
    this.reportListings = const [],
    this.reportData = const AsyncValue.loading(),
    this.reportFilter = const ListingFilterState(),
    this.campaignFilter = const ListingFilterState(),
  });

  RetargetingState copyWith({
    Map<String, dynamic>? selectedListing,
    Map<String, dynamic>? audienceData,
    bool? loadingAudience,
    bool? sending,
    bool? sent,
    int? sentCount,
    int? blastCooldownSeconds,
    int? selectedReportListingId,
    List<Map<String, dynamic>>? reportListings,
    AsyncValue<Map<String, dynamic>>? reportData,
    ListingFilterState? reportFilter,
    ListingFilterState? campaignFilter,
  }) {
    return RetargetingState(
      selectedListing: selectedListing ?? this.selectedListing,
      audienceData: audienceData ?? this.audienceData,
      loadingAudience: loadingAudience ?? this.loadingAudience,
      sending: sending ?? this.sending,
      sent: sent ?? this.sent,
      sentCount: sentCount ?? this.sentCount,
      blastCooldownSeconds: blastCooldownSeconds ?? this.blastCooldownSeconds,
      selectedReportListingId: selectedReportListingId != null ? (selectedReportListingId == -1 ? null : selectedReportListingId) : this.selectedReportListingId,
      reportListings: reportListings ?? this.reportListings,
      reportData: reportData ?? this.reportData,
      reportFilter: reportFilter ?? this.reportFilter,
      campaignFilter: campaignFilter ?? this.campaignFilter,
    );
  }
}

class RetargetingViewModel extends AutoDisposeNotifier<RetargetingState> {
  Timer? _countdownTimer;

  @override
  RetargetingState build() {
    ref.onDispose(() {
      _countdownTimer?.cancel();
    });
    return const RetargetingState();
  }
  
  void init(int? initialListingId) {
    state = state.copyWith(selectedReportListingId: initialListingId ?? -1);
    _loadReportListings();
    _fetchReport(initialListingId);
  }

  Future<void> _loadReportListings() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/my?limit=20&offset=0&active=true'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final listings = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
        state = state.copyWith(reportListings: listings);
        if (state.selectedListing == null && listings.isNotEmpty) {
          state = state.copyWith(selectedListing: listings.first);
          loadAudience();
        }
      }
    } catch (_) {}
  }

  void selectReportListing(int? listingId) {
    state = state.copyWith(selectedReportListingId: listingId ?? -1);
    _fetchReport(listingId);
  }
  
  void updateReportFilter(ListingFilterState filter) {
    state = state.copyWith(reportFilter: filter);
  }
  
  void updateCampaignFilter(ListingFilterState filter) {
    state = state.copyWith(campaignFilter: filter);
  }
  
  void selectCampaignListing(Map<String, dynamic> item) {
    if (state.selectedListing?['id'] != item['id']) {
      state = state.copyWith(selectedListing: item);
      loadAudience();
    }
  }

  Future<void> _fetchReport(int? listingId) async {
    state = state.copyWith(reportData: const AsyncValue.loading());
    try {
      final data = await AnalyticsService.getMassNotificationReport(listingId: listingId);
      state = state.copyWith(reportData: AsyncValue.data(data));
    } catch (e, st) {
      state = state.copyWith(reportData: AsyncValue.error(e, st));
    }
  }

  Future<void> loadAudience() async {
    final listing = state.selectedListing;
    if (listing == null) return;
    
    state = state.copyWith(
      loadingAudience: true,
      audienceData: null,
      sent: false,
      blastCooldownSeconds: 0,
    );
    
    final listingId = listing['id'] as int;
    try {
      final results = await Future.wait([
        AnalyticsService.retargetingAudience(listingId),
        AnalyticsService.getNotificationCooldown(listingId),
      ]);
      
      final audienceData = results[0] as Map<String, dynamic>?;
      final cooldown = (results[1] as int?) ?? 0;
      
      state = state.copyWith(
        audienceData: audienceData,
        blastCooldownSeconds: cooldown,
        loadingAudience: false,
      );
      
      if (cooldown > 0) _startCountdown();
    } catch (_) {
      state = state.copyWith(loadingAudience: false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.blastCooldownSeconds > 0) {
        state = state.copyWith(blastCooldownSeconds: state.blastCooldownSeconds - 1);
      } else {
        _countdownTimer?.cancel();
        state = state.copyWith(sent: false);
      }
    });
  }
  
  Future<Map<String, dynamic>?> sendBlast(int actualCount, int tuciCost) async {
    final listing = state.selectedListing;
    if (listing == null) return null;
    
    state = state.copyWith(sending: true);
    final result = await AnalyticsService.sendRetargeting(
      listingId: listing['id'] as int,
      estimatedAudience: actualCount,
      estimatedCost: tuciCost,
      recipientCount: actualCount,
    );
    
    if (result != null && result['error'] == null) {
      CacheService.clearData('user_wallet_data');
      final sent = result['sent'] as int? ?? actualCount;
      state = state.copyWith(
        sent: true,
        sentCount: sent,
        blastCooldownSeconds: 86400,
        sending: false,
      );
      _startCountdown();
      return result;
    }
    
    state = state.copyWith(sending: false);
    return result;
  }
}

final retargetingProvider = NotifierProvider.autoDispose<RetargetingViewModel, RetargetingState>(
  () => RetargetingViewModel(),
);
