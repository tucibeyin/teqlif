import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';

/// Teqlif Design System - TextField
/// Tüm uygulamada kullanılan ortak TextFormField yapısı.
class TeqTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType keyboardType;
  final int? maxLines;
  final int? minLines;
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;
  final bool readOnly;
  final VoidCallback? onTap;
  final int? maxLength;
  final String? helperText;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final String? prefixText;
  final bool floatingLabel;

  const TeqTextField({
    Key? key,
    this.controller,
    this.labelText,
    this.hintText,
    this.errorText,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.validator,
    this.readOnly = false,
    this.onTap,
    this.maxLength,
    this.helperText,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.inputFormatters,
    this.textInputAction,
    this.prefixText,
    this.floatingLabel = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color bgColor = isDark ? TeqColors.surfaceDark : Colors.white;
    final Color borderColor = isDark
        ? TeqColors.borderDark
        : TeqColors.borderLight;
    final Color hintColor = isDark
        ? TeqColors.textHintDark
        : TeqColors.textHintLight;
    final Color textColor = isDark
        ? TeqColors.textPrimaryDark
        : TeqColors.textPrimaryLight;

    final decoration = InputDecoration(
      labelText: floatingLabel ? labelText : null,
      hintText: hintText,
      hintStyle: TeqTypography.bodyLarge.copyWith(color: hintColor),
      errorText: errorText,
      helperText: helperText,
      helperStyle: TeqTypography.bodySmall.copyWith(color: hintColor),
      errorStyle: TeqTypography.bodySmall.copyWith(color: TeqColors.error),
      filled: true,
      fillColor: bgColor,
      prefixIcon: prefixIcon,
      prefixText: prefixText,
      prefixStyle: TextStyle(color: textColor, fontSize: 16),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TeqSpacing.m,
        vertical: TeqSpacing.m,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
        borderSide: const BorderSide(color: TeqColors.error, width: 1.5),
      ),
    );

    final field = TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      scrollPadding: const EdgeInsets.only(bottom: 80),
      onChanged: onChanged,
      validator: validator,
      readOnly: readOnly,
      onTap: onTap,
      style: TeqTypography.bodyLarge.copyWith(color: textColor),
      decoration: decoration,
    );

    if (floatingLabel || labelText == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          labelText!,
          style: TeqTypography.labelMedium.copyWith(
            color: isDark
                ? TeqColors.textSecondaryDark
                : TeqColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: TeqSpacing.xs),
        field,
      ],
    );
  }
}
