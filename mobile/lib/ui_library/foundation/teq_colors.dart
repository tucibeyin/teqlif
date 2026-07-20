import 'package:flutter/material.dart';

/// Teqlif Design System - Colors
/// Uygulama içerisindeki tüm renklerin tek merkezden yönetildiği Foundation dosyası.
class TeqColors {
  TeqColors._();

  // Primary (Brand) Colors
  static const Color primary = Color(0xFF06B6D4);
  static const Color primaryDark = Color(0xFF0891B2);
  static const Color primaryLight = Color(0xFF22D3EE);
  static const Color primaryBg = Color(0xFFECFEFF);

  // Background Colors
  static const Color backgroundLight = Color(0xFFF9FAFB);
  static const Color backgroundDark = Color(0xFF000000);

  // Surface Colors (Cards, Dialogs)
  static const Color surfaceLight = Colors.white;
  static const Color surfaceDark = Color(0xFF1C1C1C);

  // Text Colors
  static const Color textPrimaryLight = Color(0xFF1A1A1A);
  static const Color textPrimaryDark = Colors.white;

  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color textSecondaryDark = Color(0xFFA8A8A8);

  static const Color textHintLight = Color(0xFF9CA3AF);
  static const Color textHintDark = Color(0xFF737373);

  // Border & Divider Colors
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color borderDark = Color(0xFF363636);

  static const Color dividerLight = Color(0xFFF3F4F6);
  static const Color dividerDark = Color(0xFF262626);

  // Feedback Colors
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
}
