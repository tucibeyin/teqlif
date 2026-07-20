import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';

enum TeqSnackBarType { success, error, info, warning }

/// Teqlif Design System - SnackBar
/// Projedeki tüm SnackBar (Toast) mesajları için merkezi yapı.
class TeqSnackBar {
  TeqSnackBar._();

  static void show(
    BuildContext context, {
    required String message,
    TeqSnackBarType type = TeqSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    Color bgColor;
    IconData icon;

    switch (type) {
      case TeqSnackBarType.success:
        bgColor = TeqColors.success;
        icon = Icons.check_circle_outline;
        break;
      case TeqSnackBarType.error:
        bgColor = TeqColors.error;
        icon = Icons.error_outline;
        break;
      case TeqSnackBarType.warning:
        bgColor = TeqColors.warning;
        icon = Icons.warning_amber_outlined;
        break;
      case TeqSnackBarType.info:
        bgColor = TeqColors.info;
        icon = Icons.info_outline;
        break;
    }

    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      duration: duration,
      content: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: TeqSpacing.m,
          vertical: TeqSpacing.s,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: TeqSpacing.s),
            Expanded(
              child: Text(
                message,
                style: TeqTypography.bodyMedium.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
