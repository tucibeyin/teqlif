import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';

class VideoRoiScreen extends StatefulWidget {
  final bool isPremium;
  const VideoRoiScreen({super.key, required this.isPremium});

  @override
  State<VideoRoiScreen> createState() => _VideoRoiScreenState();
}

class _VideoRoiScreenState extends State<VideoRoiScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final data = await AnalyticsService.getVideoRoi(days: _days);
    if (!mounted) return;
    if (data == null) {
      setState(() { _loading = false; _error = 'Veri yüklenemedi.'; });
    } else {
      setState(() { _loading = false; _data = data; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('Video ROI'),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
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
    final video = (_data?['video'] as Map<String, dynamic>?) ?? {};
    final photo = (_data?['photo'] as Map<String, dynamic>?) ?? {};
    final byListing = (_data?['by_listing'] as List? ?? []).cast<Map<String, dynamic>>();

    final videoCtr = (video['ctr'] as num?)?.toDouble() ?? 0;
    final photoCtr = (photo['ctr'] as num?)?.toDouble() ?? 0;
    final videoImp = video['impressions'] as int? ?? 0;
    final photoImp = photo['impressions'] as int? ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Filtre
          Row(
            children: [30, 7].map((d) {
              final active = _days == d;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d == 30 ? 6 : 0, left: d == 7 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () { if (_days != d) { setState(() => _days = d); _load(); } },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF6366F1) : AppColors.card(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? const Color(0xFF6366F1) : AppColors.border(context)),
                      ),
                      child: Text(
                        'Son $d Gün',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: active ? Colors.white : AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Karşılaştırma kartları
          Text(
            'Video vs Fotoğraf CTR',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SegmentCard(
                label: '🎬 Video İlanlar',
                ctr: videoCtr,
                impressions: videoImp,
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(width: 10),
              _SegmentCard(
                label: '📸 Fotoğraf İlanlar',
                ctr: photoCtr,
                impressions: photoImp,
                color: const Color(0xFF10B981),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InsightBanner(videoCtr: videoCtr, photoCtr: photoCtr),
          const SizedBox(height: 20),

          if (byListing.isNotEmpty) ...[
            Text(
              'İlan Bazlı CTR',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text('İlan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)))),
                        SizedBox(width: 48, child: Text('Tür', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)))),
                        SizedBox(width: 52, child: Text('👁', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)))),
                        SizedBox(width: 52, child: Text('CTR', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...byListing.asMap().entries.map((e) {
                    final s = e.value;
                    final isLast = e.key == byListing.length - 1;
                    final ct = s['content_type'] as String? ?? '';
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s['title'] as String? ?? '—',
                                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                child: Text(
                                  ct == 'video' ? '🎬' : '📸',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '${s['impressions'] ?? 0}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '%${((s['ctr'] as num?) ?? 0).toStringAsFixed(1)}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _ctrColor((s['ctr'] as num?) ?? 0),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast) const Divider(height: 1),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _ctrColor(num ctr) {
    if (ctr >= 10) return const Color(0xFF22C55E);
    if (ctr >= 5) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

class _SegmentCard extends StatelessWidget {
  final String label;
  final double ctr;
  final int impressions;
  final Color color;
  const _SegmentCard({required this.label, required this.ctr, required this.impressions, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context))),
            const SizedBox(height: 8),
            Text('%${ctr.toStringAsFixed(1)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text('$impressions gösterim', style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context))),
          ],
        ),
      ),
    );
  }
}

class _InsightBanner extends StatelessWidget {
  final double videoCtr;
  final double photoCtr;
  const _InsightBanner({required this.videoCtr, required this.photoCtr});

  @override
  Widget build(BuildContext context) {
    if (videoCtr == 0 && photoCtr == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Henüz yeterli feed verisi yok. İlanlarınız swipe feed\'de gösterime girince bu kısım dolacak.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
        ),
      );
    }
    final diff = videoCtr - photoCtr;
    final icon = diff >= 0 ? '🎬' : '📸';
    final winner = diff >= 0 ? 'Video' : 'Fotoğraf';
    final pct = diff.abs().toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
      ),
      child: Text(
        '$icon $winner ilanlar CTR\'de %$pct daha ${diff >= 0 ? "yüksek" : "düşük"} performans gösteriyor.',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)),
      ),
    );
  }
}
