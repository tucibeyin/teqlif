import 'package:flutter/material.dart';

class AppTheme {
  static const _primary = Color(0xFF00B4CC);
  static const _primaryDark = Color(0xFF008FA3);
  static const _bg = Color(0xFFF4F7FA);
  static const _card = Color(0xFFFFFFFF);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primary,
          brightness: Brightness.light,
          primary: _primary,
          surface: _card,
          onSurface: const Color(0xFF0F1923),
        ),
        scaffoldBackgroundColor: _bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFCFCFC),
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
          shadowColor: Color(0x14000000),
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF0F1923),
          ),
          iconTheme: IconThemeData(color: Color(0xFF0F1923)),
        ),
        cardTheme: CardThemeData(
          color: _card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE2EBF0)),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFB),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2EBF0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2EBF0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _primary, width: 1.5),
          ),
          hintStyle: const TextStyle(color: Color(0xFF9AAAB8)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _primary,
            side: const BorderSide(color: _primary),
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _card,
          selectedItemColor: _primary,
          unselectedItemColor: Color(0xFF9AAAB8),
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFE6F9FC),
          labelStyle:
              const TextStyle(color: _primaryDark, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100)),
          side: BorderSide.none,
        ),
        dividerTheme:
            const DividerThemeData(color: Color(0xFFE2EBF0), thickness: 1),
      );
}

// Color constants for easy access
extension AppColors on BuildContext {
  Color get primary => const Color(0xFF00B4CC);
  Color get primaryDark => const Color(0xFF008FA3);
  Color get textMuted => const Color(0xFF9AAAB8);
  Color get textSecondary => const Color(0xFF4A5568);
  Color get cardBg => const Color(0xFFFFFFFF);
  Color get scaffoldBg => const Color(0xFFF4F7FA);
  Color get border => const Color(0xFFE2EBF0);
  Color get success => const Color(0xFF10B981);
  Color get danger => const Color(0xFFEF4444);
}
