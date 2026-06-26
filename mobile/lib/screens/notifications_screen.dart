import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/notification_service.dart';
import '../services/stream_service.dart';
import 'live/swipe_live_screen.dart';
import 'listing_detail_screen.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;
  bool _markingRead = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await NotificationService.getNotifications();
      if (mounted) {
        setState(() {
          _notifs = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingRead) return;
    setState(() => _markingRead = true);
    await NotificationService.markAllRead();
    if (mounted) {
      setState(() {
        for (final n in _notifs) {
          n['is_read'] = true;
        }
        _markingRead = false;
      });
    }
  }

  void _onTap(Map<String, dynamic> notif) {
    setState(() => notif['is_read'] = true);
    _navigate(notif);
  }

  void _navigate(Map<String, dynamic> notif) {
    final type = notif['type'] as String? ?? '';
    final relatedId = notif['related_id'] as int?;
    final body = notif['body'] as String?;
    final title = notif['title'] as String? ?? '';

    switch (type) {
      case 'follow':
        // body = sender username (set in backend); fallback: parse from title
        final username = (body != null && body.isNotEmpty && !body.contains(' '))
            ? body
            : _extractHandle(title);
        if (username.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PublicProfileScreen(username: username),
          ));
        }
      case 'new_bid':
      case 'outbid':
      case 'smart_auction_alert':
        if (relatedId != null && !StreamService.isHosting) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => SwipeLiveScreen.single(streamId: relatedId),
          ));
        }
      case 'auction_won':
        if (relatedId != null) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ListingDeepLinkLoader(listingId: relatedId),
          ));
        }
      case 'message':
        if (relatedId != null) {
          final username = _extractHandle(title);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => DirectChatScreen(
              otherUserId: relatedId,
              displayName: username.isNotEmpty ? username : 'Kullanıcı',
              otherHandle: username,
            ),
          ));
        }
      // listing_deactivated, listing_deleted: bilgi amaçlı, navigasyon yok
    }
  }

  // "@john seni..." → "john"
  String _extractHandle(String text) {
    final match = RegExp(r'@(\w+)').firstMatch(text);
    return match?.group(1) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.notificationsTitle),
        actions: [
          TextButton(
            key: const Key('notifications_btn_tumunu_oku'),
            onPressed: _markAllRead,
            child: Text(
              l.notificationsMarkAllRead,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              onRefresh: _load,
              color: kPrimary,
              child: _notifs.isEmpty
                  ? _emptyState(l)
                  : ListView.separated(
                      itemCount: _notifs.length,
                      separatorBuilder: (context, i) =>
                          const Divider(height: 1, indent: 72, endIndent: 0),
                      itemBuilder: (_, i) => _NotifTile(
                        notif: _notifs[i],
                        onTap: () => _onTap(_notifs[i]),
                      ),
                    ),
            ),
    );
  }

  Widget _emptyState(AppLocalizations l) {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.notifications_none_outlined,
                  size: 64, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 16),
              Text(
                l.notifNone,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                l.notifNoneDesc,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Bildirim satırı ──────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;

  const _NotifTile({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = notif['type'] as String? ?? '';
    final title = notif['title'] as String? ?? '';
    final body = notif['body'] as String?;
    final isRead = notif['is_read'] as bool? ?? true;
    final createdAt = notif['created_at'] as String?;

    // follow: body = username, görüntüleme için kullanılmaz
    final displayBody = type == 'follow' ? null : body;

    final (icon, color) = _iconAndColor(type);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isRead ? null : kPrimary.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // İkon çemberi
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            // Metin alanı
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isRead ? FontWeight.w400 : FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (displayBody != null && displayBody.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      displayBody,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF64748B)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _relativeTime(createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ],
              ),
            ),
            // Okunmamış nokta
            if (!isRead)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 8),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: kPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _iconAndColor(String type) {
    return switch (type) {
      'follow'              => (Icons.person_add_rounded,        const Color(0xFF6366F1)),
      'new_bid'             => (Icons.gavel_rounded,             const Color(0xFFF97316)),
      'outbid'              => (Icons.arrow_circle_up_rounded,   const Color(0xFFEF4444)),
      'auction_won'         => (Icons.shopping_bag_rounded,      const Color(0xFF16A34A)),
      'message'             => (Icons.chat_bubble_rounded,       const Color(0xFF0EA5E9)),
      'smart_auction_alert' => (Icons.bolt_rounded,              const Color(0xFF8B5CF6)),
      'listing_deactivated' => (Icons.pause_circle_rounded,      const Color(0xFF64748B)),
      'listing_deleted'     => (Icons.delete_outline_rounded,    const Color(0xFF94A3B8)),
      _                     => (Icons.notifications_rounded,     kPrimary),
    };
  }

  String _relativeTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Az önce';
      if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
      if (diff.inHours < 24) return '${diff.inHours} sa önce';
      if (diff.inDays < 7) return '${diff.inDays} gün önce';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} hafta önce';
      return '${(diff.inDays / 30).floor()} ay önce';
    } catch (_) {
      return '';
    }
  }
}
