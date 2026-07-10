import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../config/api.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';

// Basit bellek önbelleği: days → (timestamp, veri)
final _roiCache = <int, (DateTime, Map<String, dynamic>)>{};
final _videoPerfCache = <int, (DateTime, Map<String, dynamic>)>{};
final _galleryCache = <int, (DateTime, Map<String, dynamic>)>{};
const _cacheTtl = Duration(minutes: 5);

class ListingAnalyticsScreen extends StatefulWidget {
  final bool isPremium;
  final bool isEmbedded;
  const ListingAnalyticsScreen({
    super.key,
    required this.isPremium,
    this.isEmbedded = false,
  });

  @override
  State<ListingAnalyticsScreen> createState() => _ListingAnalyticsScreenState();
}

class _ListingAnalyticsScreenState extends State<ListingAnalyticsScreen> {
  int _days = 30;
  bool _loading = true;
  bool _hasError = false;
  String? _selectedListingId;

  List<_ListingMetric> _listings = [];
  double _videoCtr = 0;
  double _photoCtr = 0;
  int _videoImp = 0;
  int _photoImp = 0;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  List<_ListingMetric> get _filteredListings => _searchQuery.isEmpty
      ? _listings
      : _listings.where((m) => m.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

  @override
  void initState() {
    super.initState();
    if (widget.isPremium) {
      _load();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _fromCache<T>(Map<int, (DateTime, Map<String, dynamic>)> cache) {
    final entry = cache[_days];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$1) > _cacheTtl) {
      cache.remove(_days);
      return null;
    }
    return entry.$2;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });

    var roi = _fromCache(_roiCache);
    var videoPerf = _fromCache(_videoPerfCache);
    var gallery = _fromCache(_galleryCache);

    if (roi == null || videoPerf == null || gallery == null) {
      final results = await Future.wait([
        roi == null ? AnalyticsService.getVideoRoi(days: _days) : Future.value(roi),
        videoPerf == null ? AnalyticsService.getVideoPerformance(days: _days) : Future.value(videoPerf),
        gallery == null ? AnalyticsService.getGalleryStats(days: _days) : Future.value(gallery),
      ]);
      roi = results[0];
      videoPerf = results[1];
      gallery = results[2];
      final now = DateTime.now();
      if (roi != null) _roiCache[_days] = (now, roi);
      if (videoPerf != null) _videoPerfCache[_days] = (now, videoPerf);
      if (gallery != null) _galleryCache[_days] = (now, gallery);
    }

    if (!mounted) return;

    if (roi == null && videoPerf == null && gallery == null) {
      setState(() {
        _loading = false;
        _hasError = true;
      });
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
      return _ListingMetric(
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

    setState(() {
      _loading = false;
      _hasError = false;
      _listings = deduped;
      _videoCtr = (roi?['video']?['ctr'] as num?)?.toDouble() ?? 0;
      _photoCtr = (roi?['photo']?['ctr'] as num?)?.toDouble() ?? 0;
      _videoImp = roi?['video']?['impressions'] as int? ?? 0;
      _photoImp = roi?['photo']?['impressions'] as int? ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final bodyContent = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_hasError && widget.isPremium)
        ? _buildError(l)
        : Stack(
            children: [
              _buildContent(l),
              if (!widget.isPremium) _buildPaywall(context, l),
            ],
          );

    if (widget.isEmbedded) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.proToolListingsTitle),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: bodyContent,
    );
  }

