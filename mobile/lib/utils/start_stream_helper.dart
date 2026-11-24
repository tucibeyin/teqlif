import 'dart:async';
import '../main.dart' show providerContainer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../core/app_exception.dart';
import '../services/analytics_service.dart';
import '../services/captcha_service.dart';
import '../services/category_service.dart';
import '../services/client_logger.dart';
import '../services/localization_service.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';
import '../services/catalog_service.dart';
import 'subcategory_icons.dart';
import '../ui_library/components/overlays/teq_toast.dart';
import '../screens/live/host_stream_screen.dart';
import '../services/permission_service.dart';
import '../core/user_tier.dart';
import '../screens/profile_screen.dart';

/// Canlı yayın başlatma dialog'unu gösterir.
/// [onStreamStarted]: yayın ekranından geri dönüldüğünde çağrılır (opsiyonel).
Future<void> showStartStreamDialog(
  BuildContext context, {
  VoidCallback? onStreamStarted,
}) async {
  final locale = context.mounted
      ? Localizations.localeOf(context).languageCode
      : 'tr';
  final categories = await providerContainer.read(categoryServiceProvider).getCategories(
    locale: locale,
    forStream: true,
  );
  final token = await StorageService.getToken();
  if (!context.mounted) return;
  final loc = ProviderScope.containerOf(context, listen: false).read(localizationProvider);

  if (token == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.t('liveLoginRequired'))),
    );
    return;
  }

  // ── YENİ: İzin Kontrolü Dialog Öncesine Taşındı ──────────────────────────
  final hasPermission = await PermissionService.requestLiveStreamPermissions(context);
  if (!hasPermission) return;
  // ──────────────────────────────────────────────────────────────────────────

  final userInfo = await StorageService.getUserInfo();
  final userType = userInfo?['user_type'] as String? ?? UserTier.standard;

  // Aylık stream kullanımı — blast-credits endpoint'inden gelir
  final blastCreditsData = await providerContainer
      .read(analyticsServiceProvider)
      .getBlastCredits();
  final streamSecondsUsed =
      (blastCreditsData?['monthly_stream_seconds_used'] as num?)?.toInt() ?? 0;

  if (!context.mounted) return;

  final titleController = TextEditingController();
  String? selectedCategory;
  String? selectedSubcategory;
  bool hasSubcategories = false;
  String? errorText;
  int audienceSize = 0;
  double audienceCost = 0.0;
  bool audienceLoading = false;
  Timer? debounceTimer;
  String selectedQuality = UserTier.maxStreamQuality(userType);

  Future<void> fetchAudience(
    String title,
    String? category,
    String? subcategory,
    void Function(void Function()) setS,
  ) async {
    if (title.length < 3 || category == null || (hasSubcategories && subcategory == null)) {
      setS(() {
        audienceSize = 0;
        audienceCost = 0.0;
        audienceLoading = false;
      });
      return;
    }
    setS(() => audienceLoading = true);
    final result = await providerContainer.read(analyticsServiceProvider).getAudienceSize(
      title: title,
      category: category,
      subcategory: subcategory ?? '',
    );
    final size = (result?['audience_size'] as num?)?.toInt() ?? 0;
    final cost = (result?['estimated_cost'] as num?)?.toDouble() ?? 0.0;
    setS(() {
      audienceSize = size;
      audienceCost = cost;
      audienceLoading = false;
    });
  }

  if (!context.mounted) return;
  final result = await showDialog<(String, String, String, bool, int, String)?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setStateDialog) => AlertDialog(
        title: Text(loc.t('liveStartStreamDialogTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
              key: const Key('live_dialog_input_yayin_basligi'),
              controller: titleController,
              autofocus: true,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: loc.t('liveStreamTitleHint'),
                labelText: loc.t('liveStreamTitleLabel'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                debounceTimer?.cancel();
                debounceTimer = Timer(const Duration(milliseconds: 800), () {
                  fetchAudience(v.trim(), selectedCategory, selectedSubcategory, setStateDialog);
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('live_dialog_select_kategori'),
              // ignore: deprecated_member_use
              value: selectedCategory,
              decoration: InputDecoration(
                labelText: loc.t('liveCategoryLabel'),
                border: const OutlineInputBorder(),
              ),
              hint: Text(loc.t('liveCategoryHint')),
              items: categories
                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                  .toList(),
              onChanged: (v) {
                setStateDialog(() {
                  selectedCategory = v;
                  selectedSubcategory = null;
                  hasSubcategories = CatalogService.subcategoriesFor(v ?? '').isNotEmpty;
                });
                debounceTimer?.cancel();
                fetchAudience(titleController.text.trim(), v, selectedSubcategory, setStateDialog);
              },
            ),
            if (hasSubcategories) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('live_dialog_select_alt_kategori'),
                // ignore: deprecated_member_use
                value: selectedSubcategory,
                decoration: InputDecoration(
                  labelText: loc.t('liveSubcategoryLabel'),
                  border: const OutlineInputBorder(),
                ),
                hint: Text(loc.t('liveSubcategoryHint')),
                items: CatalogService.subcategoriesFor(selectedCategory ?? '')
                    .map((s) => DropdownMenuItem(
                          value: s.$1,
                          child: Row(
                            children: [
                              Icon(getSubcategoryIcon(s.$1), size: 20, color: kPrimary),
                              const SizedBox(width: 8),
                              Text(loc.t(s.$2)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  setStateDialog(() => selectedSubcategory = v);
                  debounceTimer?.cancel();
                  fetchAudience(titleController.text.trim(), selectedCategory, v, setStateDialog);
                },
              ),
            ],
            if (audienceLoading) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    loc.t('audienceCalculating'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ] else if (audienceSize > 0) ...[
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final t = titleController.text.trim();
                  if (t.isEmpty) {
                    setStateDialog(
                        () => errorText = loc.t('liveStreamTitleRequired'));
                    return;
                  }
                  if (t.length < 3) {
                    setStateDialog(() => errorText = loc.t('liveStreamTitleMin'));
                    return;
                  }
                  if (selectedCategory == null) {
                    setStateDialog(
                        () => errorText = loc.t('liveCategoryRequired'));
                    return;
                  }
                  if (hasSubcategories && selectedSubcategory == null) {
                    setStateDialog(
                        () => errorText = loc.t('liveSubcategoryRequired'));
                    return;
                  }
                  final confirmed = await _showBlastConfirmDialog(
                    ctx,
                    loc: loc,
                    audienceSize: audienceSize,
                    audienceCost: audienceCost.toInt(),
                  );
                  if (confirmed == true && ctx.mounted) {
                    Navigator.pop(ctx, (
                      t, selectedCategory!, selectedSubcategory ?? '',
                      true, audienceCost.toInt(), selectedQuality,
                    ));
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kPrimary.withValues(alpha: 0.12),
                        kPrimary.withValues(alpha: 0.06)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kPrimary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Text('🎯', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.t('audienceReadyBuyersBanner', {'count': audienceSize.toString()}),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kPrimary,
                              ),
                            ),
                            Text(
                              audienceCost == 0
                                  ? loc.t('blastSubtitleFree')
                                  : loc.t('blastSubtitlePaid', {'cost': audienceCost.toInt().toString()}),
                              style: TextStyle(
                                fontSize: 11,
                                color: kPrimary.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: kPrimary, size: 18),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _StreamQualitySelector(
              userType: userType,
              selectedQuality: selectedQuality,
              loc: loc,
              onQualitySelected: (q) => setStateDialog(() => selectedQuality = q),
            ),
            const SizedBox(height: 8),
            _StreamHoursWarningRow(
              userType: userType,
              streamSecondsUsed: streamSecondsUsed,
              loc: loc,
            ),
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
        ),
        actions: [
          TextButton(
            key: const Key('live_dialog_btn_iptal'),
            onPressed: () {
              debounceTimer?.cancel();
              Navigator.pop(ctx);
            },
            child: Text(loc.t('btnCancel')),
          ),
          Builder(builder: (ctx2) {
            final limitSecs = UserTier.streamLimitSeconds(userType);
            final limitReached = limitSecs != null && streamSecondsUsed >= limitSecs;
            return ElevatedButton(
              key: const Key('live_dialog_btn_baslat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: limitReached ? Colors.grey : kPrimary,
              ),
              onPressed: limitReached ? null : () {
                final t = titleController.text.trim();
                if (t.isEmpty) {
                  setStateDialog(() => errorText = loc.t('liveStreamTitleRequired'));
                  return;
                }
                if (t.length < 3) {
                  setStateDialog(() => errorText = loc.t('liveStreamTitleMin'));
                  return;
                }
                if (selectedCategory == null) {
                  setStateDialog(() => errorText = loc.t('liveCategoryRequired'));
                  return;
                }
                if (hasSubcategories && selectedSubcategory == null) {
                  setStateDialog(() => errorText = loc.t('liveSubcategoryRequired'));
                  return;
                }
                debounceTimer?.cancel();
                Navigator.pop(ctx, (
                  t, selectedCategory!, selectedSubcategory ?? '',
                  false, 0, selectedQuality,
                ));
              },
              child: Text(
                limitReached
                    ? loc.tOr('streamLimitReached', 'Limit Doldu')
                    : audienceSize > 0
                        ? loc.t('btnStartNormal')
                        : loc.t('liveStartBtn'),
                style: const TextStyle(color: Colors.white),
              ),
            );
          }),
        ],
      ),
    ),
  );

  if (result == null) return;
  final (title, category, subcategory, blastApproved, blastCost, quality) = result;

  providerContainer.read(analyticsServiceProvider).trackEvent('stream_start_intent', {
    'category': category,
    'subcategory': subcategory,
    'blast_approved': blastApproved,
  });

  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator(color: kPrimary)),
    ),
  );

  final captchaToken = await CaptchaService.getToken();
  if (!context.mounted) return;

  try {
    final userInfo = await StorageService.getUserInfo();
    final hostUsername = userInfo?['username'] as String? ?? '';
    final streamToken = await providerContainer.read(streamServiceProvider).startStream(
      title,
      category,
      subcategory,
      captchaToken: captchaToken,
    );
    if (!context.mounted) return;
    Navigator.pop(context);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HostStreamScreen(
          streamToken: streamToken,
          title: title,
          hostUsername: hostUsername,
          blastApproved: blastApproved,
          blastCost: blastCost.toDouble(),
          quality: quality,
        ),
      ),
    );
    onStreamStarted?.call();
  } on AppException catch (e, st) {
    if (!context.mounted) return;
    Navigator.pop(context);
    ClientLogger.report(
      tag: 'StartStream',
      message:
          'startStream AppException | code=${e.code} status=${e.statusCode}',
      error: e,
      stackTrace: st,
      details: {'title': title, 'category': category},
    );
    final msg = _mapCaptchaError(e, loc);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  } catch (e, st) {
    if (context.mounted) Navigator.pop(context);
    ClientLogger.report(
      tag: 'StartStream',
      message: 'startStream beklenmeyen hata',
      error: e,
      stackTrace: st,
      details: {'title': title, 'category': category},
    );
    TeqToast.error(loc.t('errorGenericRetry'));
  }
}

