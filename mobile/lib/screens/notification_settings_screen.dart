import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../services/storage_service.dart';
import '../l10n/app_localizations.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final bool isPremium;
  const NotificationSettingsScreen({super.key, this.isPremium = false});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _loading = true;
  String? _error;

  final Map<String, bool> _prefs = {
    'messages': true,
    'follows': true,
    'auction_won': true,
    'stream_started': true,
    'new_listing': true,
    'new_bid': true,
    'outbid': true,
  };

  // Pro ayarları
  int _bidThreshold = 0;
  bool _quietEnabled = false;
  TimeOfDay _quietFrom = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietTo = const TimeOfDay(hour: 8, minute: 0);

  Map<String, (String, String, IconData)> _buildLabels(AppLocalizations l) => {
    'messages': (l.notifSettingsMessagesTitle, l.notifSettingsMessagesDesc, Icons.chat_bubble_outline),
    'follows': (l.notifSettingsFollowsTitle, l.notifSettingsFollowsDesc, Icons.person_add_outlined),
    'auction_won': (l.notifSettingsAuctionWonTitle, l.notifSettingsAuctionWonDesc, Icons.emoji_events_outlined),
    'stream_started': (l.notifSettingsStreamStartedTitle, l.notifSettingsStreamStartedDesc, Icons.live_tv_outlined),
    'new_listing': (l.notifSettingsNewListingTitle, l.notifSettingsNewListingDesc, Icons.storefront_outlined),
    'new_bid': (l.notifSettingsNewBidTitle, l.notifSettingsNewBidDesc, Icons.gavel_outlined),
    'outbid': (l.notifSettingsOutbidTitle, l.notifSettingsOutbidDesc, Icons.trending_up_outlined),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await StorageService.getToken();
    if (token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/auth/notification-prefs'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            for (final k in _prefs.keys) {
              _prefs[k] = data[k] as bool? ?? true;
            }
            _bidThreshold = (data['bid_threshold_tl'] as int?) ?? 0;
            _quietEnabled = (data['quiet_hours_enabled'] as bool?) ?? false;
            _quietFrom = _parseTime(data['quiet_from'] as String? ?? '22:00');
            _quietTo = _parseTime(data['quiet_to'] as String? ?? '08:00');
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay _parseTime(String hhmm) {
    try {
      final parts = hhmm.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> _buildPayload() => {
    ..._prefs,
    'bid_threshold_tl': _bidThreshold,
    'quiet_hours_enabled': _quietEnabled,
    'quiet_from': _formatTime(_quietFrom),
    'quiet_to': _formatTime(_quietTo),
  };

  Future<void> _patch(Map<String, dynamic> payload) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.patch(
        Uri.parse('$kBaseUrl/auth/notification-prefs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _prefs[key] = value);
    final payload = _buildPayload();
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.patch(
        Uri.parse('$kBaseUrl/auth/notification-prefs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
    } catch (_) {
      if (mounted) setState(() => _prefs[key] = !value);
    }
  }

  Future<void> _setBidThreshold(int value) async {
    setState(() => _bidThreshold = value);
    await _patch(_buildPayload());
  }

  Future<void> _setQuietEnabled(bool value) async {
    setState(() => _quietEnabled = value);
    await _patch(_buildPayload());
  }

  Future<void> _pickTime({required bool isFrom}) async {
    final initial = isFrom ? _quietFrom : _quietTo;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _quietFrom = picked;
      } else {
        _quietTo = picked;
      }
    });
    await _patch(_buildPayload());
  }

  void _showUpgradeSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
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
            const Text(
              '👑 Pro Bildirim Ayarları',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Teklif eşiği ve sessiz saat ayarları Pro kullanıcılara özel.\nPro\'ya geçerek gereksiz bildirimlerden kurtulun.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Pro\'ya Geç',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = _buildLabels(l);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.navBar(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        title: Text(
          l.notifSettingsTitle,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // ── Temel bildirimler ──────────────────────────────────
                    ..._prefs.keys.map((key) {
                      final info = labels[key]!;
                      return _NotifTile(
                        key: Key('notif_tile_$key'),
                        icon: info.$3,
                        label: info.$1,
                        subtitle: info.$2,
                        value: _prefs[key]!,
                        onChanged: (v) => _toggle(key, v),
                      );
                    }),
                    const SizedBox(height: 12),
                    // ── Pro Bildirim Ayarları ─────────────────────────────
                    _ProSection(
                      isPremium: widget.isPremium,
                      bidThreshold: _bidThreshold,
                      quietEnabled: _quietEnabled,
                      quietFrom: _quietFrom,
                      quietTo: _quietTo,
                      onBidThreshold: widget.isPremium ? _setBidThreshold : null,
                      onQuietEnabled: widget.isPremium ? _setQuietEnabled : null,
                      onPickFrom: widget.isPremium ? () => _pickTime(isFrom: true) : null,
                      onPickTo: widget.isPremium ? () => _pickTime(isFrom: false) : null,
                      onUpgradeTap: _showUpgradeSheet,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}

// ── Pro bölümü widget'ı ───────────────────────────────────────────────────────

class _ProSection extends StatelessWidget {
  final bool isPremium;
  final int bidThreshold;
  final bool quietEnabled;
  final TimeOfDay quietFrom;
  final TimeOfDay quietTo;
  final ValueChanged<int>? onBidThreshold;
  final ValueChanged<bool>? onQuietEnabled;
  final VoidCallback? onPickFrom;
  final VoidCallback? onPickTo;
  final VoidCallback onUpgradeTap;

  static const _thresholds = [0, 100, 250, 500, 1000, 2500];

  const _ProSection({
    required this.isPremium,
    required this.bidThreshold,
    required this.quietEnabled,
    required this.quietFrom,
    required this.quietTo,
    required this.onBidThreshold,
    required this.onQuietEnabled,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bölüm başlığı
          Row(
            children: [
              Text(
                'Pro Bildirim Ayarları',
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
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
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
                        color: isPremium ? kPrimary : AppColors.iconColor(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Teklif Eşiği',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            Text(
                              'Sadece belirli tutarın üzerindeki teklifleri bildir',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isPremium)
                        Icon(Icons.lock_outline, size: 16, color: AppColors.textTertiary(context)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _thresholds.map((v) {
                      final isSelected = bidThreshold == v;
                      return GestureDetector(
                        onTap: isPremium ? () => onBidThreshold?.call(v) : onUpgradeTap,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? kPrimary : AppColors.bg(context),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? kPrimary : AppColors.border(context),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Text(
                            v == 0 ? 'Kapalı' : '₺$v',
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
                        color: isPremium && quietEnabled ? kPrimary : AppColors.iconColor(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sessiz Saatler',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            Text(
                              'Bu saatler arası bildirimleri ertele, sabah göster',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isPremium)
                        Icon(Icons.lock_outline, size: 16, color: AppColors.textTertiary(context))
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
                            label: 'Başlangıç',
                            time: quietFrom,
                            onTap: onPickFrom,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimePicker(
                            label: 'Bitiş',
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

class _TimePicker extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                Icon(Icons.edit_outlined, size: 14, color: AppColors.textTertiary(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Temel bildirim tile ────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Icon(icon, color: value ? kPrimary : AppColors.iconColor(context), size: 22),
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
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
        ),
        value: value,
        activeThumbColor: kPrimary,
        onChanged: onChanged,
      ),
    );
  }
}
