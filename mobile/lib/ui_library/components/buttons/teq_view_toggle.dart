import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';

/// Izgara / Liste görünüm geçiş çifti.
///
/// Kullanım:
/// ```dart
/// TeqViewToggle(
///   isListView: _isListView,
///   onChanged: (v) => setState(() => _isListView = v),
///   gridTooltip: loc.t("tooltipGridView"),
///   listTooltip: loc.t("tooltipListView"),
/// )
/// ```
class TeqViewToggle extends StatelessWidget {
  final bool isListView;
  final ValueChanged<bool> onChanged;
  final String gridTooltip;
  final String listTooltip;

  const TeqViewToggle({
    super.key,
    required this.isListView,
    required this.onChanged,
    required this.gridTooltip,
    required this.listTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark
        ? TeqColors.primary.withValues(alpha: 0.18)
        : TeqColors.primaryBg;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleBtn(
          icon: Icons.grid_view_rounded,
          tooltip: gridTooltip,
          active: !isListView,
          activeBg: activeBg,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: TeqSpacing.xxs),
        _ToggleBtn(
          icon: Icons.format_list_bulleted_rounded,
          tooltip: listTooltip,
          active: isListView,
          activeBg: activeBg,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final Color activeBg;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.activeBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(TeqSpacing.xxs),
          decoration: BoxDecoration(
            color: active ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(TeqSpacing.radiusS),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? TeqColors.primary : const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }
}
