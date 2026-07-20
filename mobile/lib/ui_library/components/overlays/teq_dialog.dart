import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';
import '../buttons/teq_button.dart';

/// Teqlif Design System - Dialog
/// Proje içerisindeki tüm standart açılır pencereler (AlertDialog)
class TeqDialog {
  TeqDialog._();

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required String message,
    String? primaryButtonText,
    VoidCallback? onPrimaryPressed,
    String? secondaryButtonText,
    VoidCallback? onSecondaryPressed,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? TeqColors.surfaceDark : TeqColors.surfaceLight;
    final textColor = isDark
        ? TeqColors.textPrimaryDark
        : TeqColors.textPrimaryLight;
    final subtitleColor = isDark
        ? TeqColors.textSecondaryDark
        : TeqColors.textSecondaryLight;

    return showDialog<T>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TeqSpacing.radiusL),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(TeqSpacing.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TeqTypography.h2.copyWith(color: textColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TeqSpacing.s),
                Text(
                  message,
                  style: TeqTypography.bodyLarge.copyWith(color: subtitleColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TeqSpacing.l),
                Row(
                  children: [
                    if (secondaryButtonText != null) ...[
                      Expanded(
                        child: TeqButton.outline(
                          text: secondaryButtonText,
                          onPressed:
                              onSecondaryPressed ??
                              () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: TeqSpacing.m),
                    ],
                    if (primaryButtonText != null)
                      Expanded(
                        child: TeqButton(
                          text: primaryButtonText,
                          onPressed: onPrimaryPressed,
                          customColor: isDestructive ? TeqColors.error : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
