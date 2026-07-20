import 'package:flutter/material.dart';
import '../foundation/teq_colors.dart';
import '../foundation/teq_spacing.dart';

/// Teqlif Design System - Theme
/// Mevcut `lib/config/theme.dart` dosyasının yeni yapıya entegre edilmiş hali.
class TeqTheme {
  TeqTheme._();

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TeqColors.primary,
      primary: TeqColors.primary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: TeqColors.surfaceLight,
      foregroundColor: TeqColors.textPrimaryLight,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(
        color: TeqColors.textPrimaryLight,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: TeqColors.primary,
      unselectedItemColor: TeqColors.textHintLight,
      backgroundColor: TeqColors.surfaceLight,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: TeqColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.borderLight, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TeqSpacing.m,
        vertical: TeqSpacing.m,
      ),
      labelStyle: const TextStyle(color: TeqColors.textSecondaryLight),
    ),
    scaffoldBackgroundColor: TeqColors.backgroundLight,
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: TeqColors.primary,
      secondary: TeqColors.primaryLight,
      surface: TeqColors.surfaceDark,
      onSurface: Colors.white,
      onPrimary: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: TeqColors.backgroundDark,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
    ),
    scaffoldBackgroundColor: TeqColors.backgroundDark,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: TeqColors.backgroundDark,
      indicatorColor: const Color(0xFF0C2D35),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: TeqColors.backgroundDark,
      selectedItemColor: TeqColors.primary,
      unselectedItemColor: TeqColors.textSecondaryDark,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: TeqColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: const CardThemeData(color: TeqColors.surfaceDark, elevation: 0),
    dividerTheme: const DividerThemeData(
      color: TeqColors.dividerDark,
      space: 1,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TeqColors.surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TeqSpacing.m,
        vertical: TeqSpacing.m,
      ),
      labelStyle: const TextStyle(color: TeqColors.textSecondaryDark),
      hintStyle: const TextStyle(color: TeqColors.textHintDark),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? TeqColors.primary
            : TeqColors.textSecondaryDark,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? TeqColors.primaryLight.withValues(alpha: 0.5)
            : TeqColors.borderDark,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      textColor: Colors.white,
      iconColor: Colors.white,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
      bodySmall: TextStyle(color: TeqColors.textSecondaryDark),
      titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(color: TeqColors.textSecondaryDark),
    ),
  );
}