Future<bool?> _showBlastConfirmDialog(
  BuildContext ctx, {
  required TranslationPack loc,
  required int audienceSize,
  required int audienceCost,
}) {
  final isFree = audienceCost == 0;
  return showDialog<bool>(
    context: ctx,
    builder: (dlgCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        loc.t('blastInviteDialogTitle'),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPrimary.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.people_alt_outlined,
                  label: loc.t('blastTargetAudience'),
                  value: '$audienceSize kişi',
                  color: kPrimary,
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.notifications_active_outlined,
                  label: loc.t('blastNotificationLabel'),
                  value: loc.t('blastNotificationValue'),
                  color: const Color(0xFF3B82F6),
                ),
                const SizedBox(height: 10),
                isFree
                    ? _InfoRow(
                        icon: Icons.check_circle_outline,
                        label: loc.t('blastConfirmCostFreeLabel'),
                        value: loc.t('blastConfirmCostFree'),
                        color: const Color(0xFF22C55E),
                        bold: true,
                      )
                    : _InfoRow(
                        icon: Icons.account_balance_wallet_outlined,
                        label: loc.t('blastConfirmCostPaidLabel'),
                        value: '$audienceCost teqlik',
                        color: const Color(0xFFB8860B),
                        bold: true,
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            loc.t('streamNotificationAutoSent'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dlgCtx, false),
          child: Text(loc.t('btnDismiss')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dlgCtx, true),
          style: FilledButton.styleFrom(backgroundColor: kPrimary),
          child: Text(loc.t('actionConfirmAndStart')),
        ),
      ],
    ),
  );
}

