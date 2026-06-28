import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';

class AdReportScreen extends StatefulWidget {
  final int campaignId;
  final String listingTitle;

  const AdReportScreen({
    super.key,
    required this.campaignId,
    required this.listingTitle,
  });

  @override
  State<AdReportScreen> createState() => _AdReportScreenState();
}

class _AdReportScreenState extends State<AdReportScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _report;
  bool _loading = true;
  String? _error;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadReport();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    final l = AppLocalizations.of(context)!;
    final report = await AnalyticsService.getCampaignReport(widget.campaignId);
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
      _error = report == null ? l.adReportLoadError : null;
    });
    if (report != null) _fadeCtrl.forward();
  }

  // ── Formatters ──────────────────────────────────────────────────────────────

  String _fmtCtr(dynamic raw) {
    if (raw == null) return '%0,00';
    final v = (raw as num).toDouble();
    return '%${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _statusLabel(String? s, AppLocalizations l) {
    switch (s) {
      case 'active':    return l.adReportStatusActive;
      case 'completed': return l.adReportStatusCompleted;
      case 'paused':    return l.adReportStatusPaused;
      case 'cancelled': return l.adReportStatusCancelled;
      default:          return s ?? '—';
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'active':    return const Color(0xFF10B981);
      case 'completed': return const Color(0xFF6366F1);
      case 'paused':    return const Color(0xFFF59E0B);
      default:          return const Color(0xFF64748B);
    }
  }

  int _activeDays(dynamic createdAt) {
    if (createdAt == null) return 0;
    try {
      final dt = DateTime.parse(createdAt as String);
      return DateTime.now().difference(dt).inDays.clamp(0, 9999);
    } catch (_) {
      return 0;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      body: SafeArea(
        child: _loading
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : _buildReport(),
      ),
    );
  }

  Widget _buildLoading() {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kPrimary),
          const SizedBox(height: 16),
          Text(
            l.adReportLoading,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Color(0xFF475569), size: 52),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
            ),
            const SizedBox(height: 24),
            _AdButton(
              label: l.btnRetry,
              color: kPrimary,
              onTap: () {
                setState(() { _loading = true; _error = null; });
                _loadReport();
              },
            ),
            const SizedBox(height: 12),
            _AdButton(
              label: l.btnGoBack,
              color: const Color(0xFF1E293B),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport() {
    final l = AppLocalizations.of(context)!;
    final r = _report!;
    final status      = r['status'] as String?;
    final impressions = r['impressions'] as int? ?? 0;
    final clicks      = r['clicks'] as int? ?? 0;
    final ctr         = r['ctr'];
    final ctrD        = ctr != null ? (ctr as num).toDouble() : 0.0;
    final activeDays  = _activeDays(r['created_at']);

    return FadeTransition(
      opacity: _fadeAnim,
      child: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _AdHeader(
              title: widget.listingTitle,
              tagLabel: l.adReportTitle,
              subtitle: l.adReportSubtitle,
            ),
          ),

          // ── Durum Chip ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _statusColor(status).withValues(alpha: 0.40)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                            color: _statusColor(status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _statusLabel(status, l),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── Ana metrik kartları (2×2) ────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              delegate: SliverChildListDelegate([
                _MetricCard(
                  icon: Icons.visibility_outlined,
                  label: l.adReportMetricImpressions,
                  value: '$impressions',
                  color: const Color(0xFF6366F1),
                ),
                _MetricCard(
                  icon: Icons.ads_click,
                  label: l.adReportMetricClicks,
                  value: '$clicks',
                  color: const Color(0xFF10B981),
                ),
                _MetricCard(
                  icon: Icons.touch_app_rounded,
                  label: l.adReportMetricClickRate,
                  value: _fmtCtr(ctr),
                  color: const Color(0xFFF59E0B),
                  hint: clicks > 0 && impressions > 0
                      ? l.adReportMetricClickRateHint(clicks, impressions)
                      : null,
                ),
                _MetricCard(
                  icon: Icons.calendar_today_rounded,
                  label: l.adReportMetricActiveDays,
                  value: activeDays == 0
                      ? l.adReportMetricActiveDaysLessThan1
                      : l.adReportMetricActiveDaysValue(activeDays),
                  color: const Color(0xFF06B6D4),
                ),
              ]),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.3,
              ),
            ),
          ),

          // ── Akıllı Analiz kartı ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _CtrInsight(ctr: ctrD, clicks: clicks, impressions: impressions),
            ),
          ),

          // ── Gelişmiş metrikler ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _AdvancedMetrics(report: r, l: l),
            ),
          ),

          // ── Geri Dön butonu ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              child: _AdButton(
                label: l.btnGoBack,
                color: const Color(0xFF1E293B),
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _AdHeader extends StatelessWidget {
  final String title;
  final String tagLabel;
  final String subtitle;

  const _AdHeader({
    required this.title,
    required this.tagLabel,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1040), Color(0xFF0A0F1E)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF64748B), size: 18),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.campaign_rounded, color: kPrimary, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      tagLabel,
                      style: TextStyle(
                        color: kPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Metric Card ──────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? hint;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, height: 1.3),
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(hint!, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

// ── CTR Insight ──────────────────────────────────────────────────────────────

class _CtrInsight extends StatelessWidget {
  final double ctr;
  final int clicks;
  final int impressions;

  const _CtrInsight({required this.ctr, required this.clicks, required this.impressions});

  String _insight(AppLocalizations l) {
    if (impressions == 0) return l.adReportInsightNoImpressions;
    if (ctr >= 5)   return l.adReportInsightGreat(clicks);
    if (ctr >= 2)   return l.adReportInsightGood(clicks, impressions);
    if (ctr >= 0.5) return l.adReportInsightLow(clicks, impressions);
    return l.adReportInsightVeryLow(clicks, impressions);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimary.withValues(alpha: 0.16), const Color(0xFF1E1B4B).withValues(alpha: 0.75)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.25), shape: BoxShape.circle),
                child: Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 14),
              ),
              const SizedBox(width: 8),
              Text(l.adReportSmartAnalysis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Text(_insight(l), style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.55)),
        ],
      ),
    );
  }
}

// ── Button ────────────────────────────────────────────────────────────────────

class _AdButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AdButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Gelişmiş Reklam Metrikleri ────────────────────────────────────────────────

class _AdvancedMetrics extends StatelessWidget {
  final Map<String, dynamic> report;
  final AppLocalizations l;
  const _AdvancedMetrics({required this.report, required this.l});

  @override
  Widget build(BuildContext context) {
    final bestHour = report['best_hour'] as int?;
    final catAvgCtr = report['category_avg_ctr'];
    final dailySpend = report['daily_spend'];
    final daysLeft = report['estimated_days_left'];

    if (bestHour == null && catAvgCtr == null && daysLeft == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.adReportSmartAnalysis, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(children: [
            if (bestHour != null) Expanded(
              child: _MiniStat(
                icon: Icons.schedule,
                label: l.adMetricBestHour,
                value: '${bestHour}:00',
              ),
            ),
            if (catAvgCtr != null) Expanded(
              child: _MiniStat(
                icon: Icons.bar_chart,
                label: l.adMetricCategoryAvgCtr,
                value: '%${(catAvgCtr as num).toStringAsFixed(1)}',
              ),
            ),
            if (daysLeft != null) Expanded(
              child: _MiniStat(
                icon: Icons.local_fire_department,
                label: l.adMetricBurnRate,
                value: '~${(daysLeft as num).toStringAsFixed(0)} gün',
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MiniStat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF818CF8)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9), textAlign: TextAlign.center),
      ],
    );
  }
}
