import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../services/analytics_service.dart';

class MarketTrendsScreen extends StatefulWidget {
  final bool isPremium;

  const MarketTrendsScreen({super.key, required this.isPremium});

  @override
  State<MarketTrendsScreen> createState() => _MarketTrendsScreenState();
}

class _MarketTrendsScreenState extends State<MarketTrendsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await AnalyticsService.getMarketTrends();
    if (mounted) {
      setState(() {
        _data = result;
        _loading = false;
        _error = result == null ? 'Veriler yüklenemedi.' : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('Pazar Trendleri'),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
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
          TextButton(onPressed: () { setState(() { _loading = true; }); _load(); }, child: const Text('Tekrar Dene')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final peakHours = (_data?['peak_hours'] as List? ?? []).cast<Map<String, dynamic>>();
    final categories = (_data?['trending_categories'] as List? ?? []).cast<Map<String, dynamic>>();
    final growth = _data?['average_spend_growth'] as double?;
    final maxCount = peakHours.isEmpty ? 1 : (peakHours.map((h) => (h['count'] as int? ?? 0)).reduce((a, b) => a > b ? a : b));
    final maxCatCount = categories.isEmpty ? 1 : (categories.map((c) => (c['recent_count'] as int? ?? 0)).reduce((a, b) => a > b ? a : b));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Harcama Büyüme Özeti ──────────────────────────────────────────
          _SummaryCard(growth: growth),
          const SizedBox(height: 16),

          // ── Zirve Saatler ────────────────────────────────────────────────
          _SectionHeader(title: '⏰ Zirve Saatler', subtitle: 'Son 30 gün en yoğun 3 saat'),
          const SizedBox(height: 10),
          if (peakHours.isEmpty)
            _EmptyHint(text: 'Henüz yeterli veri yok.')
          else
            ...peakHours.asMap().entries.map((e) {
              final i = e.key;
              final h = e.value;
              final count = h['count'] as int? ?? 0;
              final ratio = maxCount > 0 ? count / maxCount : 0.0;
              return _HourBar(
                label: h['label'] as String? ?? '',
                count: count,
                ratio: ratio,
                rank: i + 1,
              );
            }),
          const SizedBox(height: 20),

          // ── Yükselen Kategoriler ─────────────────────────────────────────
          _SectionHeader(title: '🚀 Yükselen Kategoriler', subtitle: 'Son 15 güne göre büyüme'),
          const SizedBox(height: 10),
          if (categories.isEmpty)
            _EmptyHint(text: 'Henüz yeterli satış verisi yok.')
          else
            ...categories.map((cat) {
              final recentCount = cat['recent_count'] as int? ?? 0;
              final ratio = maxCatCount > 0 ? recentCount / maxCatCount : 0.0;
              final growthPct = (cat['growth_pct'] as num?)?.toDouble() ?? 0.0;
              return _CategoryBar(
                label: cat['label'] as String? ?? '',
                recentCount: recentCount,
                growthPct: growthPct,
                ratio: ratio,
              );
            }),
          const SizedBox(height: 8),
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      spreadRadius: 4,
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
                          colors: [Color(0xFFFFB800), Color(0xFFFF6B00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.lock_outline, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Pro Özelliği',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sektörel pazar analizi verileri yalnızca\nPro kullanıcılar için erişilebilirdir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary(context),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Zirve saatleri, yükselen kategoriler ve\npazar büyüme verilerine ulaşın.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFB800), Color(0xFFFF6B00)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () => _showUpgradeInfo(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Aboneliği Yükselt',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Geri Dön',
                        style: TextStyle(color: AppColors.textSecondary(context)),
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

  void _showUpgradeInfo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pro abonelik yakında! Bildirim almak için hesabınızı takipte tutun.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

// ── Alt Bileşenler ────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double? growth;

  const _SummaryCard({required this.growth});

  @override
  Widget build(BuildContext context) {
    final isPositive = (growth ?? 0) >= 0;
    final growthStr = growth == null
        ? '—'
        : '${isPositive ? '+' : ''}${growth!.toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF1A6B3C), const Color(0xFF27AE60)]
              : [const Color(0xFF8B1A1A), const Color(0xFFE74C3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isPositive ? const Color(0xFF27AE60) : const Color(0xFFE74C3C))
                .withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ortalama Harcama Trendi',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  growthStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Geçen aya göre',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            color: Colors.white,
            size: 48,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
        ),
      ],
    );
  }
}

class _HourBar extends StatelessWidget {
  final String label;
  final int count;
  final double ratio;
  final int rank;

  const _HourBar({
    required this.label,
    required this.count,
    required this.ratio,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [kPrimary, const Color(0xFF3498DB), const Color(0xFF9B59B6)];
    final color = colors[(rank - 1).clamp(0, 2)];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '#$rank',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              Text(
                '$count etkileşim',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String label;
  final int recentCount;
  final double growthPct;
  final double ratio;

  const _CategoryBar({
    required this.label,
    required this.recentCount,
    required this.growthPct,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = growthPct >= 0;
    final growthColor = isPositive ? const Color(0xFF27AE60) : const Color(0xFFE74C3C);
    final growthStr = '${isPositive ? '+' : ''}${growthPct.toStringAsFixed(1)}%';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: growthColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  growthStr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: growthColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$recentCount satış (son 15 gün)',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(kPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;

  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
      ),
    );
  }
}
