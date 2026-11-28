import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_colors.dart';
import '../../services/localization_service.dart';
import '../../services/wallet_service.dart';
import 'convert_minutes_sheet.dart';

class TeqlikConversionTab extends ConsumerStatefulWidget {
  final int currentBalance;

  const TeqlikConversionTab({super.key, required this.currentBalance});

  @override
  ConsumerState<TeqlikConversionTab> createState() => _TeqlikConversionTabState();
}

class _TeqlikConversionTabState extends ConsumerState<TeqlikConversionTab>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _rates = [];
  int _teqlikPerMinute = 1;
  bool _loadingRates = true;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _loadRates();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRates() async {
    final data = await WalletService.getConversionRates();
    if (!mounted) return;
    setState(() {
      _loadingRates = false;
      if (data != null) {
        _teqlikPerMinute = data['teqlik_per_stream_minute'] as int? ?? 1;
        _rates = (data['rates'] as List?)
                ?.map((r) => r as Map<String, dynamic>)
                .toList() ??
            [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pulsing dönüşüm ikonu — sadece Canlı Yayın Dakikası kartına geçirilir
    final convertButton = ScaleTransition(
      scale: _pulse,
      child: GestureDetector(
        onTap: () => ConvertMinutesSheet.show(
          context,
          currentBalance: widget.currentBalance,
          teqlikPerMinute: _teqlikPerMinute,
        ),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06B6D4).withOpacity(0.45),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.swap_horiz_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: _loadRates,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // ── Referans Kartlar Başlığı ─────────────────────────────────────
          Text(
            loc.t('walletConversionRates'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),

          // ── Referans Kartlar ─────────────────────────────────────────────
          if (_loadingRates)
            const Center(child: CircularProgressIndicator())
          else
            ..._rates.map((rate) {
              final isStream = rate['key'] == 'stream_minute';
              return _RateCard(
                arbKey: rate['arb_key'] as String? ?? '',
                cost: rate['cost'] as int? ?? 0,
                isStreamMinute: isStream,
                loc: loc,
                isDark: isDark,
                convertButton: isStream ? convertButton : null,
              );
            }),
        ],
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  final String arbKey;
  final int cost;
  final bool isStreamMinute;
  final TranslationPack loc;
  final bool isDark;
  final Widget? convertButton;

  const _RateCard({
    required this.arbKey,
    required this.cost,
    required this.isStreamMinute,
    required this.loc,
    required this.isDark,
    this.convertButton,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isStreamMinute
            ? (isDark ? const Color(0xFF0C2231) : const Color(0xFFE0F7FA))
            : AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isStreamMinute
              ? const Color(0xFF06B6D4).withOpacity(0.5)
              : AppColors.border(context),
        ),
      ),
      child: Row(
        children: [
          // İkon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isStreamMinute
                  ? const Color(0xFF06B6D4).withOpacity(0.15)
                  : AppColors.surfaceVariant(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isStreamMinute ? Icons.videocam_rounded : Icons.diamond_rounded,
              size: 18,
              color: isStreamMinute
                  ? const Color(0xFF06B6D4)
                  : AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(width: 12),

          // Etiket
          Expanded(
            child: Text(
              loc.t(arbKey),
              style: TextStyle(
                fontSize: 14,
                fontWeight: isStreamMinute ? FontWeight.w600 : FontWeight.w500,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),

          // Dönüşüm ikonu (sadece Canlı Yayın Dakikası kartında)
          if (convertButton != null) ...[
            const SizedBox(width: 8),
            Text(
              '1 ${loc.t('walletConvertMinuteUnitShort')}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF06B6D4),
              ),
            ),
            const SizedBox(width: 6),
            convertButton!,
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 8),

          // Maliyet
          Text(
            '$cost teqlik',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isStreamMinute
                  ? const Color(0xFF06B6D4)
                  : AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