String _mapCaptchaError(AppException e, TranslationPack loc) {
  if (e.statusCode == 403 || e.code == 'FORBIDDEN') return loc.t('errorCaptchaFailed');
  if (e.statusCode == 429 || e.code == 'RATE_LIMIT_EXCEEDED') return loc.t('errorTooFast');
  if (e.code == 'STREAM_MONTHLY_LIMIT_REACHED') return loc.t('streamMonthlyLimitReached');
  return e.message;
}

/// Yayın kalite seçici — tier'a göre 540p/720p/1080p chip'leri
class _StreamQualitySelector extends StatelessWidget {
  final String userType;
  final String selectedQuality;
  final TranslationPack loc;
  final void Function(String quality) onQualitySelected;

  const _StreamQualitySelector({
    required this.userType,
    required this.selectedQuality,
    required this.loc,
    required this.onQualitySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hd_outlined, size: 16),
            const SizedBox(width: 6),
            Text(
              loc.tOr('liveStreamQualityLabel', 'Yayın Kalitesi'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: UserTier.allStreamQualities.map((q) {
            final locked = UserTier.isQualityLocked(userType, q);
            final selected = !locked && selectedQuality == q;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: locked
                    ? () => Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(builder: (_) => const WalletScreen()),
                        )
                    : () => onQualitySelected(q),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: locked
                        ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                        : selected
                            ? kPrimary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: locked
                          ? Theme.of(context).dividerColor
                          : selected
                              ? kPrimary
                              : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (locked) ...[
                        Icon(Icons.lock_outline, size: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        q,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: locked
                              ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                              : selected
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Aylık yayın süresi uyarı satırı
class _StreamHoursWarningRow extends StatelessWidget {
  final String userType;
  final int streamSecondsUsed;
  final TranslationPack loc;

  const _StreamHoursWarningRow({
    required this.userType,
    required this.streamSecondsUsed,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final limitSecs = UserTier.streamLimitSeconds(userType);
    if (limitSecs == null) return const SizedBox.shrink(); // PREMIUM — sınırsız

    final remainingSecs = (limitSecs - streamSecondsUsed).clamp(0, limitSecs);
    final remainingHours = (remainingSecs / 3600).ceil();
    final progress = streamSecondsUsed / limitSecs;
    final isAtLimit = remainingSecs == 0;
    final isLowWarning = !isAtLimit && progress >= 0.8; // %80 → sarı

    final Color color = isAtLimit
        ? const Color(0xFFEF4444)
        : isLowWarning
            ? const Color(0xFFF59E0B)
            : const Color(0xFF22C55E);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: isAtLimit || isLowWarning ? 0.4 : 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            isAtLimit ? Icons.block_outlined : Icons.timer_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAtLimit
                  ? loc.tOr('streamLimitReachedWarning', 'Aylık yayın limitine ulaştınız')
                  : loc.tOr(
                      'streamHoursLeft',
                      'Bu ay {hours} saatiniz kaldı',
                    ).replaceAll('{hours}', remainingHours.toString()),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
