import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_colors.dart';
import '../services/localization_service.dart';
import '../services/storage_service.dart';

/// Kullanıcının aktif oturumu olup olmadığını kontrol eder.
/// Modal bu değere göre "Hesabı Sil" butonunu gösterir ya da gizler.
final _hasSessionProvider = FutureProvider<bool>((ref) async {
  final token = await StorageService.getToken();
  return token != null;
});

/// KVKK Madde 10 gereklerini karşılayan aydınlatma metni modalı.
/// Oturum açık kullanıcılara "Hesabı Sil" butonu gösterir.
/// Buton basıldığında `true` döndürür; settings ekranı bu sinyali
/// alıp kendi delete flow'unu başlatır.
class ConsentNoticeModal extends ConsumerWidget {
  const ConsentNoticeModal({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ConsentNoticeModal(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final hasSession = ref.watch(_hasSessionProvider);
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    final showDeleteButton = hasSession.maybeWhen(
      data: (v) => v,
      orElse: () => false,
    );

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.bg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary(context).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    loc.t('consentPrivacyNoticeTitle'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Text(
                loc.t('consentPrivacyNoticeBody'),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.6,
                ),
              ),
            ),
          ),
          if (showDeleteButton) ...[
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFEF4444),
                    size: 18,
                  ),
                  label: Text(
                    loc.t('btnDeleteAccount'),
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                    ),
                  ),
                ),
              ),
            ),
          ] else
            const SizedBox(height: 20),
        ],
      ),
    );
  }
}
