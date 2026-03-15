import 'package:flutter/material.dart';

class AppColors {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color bg(BuildContext context) =>
      isDark(context) ? const Color(0xFF000000) : const Color(0xFFFAFAFA);

  static Color surface(BuildContext context) =>
      isDark(context) ? const Color(0xFF121212) : const Color(0xFFFFFFFF);

  static Color surfaceVariant(BuildContext context) =>
      isDark(context) ? const Color(0xFF1C1C1C) : const Color(0xFFF9FAFB);

  static Color card(BuildContext context) =>
      isDark(context) ? const Color(0xFF262626) : const Color(0xFFFFFFFF);

  static Color border(BuildContext context) =>
      isDark(context) ? const Color(0xFF363636) : const Color(0xFFDBDBDB);

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8A8A8) : const Color(0xFF737373);

  static Color textTertiary(BuildContext context) =>
      isDark(context) ? const Color(0xFF737373) : const Color(0xFF9CA3AF);

  static Color iconColor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFFFFFF) : const Color(0xFF374151);

  static Color iconSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8A8A8) : const Color(0xFF6B7280);

  static Color divider(BuildContext context) =>
      isDark(context) ? const Color(0xFF262626) : const Color(0xFFE5E7EB);

  static Color inputFill(BuildContext context) =>
      isDark(context) ? const Color(0xFF1C1C1C) : const Color(0xFFF3F4F6);

  static Color primaryBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C2D35) : const Color(0xFFECFEFF);

  static Color navBar(BuildContext context) =>
      isDark(context) ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}
