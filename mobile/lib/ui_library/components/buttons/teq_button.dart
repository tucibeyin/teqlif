import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';

enum TeqButtonType { primary, secondary, outline, text }

enum TeqButtonSize { small, medium, large }

/// Teqlif Design System - Button
/// Proje içerisindeki tüm Elevated, Text, Outline butonlarının merkezi.
class TeqButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final TeqButtonType type;
  final TeqButtonSize size;
  final bool isLoading;
  final bool isDisabled;
  final IconData? icon;
  final Color? customColor;
  final bool isExpanded;

  const TeqButton({
    Key? key,
    required this.text,
    required this.onPressed,
    this.type = TeqButtonType.primary,
    this.size = TeqButtonSize.medium,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.customColor,
    this.isExpanded = true,
  }) : super(key: key);

  /// Sadece Outline buton dönen constructor
  const TeqButton.outline({
    Key? key,
    required this.text,
    required this.onPressed,
    this.size = TeqButtonSize.medium,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.customColor,
    this.isExpanded = true,
  }) : type = TeqButtonType.outline,
       super(key: key);

  /// Sadece Text buton dönen constructor
  const TeqButton.text({
    Key? key,
    required this.text,
    required this.onPressed,
    this.size = TeqButtonSize.medium,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.customColor,
    this.isExpanded = true,
  }) : type = TeqButtonType.text,
       super(key: key);

  double get _buttonHeight {
    switch (size) {
      case TeqButtonSize.small:
        return 36.0;
      case TeqButtonSize.medium:
        return 48.0;
      case TeqButtonSize.large:
        return 56.0;
    }
  }

  TextStyle get _textStyle {
    switch (size) {
      case TeqButtonSize.small:
        return TeqTypography.labelSmall;
      case TeqButtonSize.medium:
        return TeqTypography.labelMedium;
      case TeqButtonSize.large:
        return TeqTypography.labelLarge;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool active = !isDisabled && !isLoading && onPressed != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget child = Text(text, style: _textStyle);

    if (isLoading) {
      child = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            type == TeqButtonType.primary ? Colors.white : TeqColors.primary,
          ),
        ),
      );
    } else if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: TeqSpacing.xs),
          child,
        ],
      );
    }

    switch (type) {
      case TeqButtonType.primary:
      case TeqButtonType.secondary:
        Color bgColor = type == TeqButtonType.primary
            ? (customColor ?? TeqColors.primary)
            : (isDark ? TeqColors.surfaceDark : TeqColors.backgroundLight);

        Color fgColor = type == TeqButtonType.primary
            ? Colors.white
            : (isDark ? Colors.white : TeqColors.textPrimaryLight);

        return SizedBox(
          height: _buttonHeight,
          width: isExpanded ? double.infinity : null,
          child: ElevatedButton(
            onPressed: active ? onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: fgColor,
              disabledBackgroundColor: isDark
                  ? TeqColors.borderDark
                  : TeqColors.borderLight,
              disabledForegroundColor: isDark
                  ? TeqColors.textHintDark
                  : TeqColors.textHintLight,
              minimumSize: Size.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
              ),
            ),
            child: child,
          ),
        );

      case TeqButtonType.outline:
        Color color =
            customColor ?? (isDark ? Colors.white : TeqColors.textPrimaryLight);
        return SizedBox(
          height: _buttonHeight,
          width: isExpanded ? double.infinity : null,
          child: OutlinedButton(
            onPressed: active ? onPressed : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              disabledForegroundColor: isDark
                  ? TeqColors.textHintDark
                  : TeqColors.textHintLight,
              minimumSize: Size.zero,
              side: BorderSide(
                color: active
                    ? color.withValues(alpha: 0.5)
                    : (isDark ? TeqColors.borderDark : TeqColors.borderLight),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
              ),
            ),
            child: child,
          ),
        );

      case TeqButtonType.text:
        Color color = customColor ?? TeqColors.primary;
        return SizedBox(
          height: _buttonHeight,
          width: isExpanded ? double.infinity : null,
          child: TextButton(
            onPressed: active ? onPressed : null,
            style: TextButton.styleFrom(
              foregroundColor: color,
              disabledForegroundColor: isDark
                  ? TeqColors.textHintDark
                  : TeqColors.textHintLight,
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
              ),
            ),
            child: child,
          ),
        );
    }
  }
}
