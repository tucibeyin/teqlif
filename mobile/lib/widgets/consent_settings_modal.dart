import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_colors.dart';
import '../services/localization_service.dart';

const _localeNames = {
  'tr': 'Türkçe',
  'en': 'English',
  'ru': 'Русский',
  'ar': 'العربية',
};

/// Ayarlar ekranından açılan KVKK modalı.
/// Kullanıcının onay tarihini ve dilini gösterir, aydınlatma metnini sunar
/// ve hesap silme aksiyonunu başlatmak için sinyal döndürür.
class ConsentSettingsModal extends ConsumerWidget {
  final DateTime? consentAt;
  final String? consentLocale;

  const ConsentSettingsModal({
    super.key,
    this.consentAt,
    this.consentLocale,
  });

  static Future<bool?> show(
    BuildContext context, {
    DateTime? consentAt,
    String? consentLocale,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConsentSettingsModal(
        consentAt: consentAt,
        consentLocale: consentLocale,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final maxHeight = MediaQuery.of(context).size.height * 0.9;
    final localeName = _localeNames[consentLocale] ?? consentLocale ?? '';

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
          // Başlık
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
          // Onay tarihi ve dili
          if (consentAt != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      localeName.isNotEmpty
                          ? loc.t('consentGivenOn')
                              .replaceFirst('{date}', _formatDate(consentAt!))
                              .replaceFirst('{locale}', localeName)
                          : loc.t('consentGivenOnDateOnly')
                              .replaceFirst('{date}', _formatDate(consentAt!)),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          // Aydınlatma metni
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
          const Divider(height: 1),
          // Hesap silme bölümü
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.t('consentSettingsDeleteHint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
