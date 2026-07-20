import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';

/// Teqlif Design System - Bottom Sheet
/// Alttan açılan pencereler için merkezi tasarım standartları.
class TeqBottomSheet {
  TeqBottomSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool isScrollControlled = true,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? TeqColors.surfaceDark : TeqColors.surfaceLight;
    final textColor = isDark
        ? TeqColors.textPrimaryDark
        : TeqColors.textPrimaryLight;
    final handleColor = isDark ? TeqColors.borderDark : TeqColors.borderLight;

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TeqSpacing.radiusXl),
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tutamaç (Handle)
                const SizedBox(height: TeqSpacing.s),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: handleColor,
                    borderRadius: BorderRadius.circular(TeqSpacing.radiusMax),
                  ),
                ),
                const SizedBox(height: TeqSpacing.s),

                // Başlık
                if (title != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TeqSpacing.m,
                    ),
                    child: Text(
                      title,
                      style: TeqTypography.h2.copyWith(color: textColor),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: TeqSpacing.m),
                  Divider(color: handleColor, height: 1),
                ],

                // İçerik
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(TeqSpacing.m),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
