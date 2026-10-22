import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';
import '../buttons/teq_button.dart';
import '../inputs/teq_text_field.dart';
import '../../../models/credit_gate_data.dart';
import '../../../screens/viewmodels/credit_gate_view_model.dart';
import '../../../services/credit_gate_service.dart';
import '../../../services/localization_service.dart' show localizationProvider, TranslationPack;

/// Tüm kredili/ücretli feature'lar için tek merkezi onay bottom sheet'i.
///
/// Her türlü iş mantığı (veri çekme, execution, blast sayım hesabı) burada
/// veya [CreditGateService]'te yönetilir. Ekranlar yalnızca şunu çağırır:
///
/// ```dart
/// final result = await CreditGateSheet.show(
///   context: context,
///   ref: ref,
///   feature: CreditFeature.boost,
///   listingId: listingId,
/// );
/// if (result.success) { /* UI güncelle */ }
/// ```
///
/// [onExecute] — yalnızca aiDesc için: gate onaylandıktan sonra
/// server-side deduction'ın tetikleneceği çağrı (generate endpoint).
/// Diğer tüm feature'lar [CreditGateService] tarafından execute edilir.
class CreditGateSheet extends ConsumerStatefulWidget {
  final CreditFeature feature;
  final int? listingId;

  /// Yalnızca aiDesc: execution caller'da yapılır; gate sadece onay toplar.
  final Future<CreditGateResult> Function()? onExecute;

  const CreditGateSheet._({
    required this.feature,
    this.listingId,
    this.onExecute,
  });

  /// Ana giriş noktası. [result.success] ile işlemin başarılı olup olmadığı
  /// kontrol edilir; [result.payload] feature'a özgü veriyi taşır.
  static Future<CreditGateResult> show({
    required BuildContext context,
    required WidgetRef ref,
    required CreditFeature feature,
    int? listingId,
    Future<CreditGateResult> Function()? onExecute,
    /// Yetersiz bakiye durumunda kullanıcı "Cüzdana Git" tıklarsa çağrılır.
    VoidCallback? onGoToWallet,
  }) async {
    final result = await showModalBottomSheet<CreditGateResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreditGateSheet._(
        feature: feature,
        listingId: listingId,
        onExecute: onExecute,
      ),
    );
    // Cüzdan yönlendirme talebini merkezi olarak burada yakala.
    if (result != null && result.isWalletRedirect) {
      onGoToWallet?.call();
      return CreditGateResult.cancelled();
    }
    return result ?? CreditGateResult.cancelled();
  }

  @override
  ConsumerState<CreditGateSheet> createState() => _CreditGateSheetState();
}

