import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/app_exception.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/captcha_service.dart';
import '../services/category_service.dart';
import '../services/client_logger.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';
import '../utils/error_helper.dart';
import '../screens/live/host_stream_screen.dart';

/// Canlı yayın başlatma dialog'unu gösterir.
/// [onStreamStarted]: yayın ekranından geri dönüldüğünde çağrılır (opsiyonel).
Future<void> showStartStreamDialog(
  BuildContext context, {
  VoidCallback? onStreamStarted,
}) async {
  final categories = await CategoryService.getCategories();
  final token = await StorageService.getToken();
  if (!context.mounted) return;
  final l = AppLocalizations.of(context)!;

  if (token == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.liveLoginRequired)),
    );
    return;
  }

  final titleController = TextEditingController();
  String? selectedCategory;
  String? errorText;
  int audienceSize = 0;
  double audienceCost = 0.0;
  bool audienceLoading = false;
  Timer? debounceTimer;

  Future<void> fetchAudience(
    String title,
    String? category,
    void Function(void Function()) setS,
  ) async {
    if (title.length < 3 || category == null) {
      setS(() {
        audienceSize = 0;
        audienceCost = 0.0;
        audienceLoading = false;
      });
      return;
    }
    setS(() => audienceLoading = true);
    final result = await AnalyticsService.getAudienceSize(
      title: title,
      category: category,
    );
    final size = (result?['audience_size'] as num?)?.toInt() ?? 0;
    final cost = (result?['estimated_cost'] as num?)?.toDouble() ?? 0.0;
    setS(() {
      audienceSize = size;
      audienceCost = cost;
      audienceLoading = false;
    });
  }

  final result = await showDialog<(String, String, bool, int)?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setStateDialog) => AlertDialog(
        title: Text(l.liveStartStreamDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('live_dialog_input_yayin_basligi'),
              controller: titleController,
              autofocus: true,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: l.liveStreamTitleHint,
                labelText: l.liveStreamTitleLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                debounceTimer?.cancel();
                debounceTimer = Timer(const Duration(milliseconds: 800), () {
                  fetchAudience(v.trim(), selectedCategory, setStateDialog);
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('live_dialog_select_kategori'),
              value: selectedCategory,
              decoration: InputDecoration(
                labelText: l.liveCategoryLabel,
                border: const OutlineInputBorder(),
              ),
              hint: Text(l.liveCategoryHint),
              items: categories
                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                  .toList(),
              onChanged: (v) {
                setStateDialog(() => selectedCategory = v);
                debounceTimer?.cancel();
                fetchAudience(
                    titleController.text.trim(), v, setStateDialog);
              },
            ),
            if (audienceLoading) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Kitle hesaplanıyor...',
                    style: TextStyle(fontSize: 12),
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
                        () => errorText = l.liveStreamTitleRequired);
                    return;
                  }
                  if (t.length < 3) {
                    setStateDialog(() => errorText = l.liveStreamTitleMin);
                    return;
                  }
                  if (selectedCategory == null) {
                    setStateDialog(
                        () => errorText = l.liveCategoryRequired);
                    return;
                  }
                  final confirmed = await _showBlastConfirmDialog(
                    ctx,
                    audienceSize: audienceSize,
                    audienceCost: audienceCost.toInt(),
                  );
                  if (confirmed == true && ctx.mounted) {
                    Navigator.pop(
                        ctx, (t, selectedCategory!, true, audienceCost.toInt()));
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
                              '$audienceSize Hazır Alıcıya Bildirim Gönder!',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kPrimary,
                              ),
                            ),
                            Text(
                              'Yayın başladığında push bildirim • ${audienceCost.toInt()} TUCi',
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
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const Key('live_dialog_btn_iptal'),
            onPressed: () {
              debounceTimer?.cancel();
              Navigator.pop(ctx);
            },
            child: Text(l.btnCancel),
          ),
          ElevatedButton(
            key: const Key('live_dialog_btn_baslat'),
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () {
              final t = titleController.text.trim();
              if (t.isEmpty) {
                setStateDialog(() => errorText = l.liveStreamTitleRequired);
                return;
              }
              if (t.length < 3) {
                setStateDialog(() => errorText = l.liveStreamTitleMin);
                return;
              }
              if (selectedCategory == null) {
                setStateDialog(() => errorText = l.liveCategoryRequired);
                return;
              }
              debounceTimer?.cancel();
              Navigator.pop(ctx, (t, selectedCategory!, false, 0));
            },
            child: Text(
              audienceSize > 0 ? 'Normal Başlat' : l.liveStartBtn,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );

  if (result == null) return;
  final (title, category, blastApproved, blastCost) = result;

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
    final streamToken = await StreamService.startStream(
      title,
      category,
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
          blastApproved: blastApproved,
          blastCost: blastCost.toDouble(),
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
    final ll = AppLocalizations.of(context)!;
    final msg = _mapCaptchaError(e, ll);
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
    if (context.mounted) showErrorSnackbar(context, e);
  }
}

Future<bool?> _showBlastConfirmDialog(
  BuildContext ctx, {
  required int audienceSize,
  required int audienceCost,
}) {
  return showDialog<bool>(
    context: ctx,
    builder: (dlgCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '🎯 Kitleyi Davet Et',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
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
                  label: 'Hedef Kitle',
                  value: '$audienceSize kişi',
                  color: kPrimary,
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.notifications_active_outlined,
                  label: 'Bildirim',
                  value: 'Push + Yayın linki',
                  color: const Color(0xFF3B82F6),
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'TUCi Maliyeti',
                  value: '$audienceCost TUCi',
                  color: const Color(0xFFB8860B),
                  bold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Yayın başladığında bildirim otomatik gönderilir.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dlgCtx, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dlgCtx, true),
          style: FilledButton.styleFrom(backgroundColor: kPrimary),
          child: const Text('Onayla ve Başlat'),
        ),
      ],
    ),
  );
}

String _mapCaptchaError(AppException e, AppLocalizations l) {
  if (e.statusCode == 403 || e.code == 'FORBIDDEN') return l.errorCaptchaFailed;
  if (e.statusCode == 429 || e.code == 'RATE_LIMIT_EXCEEDED') return l.errorTooFast;
  return e.message;
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