  Widget _buildError(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_outlined,
            size: 48,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(height: 12),
          Text(
            l.proLoadFailed,
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: Text(l.btnRetry)),
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations l) {
    final _ListingMetric? selectedItem = _selectedListingId == null
        ? null
        : _listings.where((m) => m.id == _selectedListingId).firstOrNull;

    final displayImp = selectedItem != null
        ? selectedItem.impressions
        : (_videoImp + _photoImp);
    final displayCtr = selectedItem != null
        ? selectedItem.ctr
        : (_videoImp + _photoImp > 0
              ? ((_videoCtr * _videoImp + _photoCtr * _photoImp) /
                    (_videoImp + _photoImp))
              : 0.0);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        shrinkWrap: widget.isEmbedded,
        physics: widget.isEmbedded
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _DayFilter(
            days: _days,
            l: l,
            onChanged: (d) {
              setState(() => _days = d);
              _load();
            },
          ),
          const SizedBox(height: 12),

          if (_listings.isNotEmpty) ...[
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l.searchHintTextListing,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchQuery = '';
                            if (_selectedListingId != null &&
                                !_filteredListings.any((m) => m.id == _selectedListingId)) {
                              _selectedListingId = null;
                            }
                          });
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) {
                setState(() {
                  _searchQuery = v;
                  if (_selectedListingId != null &&
                      !_filteredListings.any((m) => m.id == _selectedListingId)) {
                    _selectedListingId = null;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
          ],

          if (_listings.isNotEmpty) ...[
            // Horizontal Carousel for Selection
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _filteredListings.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final isSelected = _selectedListingId == null;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedListingId = null),
                      child: Container(
                        width: 90,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                              : AppColors.card(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6366F1)
                                : AppColors.border(context),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.dashboard_outlined,
                              color: isSelected
                                  ? const Color(0xFF6366F1)
                                  : AppColors.textSecondary(context),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l.liveAllCategory, // "Tümü" / "All"
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF6366F1)
                                    : AppColors.textPrimary(context),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final metric = _filteredListings[index - 1];
                  final isSelected = _selectedListingId == metric.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedListingId = metric.id),
                    child: Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF6366F1)
                              : AppColors.border(context),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Arka plan: resim varsa göster, yoksa gri
                          if (metric.imageUrl != null)
                            CachedNetworkImage(
                              imageUrl: metric.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: AppColors.surfaceVariant(context),
                              ),
                            )
                          else
                            Container(color: AppColors.surfaceVariant(context)),
                          // Gradient + başlık
                          Positioned(
                            left: 0, right: 0, bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black87],
                                ),
                              ),
                              child: Text(
                                metric.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          // Video rozeti
                          if (metric.isVideo)
                            Positioned(
                              top: 6, right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                              ),
                            ),
                          // Seçim halkas
                          if (isSelected)
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFF6366F1), width: 2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Metrics Display Area
            Row(
              children: [
                _SummaryTile(
                  label: l.listingTotalViews,
                  value: '+${_fmt(displayImp)}',
                  icon: Icons.visibility_outlined,
                  color: const Color(0xFF6366F1),
                ),
                const SizedBox(width: 10),
                _SummaryTile(
                  label: l.listingAvgCtr,
                  value: '%${displayCtr.toStringAsFixed(1)}',
                  icon: Icons.ads_click_outlined,
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (selectedItem == null && _videoImp > 0 && _photoImp > 0)
              _ComparisonCard(videoCtr: _videoCtr, photoCtr: _photoCtr, l: l),

            if (selectedItem != null) ...[
              const SizedBox(height: 16),
              if (selectedItem.isVideo && selectedItem.completionPct != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEC4899).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.av_timer,
                          color: Color(0xFFEC4899),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.listingVideoComplete,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '%${selectedItem.completionPct!.toStringAsFixed(1)}',
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (!selectedItem.isVideo && selectedItem.avgPhotoDepth != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.collections,
                          color: Color(0xFFF59E0B),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.listingGalleryLabel,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedItem.avgPhotoDepth! > 1.5
                                  ? l.listingGalleryDeep(
                                      selectedItem.avgPhotoDepth!
                                          .toStringAsFixed(1),
                                    )
                                  : l.listingGalleryShallow,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],

          if (_listings.isEmpty)
            _EmptyState(
              icon: Icons.bar_chart_outlined,
              title: l.listingNoDataTitle,
              subtitle: l.listingNoDataDesc,
            ),
        ],
      ),
    );
  }

  Widget _buildPaywall(BuildContext context, AppLocalizations l) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: AppColors.bg(context).withValues(alpha: 0.6),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: AppColors.isDark(context) ? 0.5 : 0.12,
                      ),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.bar_chart_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l.proUpgradeTitle,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.listingPaywallDesc,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary(context),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () => launchUrl(
                            Uri.parse('https://www.teqlif.com/pro-plan.html'),
                            mode: LaunchMode.inAppWebView,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            l.proUpgradeBtn,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)} bin';
    return '$n';
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _ListingMetric {
  final String id;
  final String title;
  final String? imageUrl;
  final bool isVideo;
  final int impressions;
  final double ctr;
  final double? completionPct;
  final double? avgPhotoDepth;
  const _ListingMetric({
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

// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _DayFilter extends StatelessWidget {
  final int days;
  final AppLocalizations l;
  final ValueChanged<int> onChanged;
  const _DayFilter({
    required this.days,
    required this.l,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [7, 30].map((d) {
        final active = days == d;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: d == 7 ? 6 : 0,
              left: d == 30 ? 6 : 0,
            ),
            child: GestureDetector(
              onTap: () {
                if (days != d) onChanged(d);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF6366F1)
                      : AppColors.card(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF6366F1)
                        : AppColors.border(context),
                  ),
                ),
                child: Text(
                  l.listingDayFilterN(d),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: active
                        ? Colors.white
                        : AppColors.textPrimary(context),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final double videoCtr;
  final double photoCtr;
  final AppLocalizations l;
  const _ComparisonCard({
    required this.videoCtr,
    required this.photoCtr,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final String message;
    if (videoCtr == 0 && photoCtr == 0) return const SizedBox.shrink();
    if (photoCtr > 0 && videoCtr > photoCtr * 1.1) {
      final x = (videoCtr / photoCtr).toStringAsFixed(1);
      message = l.listingVideoBeatsPhoto(x);
    } else if (videoCtr > 0 && photoCtr > videoCtr * 1.1) {
      final x = (photoCtr / videoCtr).toStringAsFixed(1);
      message = l.listingPhotoBeatsVideo(x);
    } else {
      message = l.listingMediaEqual;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SegChip(emoji: '🎬', label: l.listingVideoLabel, ctr: videoCtr),
              const SizedBox(width: 8),
              _SegChip(emoji: '📸', label: l.listingPhotoLabel, ctr: photoCtr),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegChip extends StatelessWidget {
  final String emoji;
  final String label;
  final double ctr;
  const _SegChip({required this.emoji, required this.label, required this.ctr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$emoji $label  %${ctr.toStringAsFixed(1)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary(context),
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final _ListingMetric metric;
  final AppLocalizations l;
  const _ListingCard({required this.metric, required this.l});

  @override
  Widget build(BuildContext context) {
    final ctrColor = metric.ctr >= 10
        ? const Color(0xFF22C55E)
        : metric.ctr >= 5
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);

    String? extraLabel;
    String? extraValue;
    Color extraColor = const Color(0xFF6366F1);
    if (metric.isVideo && metric.completionPct != null) {
      extraLabel = l.listingWatchRateLabel;
      extraValue = l.listingWatchedPct(
        metric.completionPct!.toStringAsFixed(0),
      );
      extraColor = metric.completionPct! >= 60
          ? const Color(0xFF22C55E)
          : metric.completionPct! >= 30
          ? const Color(0xFFF59E0B)
          : const Color(0xFFEF4444);
    } else if (!metric.isVideo && metric.avgPhotoDepth != null) {
      final depth = metric.avgPhotoDepth!;
      extraLabel = l.listingGalleryLabel;
      extraValue = depth >= 2
          ? l.listingGalleryDeep(depth.toStringAsFixed(0))
          : l.listingGalleryShallow;
      extraColor = depth >= 3
          ? const Color(0xFF22C55E)
          : depth >= 1.5
          ? const Color(0xFFF59E0B)
          : const Color(0xFF94A3B8);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                metric.isVideo ? '🎬' : '📸',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MetricPill(
                icon: Icons.visibility_outlined,
                value: '+${_fmtNum(metric.impressions)}',
                label: l.metricViewed,
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(width: 8),
              _MetricPill(
                icon: Icons.ads_click_outlined,
                value: '%${metric.ctr.toStringAsFixed(1)}',
                label: l.listingCtrExplain(metric.ctr.toStringAsFixed(1)),
                color: ctrColor,
              ),
              if (extraValue != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: extraColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          extraValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: extraColor,
                          ),
                        ),
                        Text(
                          extraLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _fmtNum(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)} bin';
    return '$n';
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _MetricPill({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(icon, size: 52, color: AppColors.textSecondary(context)),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary(context),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
