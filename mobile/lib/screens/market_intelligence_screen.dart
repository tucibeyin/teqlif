import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';

class MarketIntelligenceScreen extends StatefulWidget {
  final bool isPremium;
  const MarketIntelligenceScreen({super.key, required this.isPremium});

  @override
  State<MarketIntelligenceScreen> createState() => _MarketIntelligenceScreenState();
}

class _MarketIntelligenceScreenState extends State<MarketIntelligenceScreen> {
  int _searchDays = 7;
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _trends;    // peak_hours, trending_categories, average_spend_growth
  Map<String, dynamic>? _demand;    // top_queries, by_category

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    final results = await Future.wait([
      AnalyticsService.getMarketTrends(),
      AnalyticsService.getDemandRadar(days: _searchDays),
    ]);

    if (!mounted) return;
    final trends = results[0];
    final demand = results[1];

    if (trends == null && demand == null) {
      setState(() { _loading = false; _error = 'Veriler yüklenemedi.'; });
      return;
    }

    setState(() {
      _loading = false;
      _error = null;
      _trends = trends;
      _demand = demand;
    });
  }

  Future<void> _reloadDemand() async {
    final data = await AnalyticsService.getDemandRadar(days: _searchDays);
    if (mounted) setState(() => _demand = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('Pazar Bilgisi'),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
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
    final queries     = (_demand?['top_queries']          as List? ?? []).cast<Map<String, dynamic>>();
    final catSearch   = (_demand?['by_category']          as List? ?? []).cast<Map<String, dynamic>>();
    final peakHours   = (_trends?['peak_hours']           as List? ?? []).cast<Map<String, dynamic>>();
    final trendCats   = (_trends?['trending_categories']  as List? ?? []).cast<Map<String, dynamic>>();
    final growth      = _trends?['average_spend_growth']  as double?;

    final maxQCount  = queries.isEmpty  ? 1 : (queries.map((q) => (q['count'] as int? ?? 0)).reduce((a, b) => a > b ? a : b));
    final maxHrCount = peakHours.isEmpty ? 1 : (peakHours.map((h) => (h['count'] as int? ?? 0)).reduce((a, b) => a > b ? a : b));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [

          // ── Platform harcama büyümesi ──────────────────────────────────────
          if (growth != null)
            _GrowthBanner(growth: growth),
          if (growth != null) const SizedBox(height: 16),

          // ── Arama trendleri ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'İnsanlar şunları arıyor',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
                ),
              ),
              // Gün filtresi (sadece aramalar için)
              _SmallDayFilter(days: _searchDays, onChanged: (d) {
                setState(() => _searchDays = d);
                _reloadDemand();
              }),
            ],
          ),
          const SizedBox(height: 10),

          if (queries.isEmpty)
            _EmptyHint(text: 'Henüz arama verisi yok. Kullanıcılar arama yaptıkça burada görünecek.')
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: queries.take(10).toList().asMap().entries.map((e) {
                  final i = e.key;
                  final q = e.value;
                  final count = q['count'] as int? ?? 0;
                  final isLast = i == queries.take(10).length - 1;
                  final fill = maxQCount > 0 ? count / maxQCount : 0.0;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}.',
                                style: TextStyle(fontSize: i < 3 ? 15 : 11,
                                    color: AppColors.textSecondary(context)),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    q['query'] as String? ?? '—',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary(context)),
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: fill,
                                      backgroundColor: AppColors.border(context),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                      minHeight: 3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('$count',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary(context))),
                          ],
                        ),
                      ),
                      if (!isLast) const Divider(height: 1),
                    ],
                  );
                }).toList(),
              ),
            ),

          // ── Kategori bazlı aramalar ────────────────────────────────────────
          if (catSearch.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Hangi kategoride arıyorlar',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: catSearch.map((c) {
                final cat = c['category'] as String? ?? 'diğer';
                final cnt = c['count'] as int? ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context))),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$cnt',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // ── Alışveriş Saatleri ────────────────────────────────────────────
          const SizedBox(height: 24),
          Text(
            'Alışveriş en çok bu saatlerde',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'İlanlarınızı bu saatlerde yayınlarsanız daha fazla kişiye ulaşırsınız.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 12),

          if (peakHours.isEmpty)
            _EmptyHint(text: 'Henüz yeterli aktivite verisi yok.')
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: peakHours.asMap().entries.map((e) {
                  final i = e.key;
                  final h = e.value;
                  final count = h['count'] as int? ?? 0;
                  final isLast = i == peakHours.length - 1;
                  final fill = maxHrCount > 0 ? count / maxHrCount : 0.0;
                  final rankEmoji = i == 0 ? '🔥' : (i == 1 ? '⚡' : '⏰');
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Text(rankEmoji, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(h['label'] as String? ?? '',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary(context))),
                                  const SizedBox(height: 5),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: fill,
                                      backgroundColor: AppColors.border(context),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
                                      minHeight: 5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast) const Divider(height: 1),
                    ],
                  );
                }).toList(),
              ),
            ),

          // ── Yükselen Kategoriler ──────────────────────────────────────────
          if (trendCats.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Bu kategoriler ilgi görüyor',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 4),
            Text(
              'Bu kategorilerde ilan açmak satış şansınızı artırabilir.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 12),
            ...trendCats.asMap().entries.map((e) {
              final cat   = e.value;
              final label = cat['label'] as String? ?? '';
              final grow  = (cat['growth_pct'] as num?)?.toDouble() ?? 0.0;
              final isPos = grow >= 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary(context))),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPos
                            ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                            : const Color(0xFFEF4444).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${isPos ? '+' : ''}${grow.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: isPos ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
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
                        gradient: const LinearGradient(colors: [Color(0xFFFFB800), Color(0xFFFF6B00)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.insights_outlined, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 20),
                    Text('Pro Özelliği',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(context))),
                    const SizedBox(height: 10),
                    Text(
                      'Alıcılar ne arıyor, hangi saatlerde\nalışveriş yapıyor, hangi kategoriler\nyükseliyor — hepsini görün.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context), height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFFB800), Color(0xFFFF6B00)]),
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
}

// ── Alt Widgetlar ─────────────────────────────────────────────────────────────

class _GrowthBanner extends StatelessWidget {
  final double growth;
  const _GrowthBanner({required this.growth});

  @override
  Widget build(BuildContext context) {
    final isPos = growth >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isPos
            ? const Color(0xFF22C55E).withValues(alpha: 0.08)
            : const Color(0xFFEF4444).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPos
              ? const Color(0xFF22C55E).withValues(alpha: 0.25)
              : const Color(0xFFEF4444).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Text(isPos ? '📈' : '📉', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPos
                      ? 'Platform genel büyüme: +${growth.toStringAsFixed(1)}%'
                      : 'Platform genel düşüş: ${growth.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: isPos ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ortalama alışveriş tutarı — önceki 30 güne kıyasla',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallDayFilter extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;
  const _SmallDayFilter({required this.days, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [7, 30].map((d) {
        final active = days == d;
        return GestureDetector(
          onTap: () { if (days != d) onChanged(d); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFF59E0B) : AppColors.card(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: active ? const Color(0xFFF59E0B) : AppColors.border(context)),
            ),
            child: Text('$d gün',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.textSecondary(context))),
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
          textAlign: TextAlign.center),
    );
  }
}
