import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';

/// Teqlif Design System - Card
/// Proje içerisindeki tüm kart yapıları için standart konteyner.
class TeqCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final VoidCallback? onTap;
  final Color? color;
  final bool hasBorder;

  const TeqCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(TeqSpacing.m),
    this.margin,
    this.elevation = 0,
    this.onTap,
    this.color,
    this.hasBorder = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor =
        color ?? (isDark ? TeqColors.surfaceDark : TeqColors.surfaceLight);
    final borderColor = isDark ? TeqColors.borderDark : TeqColors.borderLight;

    Widget cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(TeqSpacing.radiusL),
        border: hasBorder ? Border.all(color: borderColor) : null,
        boxShadow: elevation! > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05 * elevation!),
                  blurRadius: elevation! * 2,
                  offset: Offset(0, elevation!),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return Padding(
        padding: margin ?? EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(TeqSpacing.radiusL),
            child: cardContent,
          ),
        ),
      );
    }

    return Padding(padding: margin ?? EdgeInsets.zero, child: cardContent);
  }
}
