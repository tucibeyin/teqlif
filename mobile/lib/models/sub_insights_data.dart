class ProKpis {
  final double revenue30d;
  final double? revenueGrowthPct;
  final int sales30d;
  final int bids30d;
  final int activeListings;
  final double totalRevenue;

  const ProKpis({
    required this.revenue30d,
    this.revenueGrowthPct,
    required this.sales30d,
    required this.bids30d,
    required this.activeListings,
    required this.totalRevenue,
  });

  factory ProKpis.fromJson(Map<String, dynamic> j) => ProKpis(
        revenue30d: (j['revenue_30d'] as num?)?.toDouble() ?? 0,
        revenueGrowthPct: (j['revenue_growth_pct'] as num?)?.toDouble(),
        sales30d: (j['sales_30d'] as num?)?.toInt() ?? 0,
        bids30d: (j['bids_30d'] as num?)?.toInt() ?? 0,
        activeListings: (j['active_listings'] as num?)?.toInt() ?? 0,
        totalRevenue: (j['total_revenue'] as num?)?.toDouble() ?? 0,
      );

  static const empty = ProKpis(
    revenue30d: 0,
    sales30d: 0,
    bids30d: 0,
    activeListings: 0,
    totalRevenue: 0,
  );
}

class ProFunnel {
  final int views;
  final int dwells;
  final int hesitations;
  final int bids;
  final int sales;
  final double viewToBidPct;
  final double bidToSalePct;

  const ProFunnel({
    required this.views,
    required this.dwells,
    required this.hesitations,
    required this.bids,
    required this.sales,
    required this.viewToBidPct,
    required this.bidToSalePct,
  });

  factory ProFunnel.fromJson(Map<String, dynamic> j) => ProFunnel(
        views: (j['views'] as num?)?.toInt() ?? 0,
        dwells: (j['dwells'] as num?)?.toInt() ?? 0,
        hesitations: (j['hesitations'] as num?)?.toInt() ?? 0,
        bids: (j['bids'] as num?)?.toInt() ?? 0,
        sales: (j['sales'] as num?)?.toInt() ?? 0,
        viewToBidPct: (j['view_to_bid_pct'] as num?)?.toDouble() ?? 0,
        bidToSalePct: (j['bid_to_sale_pct'] as num?)?.toDouble() ?? 0,
      );

  static const empty = ProFunnel(
    views: 0, dwells: 0, hesitations: 0, bids: 0, sales: 0,
    viewToBidPct: 0, bidToSalePct: 0,
  );
}

class HotLead {
  final int listingId;
  final String title;
  final double? price;
  final String category;
  final String? subcategory;
  final int views30d;
  final int hesitations30d;
  final int heatScore;
  final bool isBoosted;

  const HotLead({
    required this.listingId,
    required this.title,
    this.price,
    required this.category,
    this.subcategory,
    required this.views30d,
    required this.hesitations30d,
    required this.heatScore,
    required this.isBoosted,
  });