class _CreditGateSheetState extends ConsumerState<CreditGateSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(creditGateProvider.notifier).loadData(
          widget.feature,
          widget.listingId,
          ref.read(creditGateServiceProvider),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(creditGateProvider);
    final TranslationPack loc = ref.watch(localizationProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? TeqColors.surfaceDark : TeqColors.surfaceLight;
    final textColor =
        isDark ? TeqColors.textPrimaryDark : TeqColors.textPrimaryLight;
    final subColor =
        isDark ? TeqColors.textSecondaryDark : TeqColors.textSecondaryLight;
    final borderColor = isDark ? TeqColors.borderDark : TeqColors.borderLight;

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(TeqSpacing.radiusXl),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: TeqSpacing.s),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius:
                      BorderRadius.circular(TeqSpacing.radiusMax),
                ),
              ),
              const SizedBox(height: TeqSpacing.s),

              // Başlık
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: TeqSpacing.m),
                child: Row(
                  children: [
                    _FeatureIcon(feature: widget.feature),
                    const SizedBox(width: TeqSpacing.xs),
                    Expanded(
                      child: Text(
                        loc.t(
                          'creditGate${widget.feature.l10nPrefix}Title',
                        ),
                        style:
                            TeqTypography.h3.copyWith(color: textColor),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: subColor),
                      onPressed: vm.isConfirming
                          ? null
                          : () => Navigator.of(context)
                              .pop(CreditGateResult.cancelled()),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

              Divider(color: borderColor, height: 1),

              // Gövde
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(TeqSpacing.m),
                  child: vm.isLoadingData
                      ? _LoadingBody(subColor: subColor)
                      : vm.loadError != null
                          ? _ErrorBody(
                              message: loc.t(vm.loadError!),
                              textColor: subColor,
                              showRetry: vm.loadError != 'blastNoAudience',
                              onRetry: () =>
                                  ref
                                      .read(creditGateProvider.notifier)
                                      .loadData(
                                        widget.feature,
                                        widget.listingId,
                                        ref.read(creditGateServiceProvider),
                                      ),
                            )
                          : _LoadedBody(
                              vm: vm,
                              feature: widget.feature,
                              loc: loc,
                              isDark: isDark,
                              textColor: textColor,
                              subColor: subColor,
                              onConfirm: _handleConfirm,
                              onCancel: () => Navigator.of(context)
                                  .pop(CreditGateResult.cancelled()),
                              onGoToWallet: () => Navigator.of(context)
                                  .pop(CreditGateResult.walletRedirect()),
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleConfirm() async {
    final result =
        await ref.read(creditGateProvider.notifier).confirm((state) async {
      if (widget.onExecute != null) {
        return await widget.onExecute!();
      }
      return ref.read(creditGateServiceProvider).execute(
            widget.feature,
            listingId: widget.listingId,
            count: state.selectedCount,
          );
    });
    if (mounted) Navigator.of(context).pop(result);
  }
}

// ── Alt widget'lar ─────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  final Color subColor;
  const _LoadingBody({required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TeqSpacing.xl),
      child: Center(
        child: CircularProgressIndicator(
          color: TeqColors.primary,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final Color textColor;
  final bool showRetry;
  final VoidCallback onRetry;
  const _ErrorBody({
    required this.message,
    required this.textColor,
    required this.onRetry,
    this.showRetry = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TeqSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: TeqColors.error, size: 36),
          const SizedBox(height: TeqSpacing.s),
          Text(message,
              style: TeqTypography.bodyMedium.copyWith(color: textColor)),
          if (showRetry) ...[
            const SizedBox(height: TeqSpacing.m),
            TeqButton.outline(
              text: 'Tekrar Dene',
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadedBody extends StatelessWidget {
  final CreditGateState vm;
  final CreditFeature feature;
  final TranslationPack loc;
  final bool isDark;
  final Color textColor;
  final Color subColor;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onGoToWallet;

  const _LoadedBody({
    required this.vm,
    required this.feature,
    required this.loc,
    required this.isDark,
    required this.textColor,
    required this.subColor,
    required this.onConfirm,
    required this.onCancel,
    required this.onGoToWallet,
  });

  @override
  Widget build(BuildContext context) {
    final d = vm.data!;

    // Maliyet hesabı — blast için seçilen sayıya göre dinamik
    final isFreeOp = feature == CreditFeature.blast
        ? vm.freeUsed(d.freeRemaining) > 0 &&
            vm.paidCount(d.freeRemaining) == 0
        : d.isFree;
    final computedCost = feature == CreditFeature.blast
        ? vm.teqlikCost(d.freeRemaining, d.costTeqlik)
        : (d.isFree ? 0 : d.costTeqlik);
    final canAffordOp = feature == CreditFeature.blast
        ? d.teqlikBalance >= computedCost
        : d.canAfford;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kredi durum chip
        _CreditStatusChip(data: d, isDark: isDark, loc: loc),
        const SizedBox(height: TeqSpacing.m),

        // Blast: sayım seçici
        if (feature == CreditFeature.blast) ...[
          _BlastCountSelector(vm: vm, data: d, loc: loc, isDark: isDark),
          const SizedBox(height: TeqSpacing.m),
        ],

        // Maliyet satırı
        _InfoRow(
          label: loc.t('creditGateCostLabel'),
          value: isFreeOp
              ? loc.t('creditGateFree')
              : loc.t('creditGateCostValue',
                  {'cost': computedCost.toString()}),
          valueColor: isFreeOp
              ? TeqColors.success
              : (canAffordOp ? textColor : TeqColors.error),
          subColor: subColor,
        ),
        const SizedBox(height: TeqSpacing.xs),

        // Bakiye satırı
        _InfoRow(
          label: loc.t('creditGateBalanceLabel'),
          value: loc.t('creditGateBalanceValue',
              {'balance': d.teqlikBalance.toString()}),
          valueColor:
              canAffordOp ? TeqColors.success : TeqColors.error,
          subColor: subColor,
        ),

        if (!canAffordOp) ...[
          const SizedBox(height: TeqSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  loc.t('creditGateInsufficientBalance'),
                  style: TeqTypography.bodySmall.copyWith(
                    color: TeqColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: onGoToWallet,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: TeqSpacing.s, vertical: TeqSpacing.xxs),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  loc.t('creditGateGoToWallet'),
                  style: TeqTypography.bodySmall.copyWith(
                    color: TeqColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: TeqSpacing.l),

        // Aksiyon butonları
        Row(
          children: [
            Expanded(
              child: TeqButton.outline(
                text: loc.t('btnCancel'),
                onPressed: vm.isConfirming ? null : onCancel,
              ),
            ),
            const SizedBox(width: TeqSpacing.s),
            Expanded(
              child: TeqButton(
                text: loc.t('creditGateConfirm'),
                isLoading: vm.isConfirming,
                onPressed:
                    canAffordOp && !vm.isConfirming ? onConfirm : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Blast count seçici ──────────────────────────────────────────────────────────

class _BlastCountSelector extends ConsumerStatefulWidget {
  final CreditGateState vm;
  final CreditGateData data;
  final TranslationPack loc;
  final bool isDark;

  const _BlastCountSelector({
    required this.vm,
    required this.data,
    required this.loc,
    required this.isDark,
  });

  @override
  ConsumerState<_BlastCountSelector> createState() =>
      _BlastCountSelectorState();
}

class _BlastCountSelectorState
    extends ConsumerState<_BlastCountSelector> {
  bool _useCustomCount = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.vm.selectedCount.toString());
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    final parsed = int.tryParse(_ctrl.text);
    if (parsed == null) return;
    final maxAllowed = widget.data.audienceSize < widget.data.perOpCap
        ? widget.data.audienceSize
        : widget.data.perOpCap;
    if (maxAllowed < 1) return; // audienceSize=0 durumunda clamp(1,0) crash'i önle
    final clamped = parsed.clamp(1, maxAllowed);
    if (clamped != parsed) {
      final s = clamped.toString();
      _ctrl.value = TextEditingValue(
        text: s,
        selection: TextSelection.collapsed(offset: s.length),
      );
    }
    ref.read(creditGateProvider.notifier).setCount(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final d = widget.data;
    final isDark = widget.isDark;
    final borderColor =
        isDark ? TeqColors.borderDark : TeqColors.borderLight;
    final subColor = isDark
        ? TeqColors.textSecondaryDark
        : TeqColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(TeqSpacing.s),
      decoration: BoxDecoration(
        color: TeqColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded,
                  size: 16, color: TeqColors.info),
              const SizedBox(width: TeqSpacing.xxs),
              Expanded(
                child: Text(
                  loc.t('audienceReadyBuyersBanner',
                      {'count': d.audienceSize.toString()}),
                  style: TeqTypography.labelSmall
                      .copyWith(color: TeqColors.info),
                ),
              ),
            ],
          ),
          const SizedBox(height: TeqSpacing.xs),
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _useCustomCount,
                  activeColor: TeqColors.primary,
                  side: BorderSide(color: subColor),
                  onChanged: (val) =>
                      setState(() => _useCustomCount = val ?? false),
                ),
              ),
              const SizedBox(width: TeqSpacing.xs),
              Expanded(
                child: Text(
                  loc.t('audienceSendToX'),
                  style:
                      TeqTypography.bodySmall.copyWith(color: subColor),
                ),
              ),
            ],
          ),
          if (_useCustomCount) ...[
            const SizedBox(height: TeqSpacing.xs),
            Padding(
              padding:
                  const EdgeInsets.only(left: TeqSpacing.m + TeqSpacing.xxs),
              child: TeqTextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                hintText: loc.t('audiencePersonCountHint'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Yardımcı widget'lar ────────────────────────────────────────────────────────

class _FeatureIcon extends StatelessWidget {
  final CreditFeature feature;
  const _FeatureIcon({required this.feature});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (feature) {
      CreditFeature.blast =>
        (Icons.campaign_rounded, TeqColors.info),
      CreditFeature.boost =>
        (Icons.rocket_launch_rounded, const Color(0xFF6366F1)),
      CreditFeature.aiDesc =>
        (Icons.auto_awesome_rounded, TeqColors.primary),
      CreditFeature.reactivation =>
        (Icons.refresh_rounded, TeqColors.success),
    };
    return Container(
      padding: const EdgeInsets.all(TeqSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _CreditStatusChip extends StatelessWidget {
  final CreditGateData data;
  final bool isDark;
  final TranslationPack loc;

  const _CreditStatusChip({
    required this.data,
    required this.isDark,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color chipColor;

    if (data.withinWindow) {
      label = loc.t('creditGateWithinWindow');
      chipColor = TeqColors.success;
    } else if (data.freeRemaining > 0) {
      label = loc.t('creditGateFreeRemaining', {
        'remaining': data.freeRemaining.toString(),
        'total': data.freeLimitTotal.toString(),
      });
      chipColor = TeqColors.success;
    } else if (data.isStandard) {
      label = loc.t('creditGateStandardPaid');
      chipColor = TeqColors.warning;
    } else {
      label = loc.t('creditGateProExhausted',
          {'total': data.freeLimitTotal.toString()});
      chipColor = TeqColors.warning;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TeqSpacing.s,
        vertical: TeqSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TeqSpacing.radiusMax),
        border: Border.all(color: chipColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TeqTypography.labelSmall.copyWith(color: chipColor),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color subColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TeqTypography.bodyMedium.copyWith(color: subColor)),
        Text(value,
            style: TeqTypography.labelMedium.copyWith(color: valueColor)),
      ],
    );
  }
}
