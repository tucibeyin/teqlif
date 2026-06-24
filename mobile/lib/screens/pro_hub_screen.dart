import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';
import 'listing_analytics_screen.dart';
import 'market_intelligence_screen.dart';
import 'pro_insights_screen.dart';

class ProHubScreen extends StatefulWidget {
  final bool isPremium;

  const ProHubScreen({super.key, required this.isPremium});

  @override
  State<ProHubScreen> createState() => _ProHubScreenState();
}

class _ProHubScreenState extends State<ProHubScreen> {
  Map<String, dynamic>? _credits;

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    final data = await AnalyticsService.getBlastCredits();
    if (mounted) setState(() => _credits = data);
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = widget.isPremium;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('Pro Araçları'),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Durum Kartı ────────────────────────────────────────────────────
          if (isPremium) _ProStatusCard() else _UpgradeBanner(),
          const SizedBox(height: 24),

          // ── Araçlar Başlığı ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              'Pro Araçları',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary(context),
                letterSpacing: 0.6,
              ),
            ),
          ),

          // ── 3 Araç Kartı ──────────────────────────────────────────────────
          _ToolCard(
            icon: Icons.auto_graph_outlined,
            iconColor: const Color(0xFF6366F1),
            title: 'Satış ve Kitle Raporu',
            description: 'Gelirler, dönüşüm oranları ve sıcak ilanlarınız',
            isPremium: isPremium,
            onTap: isPremium
                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProInsightsScreen()))
                : () => _showUpgrade(context),
          ),
          const SizedBox(height: 10),
          _ToolCard(
            icon: Icons.bar_chart_outlined,
            iconColor: const Color(0xFF10B981),
            title: 'İlan Analizleri',
            description: 'Hangi ilanınız kaç kişiye ulaştı, kaçı tıkladı',
            isPremium: isPremium,
            onTap: isPremium
                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ListingAnalyticsScreen(isPremium: isPremium)))
                : () => _showUpgrade(context),
          ),
          const SizedBox(height: 10),
          _ToolCard(
            icon: Icons.insights_outlined,
            iconColor: const Color(0xFFF59E0B),
            title: 'Pazar Bilgisi',
            description: 'Alıcılar ne arıyor, hangi saatlerde alışveriş yapıyor',
            isPremium: isPremium,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MarketIntelligenceScreen(isPremium: isPremium)),
            ),
          ),

          // ── Blast Kredi Kartı ──────────────────────────────────────────────
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              'Kitle Davet Kredisi',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary(context),
                letterSpacing: 0.6,
              ),
            ),
          ),
          _BlastCreditCard(credits: _credits, isPremium: isPremium),

          if (!isPremium) ...[
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Text(
                'Pro\'ya Geçince Ne Kazanırsın?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary(context),
                  letterSpacing: 0.6,
                ),
              ),
            ),
            _BenefitRow(icon: Icons.insights_outlined,      text: 'Satışlarını ve gelirlerin nereye gittiğini gör'),
            _BenefitRow(icon: Icons.bar_chart_outlined,     text: 'Her ilanına kaç kişi baktı, kaçı tıkladı'),
            _BenefitRow(icon: Icons.schedule_outlined,      text: 'Alıcıların en aktif olduğu saatleri öğren'),
            _BenefitRow(icon: Icons.search_outlined,        text: 'İnsanlar ne arıyor — boşluğu doldur, sat'),
          ],
        ],
      ),
    );
  }

  void _showUpgrade(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UpgradeSheet(),
    );
  }
}

// ── Durum Kartları ─────────────────────────────────────────────────────────────

class _ProStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.workspace_premium, color: Color(0xFF06B6D4), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '👑 Pro Kullanıcı',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Tüm analitik araçlara erişiminiz aktif',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF92400E), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_outline, color: Color(0xFF06B6D4), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pro araçları kilidi aç',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  'Verilerle sat, değil tahminle',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://www.teqlif.com/pro-plan.html'),
              mode: LaunchMode.inAppWebView,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Pro\'ya Geç',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Araç Kartı ─────────────────────────────────────────────────────────────────

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool isPremium;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.isPremium,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isPremium)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
              )
            else
              Icon(Icons.chevron_right, color: AppColors.textSecondary(context), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Benefit Row ────────────────────────────────────────────────────────────────

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6366F1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Yükseltme Bottom Sheet ─────────────────────────────────────────────────────

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.workspace_premium, size: 48, color: Color(0xFFFFB800)),
          const SizedBox(height: 12),
          Text(
            'Pro Özelliği',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bu aracı kullanmak için Pro\'ya geçmeniz gerekiyor.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context), height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0891B2), Color(0xFF06B6D4)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse('https://www.teqlif.com/pro-plan.html'),
                    mode: LaunchMode.inAppWebView,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  '👑 Pro\'ya Geç',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Vazgeç', style: TextStyle(color: AppColors.textSecondary(context))),
          ),
        ],
      ),
    );
  }
}

// ── Blast Kredi Kartı ──────────────────────────────────────────────────────────

class _BlastCreditCard extends StatelessWidget {
  final Map<String, dynamic>? credits;
  final bool isPremium;

  const _BlastCreditCard({required this.credits, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    final used      = credits?['used']      as int? ?? 0;
    final limit     = credits?['limit']     as int? ?? (isPremium ? 20 : 3);
    final remaining = credits?['remaining'] as int? ?? (isPremium ? 20 : 3);
    final progress  = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;

    final Color barColor = remaining == 0
        ? const Color(0xFFEF4444)
        : remaining <= limit ~/ 4
            ? const Color(0xFFF59E0B)
            : const Color(0xFF22C55E);

    return Container(
      padding: const EdgeInsets.all(16),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.campaign_outlined, color: Color(0xFF8B5CF6), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bu Ay Kalan Hak',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(color: AppColors.textPrimary(context)),
                        children: [
                          TextSpan(
                            text: '$remaining',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: barColor,
                            ),
                          ),
                          TextSpan(
                            text: ' / $limit',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isPremium)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('PRO: 20/ay', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            remaining == 0
                ? 'Bu ay blast krediniz doldu. Yeni ayda yenilenir.'
                : '$used blast kullandınız, $remaining hakkınız kaldı.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
          ),
        ],
      ),
    );
  }
}
