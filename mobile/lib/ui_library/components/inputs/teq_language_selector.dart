import 'package:flutter/material.dart';
import '../../../config/supported_languages.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';
import '../overlays/teq_bottom_sheet.dart';

/// Teqlif Design System — Dil Seçici
///
/// Seçili dili gösterir; dokunulduğunda bir bottom sheet açarak
/// desteklenen diller arasından seçim yapılmasını sağlar.
///
/// Kullanım:
/// ```dart
/// TeqLanguageSelector(
///   selectedLang: _currentLang,
///   sheetTitle: loc.t('settingsLanguage'),
///   onChanged: (code) => _onLangChange(code),
/// )
/// ```
class TeqLanguageSelector extends StatelessWidget {
  const TeqLanguageSelector({
    super.key,
    required this.selectedLang,
    required this.onChanged,
    this.sheetTitle,
  });

  final String selectedLang;
  final ValueChanged<String> onChanged;

  /// Bottom sheet başlığı — genellikle `loc.t('settingsLanguage')`.
  final String? sheetTitle;

  AppLanguage get _current => kSupportedLanguages.firstWhere(
        (l) => l.code == selectedLang,
        orElse: () => kSupportedLanguages.first,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? TeqColors.textPrimaryDark : TeqColors.textPrimaryLight;
    final secondaryColor =
        isDark ? TeqColors.textSecondaryDark : TeqColors.textSecondaryLight;

    return InkWell(
      onTap: () => _showSheet(context),
      borderRadius: BorderRadius.circular(TeqSpacing.radiusL),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TeqSpacing.s,
          vertical: TeqSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language_outlined, size: 15, color: secondaryColor),
            const SizedBox(width: TeqSpacing.xxs),
            Text(
              _current.nativeName,
              style: TeqTypography.bodyMedium.copyWith(color: textColor),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: secondaryColor),
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    TeqBottomSheet.show<void>(
      context: context,
      title: sheetTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: kSupportedLanguages
            .map((lang) => _TeqLanguageTile(
                  option: lang,
                  isSelected: lang.code == selectedLang,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (lang.code != selectedLang) onChanged(lang.code);
                  },
                ))
            .toList(),
      ),
    );
  }
}

class _TeqLanguageTile extends StatelessWidget {
  const _TeqLanguageTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final AppLanguage option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? TeqColors.textPrimaryDark : TeqColors.textPrimaryLight;
    final secondaryColor =
        isDark ? TeqColors.textSecondaryDark : TeqColors.textSecondaryLight;
    final dividerColor = isDark ? TeqColors.dividerDark : TeqColors.dividerLight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TeqSpacing.m,
              vertical: TeqSpacing.s,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.nativeName,
                    style: TeqTypography.bodyLarge.copyWith(
                      color: isSelected ? TeqColors.primary : textColor,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_rounded,
                      size: 20, color: TeqColors.primary)
                else
                  Icon(Icons.check_rounded, size: 20, color: secondaryColor.withValues(alpha: 0)),
              ],
            ),
          ),
        ),
        if (option.code != kSupportedLanguages.last.code)
          Divider(height: 1, color: dividerColor),
      ],
    );
  }
}