  factory HotLead.fromJson(Map<String, dynamic> j) => HotLead(
        listingId: (j['listing_id'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble(),
        category: j['category'] as String? ?? '',
        subcategory: j['subcategory'] as String?,
        views30d: (j['views_30d'] as num?)?.toInt() ?? 0,
        hesitations30d: (j['hesitations_30d'] as num?)?.toInt() ?? 0,
        heatScore: (j['heat_score'] as num?)?.toInt() ?? 0,
        isBoosted: j['is_boosted'] as bool? ?? false,
      );
}

class PriceIntel {
  final int listingId;
  final String title;
  final double yourPrice;
  final double marketAvg;
  final double diffPct;
  final String signal;
  final String? category;
  final String? subcategory;

  const PriceIntel({
    required this.listingId,
    required this.title,
    required this.yourPrice,
    required this.marketAvg,
    required this.diffPct,
    required this.signal,
    this.category,
    this.subcategory,
  });

  factory PriceIntel.fromJson(Map<String, dynamic> j) => PriceIntel(
        listingId: (j['listing_id'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        yourPrice: (j['your_price'] as num?)?.toDouble() ?? 0,
        marketAvg: (j['market_avg'] as num?)?.toDouble() ?? 0,
        diffPct: (j['diff_pct'] as num?)?.toDouble() ?? 0,
        signal: j['signal'] as String? ?? 'uygun',
        category: j['category'] as String?,
        subcategory: j['subcategory'] as String?,
      );
}

class BestStream {
  final String title;
  final int viewers;
  final int bids;
  final int durationMin;

  const BestStream({
    required this.title,
    required this.viewers,
    required this.bids,
    required this.durationMin,
  });

  factory BestStream.fromJson(Map<String, dynamic> j) => BestStream(
        title: j['title'] as String? ?? '',
        viewers: (j['viewers'] as num?)?.toInt() ?? 0,
        bids: (j['bids'] as num?)?.toInt() ?? 0,
        durationMin: (j['duration_min'] as num?)?.toInt() ?? 0,
      );
}

class StreamStats {
  final int totalStreams;
  final int streams30d;
  final double avgViewers;
  final int peakViewers;
  final double avgDurationMin;
  final List<BestStream> bestStreams;

  const StreamStats({
    required this.totalStreams,
    required this.streams30d,
    required this.avgViewers,
    required this.peakViewers,
    required this.avgDurationMin,
    required this.bestStreams,
  });

  factory StreamStats.fromJson(Map<String, dynamic> j) => StreamStats(
        totalStreams: (j['total_streams'] as num?)?.toInt() ?? 0,
        streams30d: (j['streams_30d'] as num?)?.toInt() ?? 0,
        avgViewers: (j['avg_viewers'] as num?)?.toDouble() ?? 0,
        peakViewers: (j['peak_viewers'] as num?)?.toInt() ?? 0,
        avgDurationMin: (j['avg_duration_min'] as num?)?.toDouble() ?? 0,
        bestStreams: (j['best_streams'] as List?)
                ?.map((e) => BestStream.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  static const empty = StreamStats(
    totalStreams: 0, streams30d: 0, avgViewers: 0,
    peakViewers: 0, avgDurationMin: 0, bestStreams: [],
  );
}

class PeakHour {
  final String label;
  final int count;

  const PeakHour({required this.label, required this.count});

  factory PeakHour.fromJson(Map<String, dynamic> j) => PeakHour(
        label: j['label'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

class ProTip {
  final String icon;
  final String type;
  final String title;
  final String body;

  const ProTip({
    required this.icon,
    required this.type,
    required this.title,
    required this.body,
  });

  factory ProTip.fromJson(Map<String, dynamic> j) => ProTip(
        icon: j['icon'] as String? ?? '💡',
        type: j['type'] as String? ?? 'general',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
      );
}

class SearchVisibility {
  final String category;
  final int searchCount;

  const SearchVisibility({required this.category, required this.searchCount});

  factory SearchVisibility.fromJson(Map<String, dynamic> j) => SearchVisibility(
        category: j['category'] as String? ?? '',
        searchCount: (j['search_count'] as num?)?.toInt() ?? 0,
      );
}

class ProMetrics {
  final double? avgDetailDwellSeconds;
  final int? bestPostingHour;
  final double? returnViewerRatePct;
  final List<SearchVisibility> searchVisibility;

  const ProMetrics({
    this.avgDetailDwellSeconds,
    this.bestPostingHour,
    this.returnViewerRatePct,
    required this.searchVisibility,
  });

  factory ProMetrics.fromJson(Map<String, dynamic> j) => ProMetrics(
        avgDetailDwellSeconds:
            (j['avg_detail_dwell_seconds'] as num?)?.toDouble(),
        bestPostingHour: (j['best_posting_hour'] as num?)?.toInt(),
        returnViewerRatePct: (j['return_viewer_rate_pct'] as num?)?.toDouble(),
        searchVisibility: (j['search_visibility'] as List?)
                ?.map((e) =>
                    SearchVisibility.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class ProInsightsData {
  final ProKpis kpis;
  final ProFunnel funnel;
  final List<HotLead> hotLeads;
  final List<PriceIntel> priceIntel;
  final StreamStats streamStats;
  final List<PeakHour> peakHours;
  final List<ProTip> tips;

  const ProInsightsData({
    required this.kpis,
    required this.funnel,
    required this.hotLeads,
    required this.priceIntel,
    required this.streamStats,
    required this.peakHours,
    required this.tips,
  });

  factory ProInsightsData.fromJson(Map<String, dynamic> j) => ProInsightsData(
        kpis: ProKpis.fromJson((j['kpis'] as Map<String, dynamic>?) ?? {}),
        funnel:
            ProFunnel.fromJson((j['funnel'] as Map<String, dynamic>?) ?? {}),
        hotLeads: (j['hot_leads'] as List?)
                ?.map((e) => HotLead.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        priceIntel: (j['price_intel'] as List?)
                ?.map((e) => PriceIntel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        streamStats: StreamStats.fromJson(
            (j['stream_stats'] as Map<String, dynamic>?) ?? {}),
        peakHours: (j['peak_hours'] as List?)
                ?.map((e) => PeakHour.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        tips: (j['tips'] as List?)
                ?.map((e) => ProTip.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
