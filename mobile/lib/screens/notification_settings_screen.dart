import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../services/storage_service.dart';
import '../l10n/app_localizations.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _loading = true;
  String? _error;

  Map<String, bool> _prefs = {
    'messages': true,
    'follows': true,
    'auction_won': true,
    'stream_started': true,
    'new_listing': true,
    'new_bid': true,
    'outbid': true,
  };

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

  Future<void> _toggle(String key, bool value) async {
    setState(() => _prefs[key] = value);
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.patch(
        Uri.parse('$kBaseUrl/auth/notification-prefs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(_prefs),
      );
    } catch (_) {
      // Hata durumunda önceki değere geri dön
      if (mounted) setState(() => _prefs[key] = !value);
    }
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
                  children: _prefs.keys.map((key) {
                    final info = labels[key]!;
                    return _NotifTile(
                      key: Key('notif_tile_$key'),
                      icon: info.$3,
                      label: info.$1,
                      subtitle: info.$2,
                      value: _prefs[key]!,
                      onChanged: (v) => _toggle(key, v),
                    );
                  }).toList(),
                ),
    );
  }
}

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
        activeColor: kPrimary,
        onChanged: onChanged,
      ),
    );
  }
}
