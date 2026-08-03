import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/listing_filter_state.dart';
import '../../services/analytics_service.dart';
import '../../config/api.dart';

class ListingMetric {
  final String id;
  final String title;
  final String? imageUrl;
  final bool isVideo;
  final int impressions;
  final double ctr;
  final double? completionPct;
  final double? avgPhotoDepth;
  
  const ListingMetric({
    required this.id,
    required this.title,
    this.imageUrl,
    required this.isVideo,
    required this.impressions,
    required this.ctr,
    this.completionPct,
    this.avgPhotoDepth,
  });
}

class ListingAnalyticsState {
  final bool loading;
  final bool hasError;
  final String? selectedListingId;
  final List<ListingMetric> listings;
  final double videoCtr;
  final double photoCtr;
  final int videoImp;
  final int photoImp;
  final ListingFilterState filter;

  const ListingAnalyticsState({
    this.loading = true,
    this.hasError = false,
    this.selectedListingId,
    this.listings = const [],
    this.videoCtr = 0,
    this.photoCtr = 0,
    this.videoImp = 0,
    this.photoImp = 0,
    this.filter = const ListingFilterState(),
  });

  ListingAnalyticsState copyWith({
    bool? loading,
    bool? hasError,
    String? selectedListingId,
    bool clearSelectedListingId = false,
    List<ListingMetric>? listings,
    double? videoCtr,
    double? photoCtr,
    int? videoImp,
    int? photoImp,
    ListingFilterState? filter,
  }) {
    return ListingAnalyticsState(
      loading: loading ?? this.loading,
      hasError: hasError ?? this.hasError,
      selectedListingId: clearSelectedListingId ? null : (selectedListingId ?? this.selectedListingId),
      listings: listings ?? this.listings,
      videoCtr: videoCtr ?? this.videoCtr,
      photoCtr: photoCtr ?? this.photoCtr,
      videoImp: videoImp ?? this.videoImp,
      photoImp: photoImp ?? this.photoImp,
      filter: filter ?? this.filter,
    );
  }
}

class ListingAnalyticsViewModel extends AutoDisposeNotifier<ListingAnalyticsState> {
  @override
  ListingAnalyticsState build() {
    return const ListingAnalyticsState(loading: false);
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, hasError: false);

    final sd = state.filter.dateFrom?.toIso8601String().substring(0, 10);
    final ed = state.filter.dateTo?.toIso8601String().substring(0, 10);
    final cat = (state.filter.category != null && state.filter.category!.isNotEmpty) ? state.filter.category : null;

    try {
      final results = await Future.wait([
        AnalyticsService.getVideoRoi(startDate: sd, endDate: ed, category: cat),
        AnalyticsService.getVideoPerformance(startDate: sd, endDate: ed, category: cat),
        AnalyticsService.getGalleryStats(startDate: sd, endDate: ed, category: cat),
      ]);
      final roi = results[0];
      final videoPerf = results[1];
      final gallery = results[2];

      if (roi == null && videoPerf == null && gallery == null) {
        state = state.copyWith(loading: false, hasError: true);
        return;
      }

      final videoMap = <String, Map<String, dynamic>>{
        for (final s
            in (videoPerf?['stats'] as List? ?? []).cast<Map<String, dynamic>>())
          s['listing_id'].toString(): s,
      };
      final galleryMap = <String, Map<String, dynamic>>{
        for (final s
            in (gallery?['stats'] as List? ?? []).cast<Map<String, dynamic>>())
          s['listing_id'].toString(): s,
      };

      final byListing = (roi?['by_listing'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final merged = byListing.map((l) {
        final lid = l['listing_id'].toString();
        final isVideo = (l['content_type'] as String?) == 'video';
        final rawImg = l['image_url'] as String?;
        final resolvedImg = (rawImg != null && rawImg.isNotEmpty)
            ? (rawImg.startsWith('/uploads') ? '$kBaseHost$rawImg' : '$kBaseUrl$rawImg')
            : null;
        return ListingMetric(
          id: lid,
          title: l['title'] as String? ?? '—',
          imageUrl: resolvedImg,
          isVideo: isVideo,
          impressions: l['impressions'] as int? ?? 0,
          ctr: (l['ctr'] as num?)?.toDouble() ?? 0,
          completionPct: isVideo
              ? (videoMap[lid]?['avg_completion_pct'] as num?)?.toDouble()
              : null,
          avgPhotoDepth: !isVideo
              ? (galleryMap[lid]?['avg_swipe_depth'] as num?)?.toDouble()
              : null,
        );
      }).toList()..sort((a, b) => b.impressions.compareTo(a.impressions));

      final seenIds = <String>{};
      final deduped = merged.where((m) => seenIds.add(m.id)).toList();

      state = state.copyWith(
        loading: false,
        hasError: false,
        listings: deduped,
        videoCtr: (roi?['video']?['ctr'] as num?)?.toDouble() ?? 0,
        photoCtr: (roi?['photo']?['ctr'] as num?)?.toDouble() ?? 0,
        videoImp: roi?['video']?['impressions'] as int? ?? 0,
        photoImp: roi?['photo']?['impressions'] as int? ?? 0,
      );
    } catch (_) {
      state = state.copyWith(loading: false, hasError: true);
    }
  }

  void selectListing(String? id) {
    state = state.copyWith(selectedListingId: id, clearSelectedListingId: id == null);
  }

  void updateFilter(ListingFilterState filter) {
    state = state.copyWith(filter: filter);
    final selectedListingId = state.selectedListingId;
    
    var res = state.listings;
    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      final q = filter.searchQuery!.toLowerCase();
      res = res.where((m) => m.title.toLowerCase().contains(q)).toList();
    }
    
    if (selectedListingId != null && !res.any((m) => m.id == selectedListingId)) {
      state = state.copyWith(clearSelectedListingId: true);
    }
    load();
  }
}

final listingAnalyticsProvider = NotifierProvider.autoDispose<ListingAnalyticsViewModel, ListingAnalyticsState>(
  () => ListingAnalyticsViewModel(),
);
