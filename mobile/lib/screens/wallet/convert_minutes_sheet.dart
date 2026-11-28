import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_colors.dart';
import '../../core/event_bus.dart';
import '../../services/localization_service.dart';
import '../../ui_library/components/overlays/teq_toast.dart';
import '../viewmodels/wallet_conversion_view_model.dart';

class ConvertMinutesSheet extends ConsumerStatefulWidget {
  final int currentBalance;
  final int teqlikPerMinute;

  const ConvertMinutesSheet({
    super.key,
    required this.currentBalance,
    required this.teqlikPerMinute,
  });

  static Future<void> show(
    BuildContext context, {
    required int currentBalance,
    required int teqlikPerMinute,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConvertMinutesSheet(
        currentBalance: currentBalance,
        teqlikPerMinute: teqlikPerMinute,
      ),
    );
  }

  @override
  ConsumerState<ConvertMinutesSheet> createState() => _ConvertMinutesSheetState();
}

class _ConvertMinutesSheetState extends ConsumerState<ConvertMinutesSheet> {
  late final TextEditingController _ctrl;
  late StreamSubscription<WalletConversionSuccessEvent> _sub;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '0');
    _sub = eventBus.on<WalletConversionSuccessEvent>().listen((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sub.cancel();
    super.dispose();
  }

  void _onTextChanged(String val, WalletConversionNotifier notifier) {
    final n = int.tryParse(val) ?? 0;
    notifier.setMinutes(n < 0 ? 0 : n);
  }

  void _increment(WalletConversionNotifier notifier, int current) {
    final next = current + 1;
    _ctrl.text = '$next';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    notifier.setMinutes(next);
  }

  void _decrement(WalletConversionNotifier notifier, int current) {
    final next = current <= 1 ? 0 : current - 1;
    _ctrl.text = '$next';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    notifier.setMinutes(next);
  }

  Future<void> _onConvert(
    BuildContext ctx,
    WalletConversionNotifier notifier,
    WalletConversionState state,
    TranslationPack loc,
  ) async {
    if (state.minutes <= 0) {
      TeqToast.error(loc.t('walletConvertZeroError'));
      return;
    }
    final cost = state.costFor(widget.teqlikPerMinute);
    if (cost > widget.currentBalance) {
      TeqToast.error(loc.t('walletConvertInsufficient'));
      return;
    }

    final confirmed = await _showConfirmDialog(ctx, state.minutes, cost, loc);
    if (!confirmed || !mounted) return;

    final ok = await notifier.convert(widget.currentBalance);
    if (!mounted) return;

    if (!ok) {
      final errCode = ref.read(walletConversionProvider).errorCode ?? 'UNKNOWN_ERROR';
      final msg = errCode == 'INSUFFICIENT_TEQLIK'
          ? loc.t('walletConvertInsufficient')
          : errCode == 'INVALID_CONVERSION_AMOUNT'
              ? loc.t('walletConvertZeroError')
              : loc.t('errorGeneric');
      TeqToast.error(msg);
    } else {
      TeqToast.success(
        loc.t('walletConvertSuccess', {'minutes': state.minutes.toString()}),
      );
    }
  }

  Future<bool> _showConfirmDialog(
    BuildContext ctx,
    int minutes,
    int cost,
    TranslationPack loc,
  ) async {
    return await showDialog<bool>(
          context: ctx,
          builder: (dCtx) => AlertDialog(
            backgroundColor: AppColors.card(dCtx),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              loc.t('walletConvertConfirmTitle'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary(dCtx),
              ),
            ),
            content: Text(
              loc.t('walletConvertConfirmBody', {
                'teqlik': cost.toString(),
                'minutes': minutes.toString(),
              }),
              style: TextStyle(color: AppColors.textSecondary(dCtx), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(false),
                child: Text(
                  loc.t('walletConvertConfirmCancel'),
                  style: TextStyle(color: AppColors.textSecondary(dCtx)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(true),
                child: Text(
                  loc.t('walletConvertConfirmOk'),
                  style: const TextStyle(
                    color: Color(0xFF06B6D4),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final state = ref.watch(walletConversionProvider);
    final notifier = ref.read(walletConversionProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cost = state.costFor(widget.teqlikPerMinute);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tutamaç
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Başlık
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.t('walletRateLiveStream'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.swap_horiz_rounded,
                      size: 20,
                      color: Color(0xFF06B6D4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'teqlik',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  loc.t('walletConvertSheetDesc'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 4),

                // Mevcut bakiye
                Text(
                  '${loc.t("walletConvertBalance")}: ${widget.currentBalance} teqlik',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
                ),
                const SizedBox(height: 20),

                // Oran bilgisi
                Text(
                  loc.t('walletConvertRateInfo'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF06B6D4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),

                // Input satırı: stepper + teqlik göstergesi + DÖNÜŞTÜR butonu
                Row(
                  children: [
                    // Azalt
                    _StepperBtn(
                      icon: Icons.remove,
                      onTap: () => _decrement(notifier, state.minutes),
                    ),
                    const SizedBox(width: 8),

                    // Dakika input
                    SizedBox(
                      width: 72,
                      child: TextField(
                        controller: _ctrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (v) => _onTextChanged(v, notifier),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.border(context)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 1.5),
                          ),
                          hintText: '0',
                          hintStyle: TextStyle(color: AppColors.textSecondary(context)),
                        ),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // "dakika" birimi (input'un sağında, + butonunun solunda)
                    Text(
                      loc.t('walletConvertMinuteUnit'),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Artır
                    _StepperBtn(
                      icon: Icons.add,
                      onTap: () => _increment(notifier, state.minutes),
                    ),

                    // Hesaplanan teqlik
                    const Spacer(),
                    Text(
                      '= $cost teqlik',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cost > widget.currentBalance
                            ? Colors.red
                            : const Color(0xFF06B6D4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // DÖNÜŞTÜR butonu
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: state.isConverting
                        ? null
                        : () => _onConvert(context, notifier, state, loc),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: state.isConverting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            loc.t('walletConvertButton'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary(context)),
      ),
    );
  }
}
