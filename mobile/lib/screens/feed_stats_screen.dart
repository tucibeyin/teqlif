import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';

class FeedStatsScreen extends StatefulWidget {
  final bool isPremium;

  const FeedStatsScreen({super.key, required this.isPremium});

  @override
  State<FeedStatsScreen> createState() => _FeedStatsScreenState();
}

class _FeedStatsScreenState extends State<FeedStatsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    if (widget.isPremium) _load();
    else setState(() => _loading = false);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final result = await AnalyticsService.getFeedStats(days: _days);
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
        title: const Text('Feed Performansı'),
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
          TextButton(onPressed: _load, child: const Text('Tekrar Dene')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final totals = (_data?['totals'] as Map<String, dynamic>?) ?? {};
    final stats  = (_data?['stats']  as List? ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Filtre ─────────────────────────────────────────────────────────
          Row(
            children: [7, 30].map((d) {
              final active = _days == d;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d == 7 ? 6 : 0, left: d == 30 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () {
                      if (_days == d) return;
                      setState(() => _days = d);
                      _load();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF6366F1) : AppColors.card(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? const Color(0xFF6366F1) : AppColors.border(context),
                        ),
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

          // ── Özet Kartlar ───────────────────────────────────────────────────
          Row(
            children: [
              _SummaryCard(
                label: '👁 İzlenme',
                value: (totals['impressions'] as int? ?? 0).toLocaleString(),
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: '🖱 CTR',
                value: '%${((totals['ctr'] as num?) ?? 0).toStringAsFixed(1)}',
              ),
              const SizedBox(width: 10),
              _SummaryCard(
                label: '⏱ Ort. Süre',
                value: _formatMs(totals['avg_dwell_ms'] as int? ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── İlan Tablosu ───────────────────────────────────────────────────
          if (stats.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Bu dönemde henüz veri yok.',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ),
            )
          else ...[
            Text(
              'İlan Bazlı Performans',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  // Başlık satırı
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text('İlan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)))),
                        SizedBox(width: 52, child: Text('👁', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)))),
                        SizedBox(width: 52, child: Text('CTR', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context)))),
                        SizedBox(width: 52, child: Text('⏱', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...stats.asMap().entries.map((e) {
                    final s   = e.value;
                    final last = e.key == stats.length - 1;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s['title'] as String? ?? s['listing_id'].toString(),
                                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  (s['impressions'] as int? ?? 0).toLocaleString(),
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
                                    color: _ctrColor(s['ctr'] as num? ?? 0),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  _formatMs(s['avg_dwell_ms'] as int? ?? 0),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!last) const Divider(height: 1),
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
                          colors: [Color(0xFFB8860B), Color(0xFFFFD700)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.bar_chart_outlined, color: Colors.white, size: 32),
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
                      'Video ilanlarınızın feed performansı\nyalnızca Pro kullanıcılar için görünür.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary(context),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'İzlenme, tıklanma oranı (CTR) ve\nortalama izlenme süresini takip edin.',
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
                            colors: [Color(0xFFB8860B), Color(0xFFFFD700)],
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
                          child: const Text(
                            '👑 Pro\'ya Geç',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Colors.black,
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

  String _formatMs(int ms) {
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms}ms';
  }

  Color _ctrColor(num ctr) {
    if (ctr >= 10) return const Color(0xFF22C55E);
    if (ctr >= 5)  return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}

// ── Alt Widgetlar ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary(context)), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

extension _IntFormat on int {
  String toLocaleString() {
    final s = toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
