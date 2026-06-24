import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';

class ListingAnalyticsScreen extends StatefulWidget {
  final bool isPremium;
  const ListingAnalyticsScreen({super.key, required this.isPremium});

  @override
  State<ListingAnalyticsScreen> createState() => _ListingAnalyticsScreenState();
}

class _ListingAnalyticsScreenState extends State<ListingAnalyticsScreen> {
  int _days = 30;
  bool _loading = true;
  String? _error;

  // Birleştirilmiş ilan verisi
  List<_ListingMetric> _listings = [];
  double _videoCtr = 0;
  double _photoCtr = 0;
  int _videoImp = 0;
  int _photoImp = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isPremium) _load();
    else setState(() => _loading = false);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    // 3 kaynaktan paralel veri çek
    final results = await Future.wait([
      AnalyticsService.getVideoRoi(days: _days),
      AnalyticsService.getVideoPerformance(days: _days),
      AnalyticsService.getGalleryStats(days: _days),
    ]);

    if (!mounted) return;

    final roi       = results[0];
    final videoPerf = results[1];
    final gallery   = results[2];

    if (roi == null && videoPerf == null && gallery == null) {
      setState(() { _loading = false; _error = 'Veriler yüklenemedi.'; });
      return;
    }

    // Hız tabloları: listing_id → metrik
    final videoMap = <String, Map<String, dynamic>>{
      for (final s in (videoPerf?['stats'] as List? ?? []).cast<Map<String, dynamic>>())
        s['listing_id'].toString(): s,
    };
    final galleryMap = <String, Map<String, dynamic>>{
      for (final s in (gallery?['stats'] as List? ?? []).cast<Map<String, dynamic>>())
        s['listing_id'].toString(): s,
    };

    final byListing = (roi?['by_listing'] as List? ?? []).cast<Map<String, dynamic>>();
    final merged = byListing.map((l) {
      final lid = l['listing_id'].toString();
      final isVideo = (l['content_type'] as String?) == 'video';
      return _ListingMetric(
        id: lid,
        title: l['title'] as String? ?? '—',
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
    }).toList()
      ..sort((a, b) => b.impressions.compareTo(a.impressions));

    setState(() {
      _loading = false;
      _error = null;
      _listings = merged;
      _videoCtr = (roi?['video']?['ctr'] as num?)?.toDouble() ?? 0;
      _photoCtr = (roi?['photo']?['ctr'] as num?)?.toDouble() ?? 0;
      _videoImp = roi?['video']?['impressions'] as int? ?? 0;
      _photoImp = roi?['photo']?['impressions'] as int? ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('İlan Analizleri'),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null && widget.isPremium)
              ? _buildError()
              : Stack(
                  children: [
                    _buildContent(),
                    if (!widget.isPremium) _buildPaywall(context),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('Tekrar Dene')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final totalImp = _videoImp + _photoImp;
    final totalCtr = totalImp > 0
        ? ((_videoCtr * _videoImp + _photoCtr * _photoImp) / totalImp)
        : 0.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── Gün Filtresi ──────────────────────────────────────────────────
          _DayFilter(days: _days, onChanged: (d) { setState(() => _days = d); _load(); }),
          const SizedBox(height: 16),

          // ── Özet Kartlar ──────────────────────────────────────────────────
          if (_listings.isNotEmpty) ...[
            Row(
              children: [
                _SummaryTile(
                  label: 'Toplam Görüntülenme',
                  value: _fmt(totalImp),
                  icon: Icons.visibility_outlined,
                  color: const Color(0xFF6366F1),
                ),
                const SizedBox(width: 10),
                _SummaryTile(
                  label: 'Ortalama Tıklanma',
                  value: '%${totalCtr.toStringAsFixed(1)}',
                  icon: Icons.ads_click_outlined,
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Video vs Fotoğraf Karşılaştırması ─────────────────────────
            if (_videoImp > 0 && _photoImp > 0)
              _ComparisonCard(videoCtr: _videoCtr, photoCtr: _photoCtr),

            const SizedBox(height: 20),
            Text(
              'İlanlarınızın Performansı',
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── İlan Kartları ─────────────────────────────────────────────────
          if (_listings.isEmpty)
            _EmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'Henüz veri yok',
              subtitle: 'İlanlarınız swipe feed\'de gösterime girince\nburadaki veriler dolmaya başlayacak.',
            )
          else
            ..._listings.map((l) => _ListingCard(metric: l)),
        ],
      ),
    );
  }

  Widget _buildPaywall(BuildContext context) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: AppColors.bg(context).withValues(alpha: 0.6),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.bar_chart_outlined, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 20),
                    Text('Pro Özelliği',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(context))),
                    const SizedBox(height: 10),
                    Text(
                      'Her ilanınızın kaç kişiye ulaştığını,\nkaçının tıkladığını ve ne kadar ilgi\ngördüğünü takip edin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context), height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () => launchUrl(Uri.parse('https://www.teqlif.com/pro-plan.html'),
                              mode: LaunchMode.inAppWebView),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('👑 Pro\'ya Geç',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
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
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}B';
    return '$n';
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _ListingMetric {
  final String id;
  final String title;
  final bool isVideo;
  final int impressions;
  final double ctr;
  final double? completionPct;
  final double? avgPhotoDepth;
  const _ListingMetric({
    required this.id, required this.title, required this.isVideo,
    required this.impressions, required this.ctr,
    this.completionPct, this.avgPhotoDepth,
  });
}

// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _DayFilter extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;
  const _DayFilter({required this.days, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [7, 30].map((d) {
        final active = days == d;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: d == 7 ? 6 : 0, left: d == 30 ? 6 : 0),
            child: GestureDetector(
              onTap: () { if (days != d) onChanged(d); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF6366F1) : AppColors.card(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: active ? const Color(0xFF6366F1) : AppColors.border(context)),
                ),
                child: Text('Son $d Gün',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13,
                      color: active ? Colors.white : AppColors.textPrimary(context),
                    )),
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
  const _SummaryTile({required this.label, required this.value, required this.icon, required this.color});

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
              width: 36, height: 36,
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
                  Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary(context))),
                  Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
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
  const _ComparisonCard({required this.videoCtr, required this.photoCtr});

  @override
  Widget build(BuildContext context) {
    final String message;
    if (videoCtr == 0 && photoCtr == 0) return const SizedBox.shrink();
    if (photoCtr > 0 && videoCtr > photoCtr * 1.1) {
      final x = (videoCtr / photoCtr).toStringAsFixed(1);
      message = '🎬 Videolu ilanlarınız, fotoğraflılara göre $x kat daha fazla tıklanıyor.';
    } else if (videoCtr > 0 && photoCtr > videoCtr * 1.1) {
      final x = (photoCtr / videoCtr).toStringAsFixed(1);
      message = '📸 Fotoğraflı ilanlarınız, videolulara göre $x kat daha fazla tıklanıyor.';
    } else {
      message = 'Video ve fotoğraflı ilanlarınız benzer ilgi görüyor.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1))),
          const SizedBox(height: 10),
          Row(
            children: [
              _SegChip(emoji: '🎬', label: 'Videolu', ctr: videoCtr),
              const SizedBox(width: 8),
              _SegChip(emoji: '📸', label: 'Fotoğraflı', ctr: photoCtr),
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
      child: Text('$emoji $label  %${ctr.toStringAsFixed(1)}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final _ListingMetric metric;
  const _ListingCard({required this.metric});

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
      extraLabel = 'İzleme oranı';
      extraValue = '%${metric.completionPct!.toStringAsFixed(0)} izlendi';
      extraColor = metric.completionPct! >= 60
          ? const Color(0xFF22C55E)
          : metric.completionPct! >= 30
              ? const Color(0xFFF59E0B)
              : const Color(0xFFEF4444);
    } else if (!metric.isVideo && metric.avgPhotoDepth != null) {
      final depth = metric.avgPhotoDepth!;
      extraLabel = 'Galeri ilgisi';
      extraValue = depth >= 2
          ? '${depth.toStringAsFixed(0)}. fotoğrafa kadar baktı'
          : 'Sadece ilk fotoğrafa baktı';
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
          // Başlık + Tür
          Row(
            children: [
              Expanded(
                child: Text(metric.title,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              Text(metric.isVideo ? '🎬' : '📸', style: const TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          // Metrik satırı
          Row(
            children: [
              _MetricPill(
                icon: Icons.visibility_outlined,
                value: _fmtNum(metric.impressions),
                label: 'gördü',
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(width: 8),
              _MetricPill(
                icon: Icons.ads_click_outlined,
                value: '%${metric.ctr.toStringAsFixed(1)}',
                label: 'tıkladı',
                color: ctrColor,
              ),
              if (extraValue != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: extraColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(extraValue!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: extraColor)),
                        Text(extraLabel!, style: TextStyle(fontSize: 9, color: AppColors.textSecondary(context))),
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
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}B';
    return '$n';
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _MetricPill({required this.icon, required this.value, required this.label, required this.color});

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
              Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
              Text(label, style: TextStyle(fontSize: 9, color: AppColors.textSecondary(context))),
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
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(icon, size: 52, color: AppColors.textSecondary(context)),
          const SizedBox(height: 14),
          Text(title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context))),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context), height: 1.5)),
        ],
      ),
    );
  }
}
