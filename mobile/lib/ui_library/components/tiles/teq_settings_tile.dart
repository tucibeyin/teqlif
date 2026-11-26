import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';

/// Ayarlar menüsü için section wrapper.
/// Material(color) kullanır — ListTile'ın InkWell splash'i görünür olur.
class TeqSettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const TeqSettingsSection({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary(context),
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...items,
        ],
      ),
    );
  }
}

/// Tek satır ayar item'ı: icon + label + opsiyonel trailing widget.
/// Light mode %8, dark mode %12 opacity press rengi — Material Design spec.
class TeqSettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? iconColor;

  const TeqSettingsTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final pressColor = AppColors.textPrimary(context)
        .withValues(alpha: AppColors.isDark(context) ? 0.12 : 0.08);
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: pressColor,
        highlightColor: pressColor,
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? AppColors.iconColor(context)),
        title: Text(
          label,
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
        ),
        trailing: trailing ??
            Icon(Icons.chevron_right, color: AppColors.border(context), size: 20),
        onTap: onTap,
      ),
    );
  }
}
