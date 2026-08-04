import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../ui_library/components/buttons/teq_button.dart';
import 'viewmodels/notification_settings_view_model.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  final bool isPremium;
  const NotificationSettingsScreen({super.key, this.isPremium = false});

  Map<String, (String, String, IconData)> _buildLabels(TranslationPack loc) => {
    'messages': (
      loc.t("notifSettingsMessagesTitle"),
      loc.t("notifSettingsMessagesDesc"),
      Icons.chat_bubble_outline,
    ),
    'follows': (
      loc.t("notifSettingsFollowsTitle"),
      loc.t("notifSettingsFollowsDesc"),
      Icons.person_add_outlined,
    ),
    'auction_won': (
      loc.t("notifSettingsAuctionWonTitle"),
      loc.t("notifSettingsAuctionWonDesc"),
      Icons.emoji_events_outlined,
    ),
    'stream_started': (
      loc.t("notifSettingsStreamStartedTitle"),
      loc.t("notifSettingsStreamStartedDesc"),
      Icons.live_tv_outlined,
    ),
    'new_listing': (
      loc.t("notifSettingsNewListingTitle"),
      loc.t("notifSettingsNewListingDesc"),
      Icons.storefront_outlined,
    ),
    'new_bid': (
      loc.t("notifSettingsNewBidTitle"),
      loc.t("notifSettingsNewBidDesc"),
      Icons.gavel_outlined,
    ),
    'outbid': (
      loc.t("notifSettingsOutbidTitle"),
      loc.t("notifSettingsOutbidDesc"),
      Icons.trending_up_outlined,
    ),
    'ratings': (
      loc.t("notifSettingsRatingsTitle"),
      loc.t("notifSettingsRatingsDesc"),
      Icons.star_outline,
    ),
  };

  void _showUpgradeSheet(BuildContext context, TranslationPack loc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              loc.t("notifProUpgradeTitle"),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              loc.t("notifProUpgradeDesc"),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 24),
            TeqButton(
              text: loc.t("btnGoPro"),
              onPressed: () => Navigator.pop(context),
              isExpanded: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, NotificationSettingsState state, {required bool isFrom}) async {
    final initial = isFrom ? state.quietFrom : state.quietTo;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(notificationSettingsProvider.notifier).setQuietTime(isFrom: isFrom, time: picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final labels = _buildLabels(loc);
    final stateAsync = ref.watch(notificationSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.navBar(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        title: Text(
          loc.t("notifSettingsTitle"),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
      ),
      body: stateAsync.when(
        data: (state) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ── Temel bildirimler ──────────────────────────────────
              ...state.prefs.keys.map((key) {
                final info = labels[key]!;
                return _NotifTile(
                  key: Key('notif_tile_$key'),
                  icon: info.$3,
                  label: info.$1,
                  subtitle: info.$2,
                  value: state.prefs[key]!,
                  onChanged: (v) => ref.read(notificationSettingsProvider.notifier).togglePref(key, v),
                );
              }),
              const SizedBox(height: 12),
              // ── Pro Bildirim Ayarları ─────────────────────────────
              _ProSection(
                isPremium: isPremium,
                bidThreshold: state.bidThreshold,
                quietEnabled: state.quietEnabled,
                quietFrom: state.quietFrom,
                quietTo: state.quietTo,
                receiveBlastNotifications: state.receiveBlastNotifications,
                onBidThreshold: isPremium ? (v) => ref.read(notificationSettingsProvider.notifier).setBidThreshold(v) : null,
                onQuietEnabled: isPremium ? (v) => ref.read(notificationSettingsProvider.notifier).setQuietEnabled(v) : null,
                onPickFrom: isPremium ? () => _pickTime(context, ref, state, isFrom: true) : null,
                onPickTo: isPremium ? () => _pickTime(context, ref, state, isFrom: false) : null,
                onBlastNotifChanged: isPremium ? (v) => ref.read(notificationSettingsProvider.notifier).setBlastNotifications(v) : null,
                onUpgradeTap: () => _showUpgradeSheet(context, loc),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loc.t('errorGenericRetry'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                // In a real app we'd trigger a reload here.
                onPressed: () {},
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pro bölümü widget'ı ───────────────────────────────────────────────────────

class _ProSection extends ConsumerWidget {
  final bool isPremium;
  final int bidThreshold;
  final bool quietEnabled;
  final TimeOfDay quietFrom;
  final TimeOfDay quietTo;
  final bool receiveBlastNotifications;
  final ValueChanged<int>? onBidThreshold;
  final ValueChanged<bool>? onQuietEnabled;
  final VoidCallback? onPickFrom;
  final VoidCallback? onPickTo;
  final ValueChanged<bool>? onBlastNotifChanged;
  final VoidCallback onUpgradeTap;

  static const _thresholds = [0, 100, 250, 500, 1000, 2500];

  const _ProSection({
    required this.isPremium,
    required this.bidThreshold,
    required this.quietEnabled,
    required this.quietFrom,
    required this.quietTo,
    required this.receiveBlastNotifications,
    required this.onBidThreshold,
    required this.onQuietEnabled,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onBlastNotifChanged,
    required this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bölüm başlığı
          Row(
            children: [
              Text(
                loc.t("lblProNotificationSettings"),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '👑 PRO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Teklif eşiği kartı
          GestureDetector(
            onTap: isPremium ? null : onUpgradeTap,
            child: _proCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune_outlined,
                        size: 20,
                        color: isPremium
                            ? kPrimary
                            : AppColors.iconColor(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.t("notifBidThresholdTitle"),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            Text(
                              loc.t("notifBidThresholdDesc"),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isPremium)
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: AppColors.textTertiary(context),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _thresholds.map((v) {
                      final isSelected = bidThreshold == v;
                      return GestureDetector(
                        onTap: isPremium
                            ? () => onBidThreshold?.call(v)
                            : onUpgradeTap,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? kPrimary
                                : AppColors.bg(context),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? kPrimary
                                  : AppColors.border(context),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Text(
                            v == 0
                                ? loc.t("lblStatusOff")
                                : '₺$v',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : (isPremium
                                        ? AppColors.textPrimary(context)
                                        : AppColors.textTertiary(context)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Toplu kitle bildirimi toggle kartı
          GestureDetector(
            onTap: isPremium ? null : onUpgradeTap,
            child: _proCard(
              context,
              child: Row(
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    size: 20,
                    color: isPremium
                        ? (receiveBlastNotifications
                              ? kPrimary
                              : AppColors.iconColor(context))
                        : AppColors.iconColor(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.t("notifSettingsBlastTitle"),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        Text(
                          loc.t("notifSettingsBlastDesc"),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isPremium)
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: AppColors.textTertiary(context),
                    )
                  else
                    Switch(
                      value: receiveBlastNotifications,
                      activeThumbColor: kPrimary,
                      onChanged: onBlastNotifChanged,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Sessiz saatler kartı
          GestureDetector(
            onTap: isPremium ? null : onUpgradeTap,
            child: _proCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bedtime_outlined,
                        size: 20,
                        color: isPremium && quietEnabled
                            ? kPrimary
                            : AppColors.iconColor(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.t("notifQuietHoursTitle"),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            Text(
                              loc.t("notifQuietHoursDesc"),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isPremium)
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: AppColors.textTertiary(context),
                        )
                      else
                        Switch(
                          value: quietEnabled,
                          activeThumbColor: kPrimary,
                          onChanged: onQuietEnabled,
                        ),
                    ],
                  ),
                  if (isPremium && quietEnabled) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _TimePicker(
                            label: loc.t("notificationStart"),
                            time: quietFrom,
                            onTap: onPickFrom,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimePicker(
                            label: loc.t("notificationEnd"),
                            time: quietTo,
                            onTap: onPickTo,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _proCard(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: child,
    );
  }
}

class _TimePicker extends ConsumerWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback? onTap;

  const _TimePicker({
    required this.label,
    required this.time,
    required this.onTap,
  });

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  _fmt(time),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: AppColors.textTertiary(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Temel bildirim tile ────────────────────────────────────────────────────────

class _NotifTile extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          icon,
          color: value ? kPrimary : AppColors.iconColor(context),
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
        trailing: Switch(
          value: value,
          activeThumbColor: kPrimary,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
