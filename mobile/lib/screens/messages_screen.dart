import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../utils/price_formatter.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../services/offline_queue_service.dart';
import '../services/storage_service.dart';
import '../services/push_notification_service.dart';
import '../services/ws_service.dart';
import 'public_profile_screen.dart';
import 'listing_detail_screen.dart';
import 'purchase_detail_screen.dart';
import 'sale_detail_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'live/swipe_live_screen.dart';
import '../services/stream_service.dart';
import '../services/pip_service.dart';
import '../providers/pip_provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/network_error_widget.dart';
import '../widgets/stale_data_banner.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/call_service.dart';
import 'call_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => MessagesScreenState();
}

class MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _unreadNotifs = 0;
  StreamSubscription<void>? _badgeSub;
  StreamSubscription<Map<String, dynamic>>? _fcmSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadUnreadNotifs();
    // badgeRefreshNeeded: mesaj okunduğunda (chat kapandığında)
    _badgeSub = PushNotificationService.badgeRefreshNeeded.stream.listen(
      (_) => _loadUnreadNotifs(),
    );
    // notificationStream: yeni FCM bildirimi gelince (follow, bid, vb.) noktayı güncelle
    _fcmSub = PushNotificationService.notificationStream.stream.listen(
      (_) => _loadUnreadNotifs(),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _badgeSub?.cancel();
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadNotifs() async {
    final count = await NotificationService.getUnreadNotifCount();
    if (mounted) setState(() => _unreadNotifs = count);
  }

  void switchToNotificationsTab() {
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  void refresh({bool bypassCache = false}) {
    PushNotificationService.notificationStream.add({});
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && _tabController.index == 1) {
      NotificationService.markAllRead().then((_) {
        if (mounted) setState(() => _unreadNotifs = 0);
        PushNotificationService.badgeRefreshNeeded.add(null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.msgTabMessages),
        bottom: TabBar(
          controller: _tabController,
          labelColor: kPrimary,
          unselectedLabelColor: const Color(0xFF9CA3AF),
          indicatorColor: kPrimary,
          tabs: [
            Tab(text: l.msgTabMessages),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.msgTabNotifications),
                  if (_unreadNotifs > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_MessagesTab(), _NotificationsTab()],
      ),
    );
  }
}

// ── Mesajlar Tab ──────────────────────────────────────────────────────────────

class _MessagesTab extends StatefulWidget {
  const _MessagesTab();

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  List<dynamic> _conversations = [];
  bool _loading = true;
  bool _loadInProgress = false;
  bool _hasError = false;
  int? _myUserId;
  StreamSubscription<Map<String, dynamic>>? _fcmSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
    _load();
    _fcmSub = PushNotificationService.notificationStream.stream.listen(
      (_) => _load(silent: true),
    );
    _wsSub = WsService.messageStream.stream.listen((data) {
      if (data['type'] == 'message') {
        _updateConversationInMemory(data);
        PushNotificationService.badgeRefreshNeeded.add(null);
      }
    });
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMyUserId() async {
    final info = await StorageService.getUserInfo();
    if (mounted) setState(() => _myUserId = info?['id'] as int?);
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    // ── A: Kasa kontrolü ───────────────────────────────────────────────────
    final cached = await StorageService.getCachedData(
      StorageService.cacheMessages,
    );
    if (cached != null && mounted) {
      setState(() {
        _conversations = cached as List;
        _loading = false;
      });
    } else if (!silent) {
      if (mounted) setState(() => _loading = true);
    }

    // ── B: Arka planda API ─────────────────────────────────────────────────
    try {
      final data = await NotificationService.getConversations();
      await StorageService.cacheData(StorageService.cacheMessages, data);
      if (mounted)
        setState(() {
          _conversations = data;
          _loading = false;
          _hasError = false;
        });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          if (cached == null) _loading = false;
        });
      }
      debugPrint('[MessagesTab] API hatası: $e');
    } finally {
      _loadInProgress = false;
    }
  }

  /// WS üzerinden gelen mesajı HTTP isteği atmadan anında listeye yansıtır.
  /// Bilinmeyen gönderici (yeni konuşma) varsa API'ya fallback yapar.
  String _lastMsgPreview(Map<String, dynamic> data, AppLocalizations l) {
    final ct = data['content_type'] as String? ?? 'text';
    if (ct != 'text') {
      return switch (ct) {
        'image' => l.msgLastPhoto,
        'video' => l.msgLastVideo,
        'voice' => l.msgLastVoice,
        'file' => l.msgLastFile,
        _ => l.msgLastFile,
      };
    }
    return (data['content'] as String?) ?? '';
  }

  void _updateConversationInMemory(Map<String, dynamic> data) {
    final senderId = data['sender_id'] as int?;
    final receiverId = data['receiver_id'] as int?;
    final createdAt = data['created_at'] as String?;
    final otherId = senderId == _myUserId ? receiverId : senderId;
    final l = AppLocalizations.of(context)!;

    if (otherId == null || _myUserId == null) {
      _load(silent: true);
      return;
    }

    final idx = _conversations.indexWhere(
      (c) => (c['user_id'] as int?) == otherId,
    );
    if (idx < 0) {
      // Yeni konuşma — tam bilgi için API'ya git
      _load(silent: true);
      return;
    }

    final updated = List<dynamic>.from(_conversations);
    final conv = Map<String, dynamic>.from(updated[idx] as Map);
    conv['last_message'] = _lastMsgPreview(data, l);
    conv['last_at'] = createdAt;
    if (senderId != _myUserId) {
      conv['unread_count'] = ((conv['unread_count'] as int?) ?? 0) + 1;
    }
    updated
      ..removeAt(idx)
      ..insert(0, conv);
    if (mounted) setState(() => _conversations = updated);
  }

  Future<void> _deleteConversation(int otherId) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l.msgDeleteConversationConfirm,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                l.msgDeleteConversation,
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l.btnCancel),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await NotificationService.deleteConversation(otherId);
    if (!mounted) return;
    if (ok) {
      setState(
        () => _conversations.removeWhere(
          (c) => (c['user_id'] as int?) == otherId,
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.msgDeleteConversationSuccess)));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.msgDeleteConversationFailed)));
    }
  }

  String _timeAgo(String? isoStr) {
    if (isoStr == null) return '';
    try {
      final l = AppLocalizations.of(context)!;
      final dt = DateTime.parse(isoStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return l.timeNow;
      if (diff.inMinutes < 60) return l.timeMinAgo(diff.inMinutes);
      if (diff.inHours < 24) return l.timeHoursAgo(diff.inHours);
      return l.timeDaysAgo(diff.inDays);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    if (_hasError && _conversations.isEmpty) {
      return NetworkErrorWidget(scrollable: true, onRetry: _load);
    }
    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Color(0xFFD1D5DB),
            ),
            const SizedBox(height: 16),
            Text(
              l.msgNoMessages,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(l.msgNoMessagesDesc, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_hasError) _buildErrorBanner(),
        Expanded(
          child: RefreshIndicator(
            color: kPrimary,
            onRefresh: _load,
            child: ListView.separated(
              itemCount: _conversations.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final conv = _conversations[i];
                final username = conv['username'] as String? ?? '';
                final fullName = conv['full_name'] as String? ?? username;
                final l = AppLocalizations.of(context)!;
                final lastMsg = _lastMsgPreview({
                  'content_type': conv['last_message_type'] ?? 'text',
                  'content': conv['last_message'] ?? '',
                }, l);
                final lastAt = conv['last_at'] as String?;
                final unread = (conv['unread_count'] as int?) ?? 0;
                final otherId = (conv['user_id'] as int?) ?? 0;
                final initial = (fullName.isNotEmpty ? fullName[0] : '?')
                    .toUpperCase();

                final otherAvatarUrl =
                    conv['profile_image_thumb_url'] as String?;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kPrimary.withValues(alpha: 0.15),
                    backgroundImage:
                        otherAvatarUrl != null && otherAvatarUrl.isNotEmpty
                        ? CachedNetworkImageProvider(imgUrl(otherAvatarUrl))
                        : null,
                    child: otherAvatarUrl == null || otherAvatarUrl.isEmpty
                        ? Text(
                            initial,
                            style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fullName,
                          style: TextStyle(
                            fontWeight: unread > 0
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        _timeAgo(lastAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ), // color handled by theme
                      ),
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread > 0
                                ? const Color(0xFF374151)
                                : const Color(0xFF9CA3AF),
                            fontWeight: unread > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: const BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DirectChatScreen(
                          otherUserId: otherId,
                          displayName: fullName,
                          otherHandle: username,
                          otherAvatarUrl: otherAvatarUrl,
                        ),
                      ),
                    ).then((_) {
                      _load(silent: true);
                      PushNotificationService.badgeRefreshNeeded.add(null);
                    });
                  },
                  onLongPress: () => _deleteConversation(otherId),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Material(
      color: Colors.orange.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.messagesUpdateFailed,
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                AppLocalizations.of(context)!.btnRefresh,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bildirimler Tab ───────────────────────────────────────────────────────────

class _NotificationsTab extends StatefulWidget {
  const _NotificationsTab();

  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
  List<dynamic> _notifications = [];
  bool _loading = true;
  bool _notifHasError = false;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = PushNotificationService.notificationStream.stream.listen(
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    // ── A: Kasa kontrolü ───────────────────────────────────────────────────
    final cached = await StorageService.getCachedData(
      StorageService.cacheNotifications,
    );
    if (cached != null && mounted) {
      setState(() {
        _notifications = cached as List;
        _loading = false;
      });
    } else if (!silent) {
      if (mounted) setState(() => _loading = true);
    }

    // ── B: Arka planda API ─────────────────────────────────────────────────
    try {
      final data = await NotificationService.getNotifications();
      // ── C: Başarı → kasa güncelle, UI yenile ──────────────────────────
      await StorageService.cacheData(StorageService.cacheNotifications, data);
      if (mounted)
        setState(() {
          _notifications = data;
          _loading = false;
          _notifHasError = false;
        });
    } catch (e) {
      // ── D: Hata → kasa doluysa yut, boşsa boş ekran göster ───────────
      if (cached == null && mounted) {
        setState(() => _loading = false);
      }
      if (mounted) setState(() => _notifHasError = true);
      debugPrint('[NotificationsTab] API hatası (cache=${cached != null}): $e');
    }
  }

  String _timeAgo(String? isoStr) {
    if (isoStr == null) return '';
    try {
      final l = AppLocalizations.of(context)!;
      final dt = DateTime.parse(isoStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return l.timeNow;
      if (diff.inMinutes < 60) return l.timeMinAgo(diff.inMinutes);
      if (diff.inHours < 24) return l.timeHoursAgo(diff.inHours);
      return l.timeDaysAgo(diff.inDays);
    } catch (_) {
      return '';
    }
  }

  String _localizeTitle(String? type, String title, AppLocalizations l) {
    final username = RegExp(r'^@(\w+)').firstMatch(title)?.group(1) ?? '';
    return switch (type) {
      'message' => username.isNotEmpty ? l.notifMessage(username) : title,
      'follow' => username.isNotEmpty ? l.notifFollow(username) : title,
      'stream_started' =>
        username.isNotEmpty ? l.notifStreamStarted(username) : title,
      'new_bid' => username.isNotEmpty ? l.notifNewBid(username) : title,
      'new_listing' =>
        username.isNotEmpty ? l.notifNewListing(username) : title,
      'outbid' => l.notifOutbid,
      'smart_auction_alert' => l.notifSmartAuctionAlert,
      'budget_match' => l.notifBudgetMatch,
      'auction_won' => l.notifAuctionWon,
      'buy_it_now' => l.notifBuyItNow,
      'call_missed' =>
        username.isNotEmpty ? l.notifCallMissed(username) : title,
      'listing_deactivated' => l.notifListingDeactivated,
      'listing_deleted' => l.notifListingDeleted,
      'listing_removed' => l.notifListingRemoved,
      'price_drop_alert' => l.notifPriceDrop,
      'search_alert' => l.notifSearchAlert,
      'auction_ended' => l.notifAuctionEnded,
      'auction_cancelled' => l.notifAuctionCancelled,
      'referral' => l.notifReferralTitle,
      _ => title,
    };
  }

  String? _localizeBody(String? type, String? body, AppLocalizations l) {
    if (body == null || body.isEmpty) return body;
    switch (type) {
      case 'listing_removed':
        return l.notifListingRemovedBody;
      case 'listing_deactivated':
        final qMatch = RegExp(r'"(.+?)"').firstMatch(body);
        if (qMatch != null)
          return l.notifListingDeactivatedBodySingle(qMatch.group(1)!);
        final nMatch = RegExp(r'^(\d+)').firstMatch(body);
        if (nMatch != null)
          return l.notifListingDeactivatedBodyMultiple(
            int.parse(nMatch.group(1)!),
          );
        return body;
      case 'listing_deleted':
        final qMatch = RegExp(r'"(.+?)"').firstMatch(body);
        if (qMatch != null)
          return l.notifListingDeletedBodySingle(qMatch.group(1)!);
        final nMatch = RegExp(r'^(\d+)').firstMatch(body);
        if (nMatch != null)
          return l.notifListingDeletedBodyMultiple(int.parse(nMatch.group(1)!));
        return body;
      case 'outbid':
        if (body.contains(' — ')) {
          final dash = body.lastIndexOf(' — ');
          final item = body.substring(0, dash);
          final rest = body.substring(dash + 3);
          final colon = rest.lastIndexOf(': ');
          final price = colon >= 0 ? rest.substring(colon + 2) : rest;
          return l.notifOutbidBody(item, price);
        } else {
          final colon = body.lastIndexOf(': ');
          if (colon >= 0)
            return l.notifOutbidBodyNoItem(body.substring(colon + 2));
        }
        return body;
      case 'auction_ended':
        if (body.contains(' — ')) {
          final dash = body.lastIndexOf(' — ');
          final item = body.substring(0, dash);
          final rest = body.substring(dash + 3);
          final colon = rest.lastIndexOf(': ');
          final price = colon >= 0 ? rest.substring(colon + 2) : rest;
          return l.notifAuctionEndedBody(item, price);
        } else {
          final colon = body.lastIndexOf(': ');
          if (colon >= 0)
            return l.notifAuctionEndedBodyNoItem(body.substring(colon + 2));
        }
        return body;
      case 'auction_cancelled':
        if (body.contains(' — ')) {
          final dash = body.lastIndexOf(' — ');
          return l.notifAuctionCancelledBody(body.substring(0, dash));
        }
        return l.notifAuctionCancelledBodyNoItem;
      case 'price_drop_alert':
        if (body.contains(' — ')) {
          final dash = body.lastIndexOf(' — ');
          final item = body.substring(0, dash);
          final rest = body.substring(dash + 3);
          // "artık 750 ₺" or "now 750 ₺" — price starts at first digit
          final priceMatch = RegExp(r'(\d[\d.,\s]*[^\s].*)$').firstMatch(rest);
          final price = priceMatch != null ? priceMatch.group(1)!.trim() : rest;
          return l.notifPriceDropBody(item, price);
        }
        return body;
      case 'call_missed':
        return l.notifCallMissedBody;
      default:
        return body;
    }
  }

  IconData _iconForType(String? type) {
    return switch (type) {
      'follow' => Icons.person_add_rounded,
      'stream_started' => Icons.live_tv_rounded,
      'new_bid' => Icons.gavel_rounded,
      'outbid' => Icons.arrow_circle_up_rounded,
      'auction_won' => Icons.shopping_bag_rounded,
      'message' => Icons.chat_bubble_rounded,
      'smart_auction_alert' => Icons.bolt_rounded,
      'listing_deactivated' => Icons.pause_circle_rounded,
      'listing_deleted' => Icons.delete_outline_rounded,
      'call_missed' => Icons.phone_missed_rounded,
      _ => Icons.notifications_rounded,
    };
  }

  Color _colorForType(String? type) {
    return switch (type) {
      'follow' => const Color(0xFF6366F1),
      'stream_started' => const Color(0xFFEF4444),
      'new_bid' => const Color(0xFFF97316),
      'outbid' => const Color(0xFFEF4444),
      'auction_won' => const Color(0xFF16A34A),
      'message' => const Color(0xFF0EA5E9),
      'smart_auction_alert' => const Color(0xFF8B5CF6),
      'call_missed' => const Color(0xFFEF4444),
      _ => kPrimary,
    };
  }

  Future<void> _navigate(Map<String, dynamic> notif) async {
    final type = notif['type'] as String? ?? '';
    final relatedId = notif['related_id'] as int?;
    final body = notif['body'] as String?;
    final title = notif['title'] as String? ?? '';

    String extractHandle(String t) =>
        RegExp(r'@(\w+)').firstMatch(t)?.group(1) ?? '';

    switch (type) {
      case 'follow':
      case 'call_missed':
        final username =
            (body != null && body.isNotEmpty && !body.contains(' '))
            ? body
            : extractHandle(title);
        if (username.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PublicProfileScreen(username: username),
            ),
          );
        }
      case 'stream_started':
      case 'new_bid':
      case 'outbid':
      case 'smart_auction_alert':
        if (relatedId != null && !StreamService.isHosting) {
          final active = await StreamService.isStreamActive(relatedId);
          if (!mounted) return;
          if (!active) {
            final l = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.liveEnded),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          if (PipService.isVisible) {
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(pipProvider.notifier).disablePip();
            PipService.hidePip();
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SwipeLiveScreen.single(streamId: relatedId),
            ),
          );
        }
      case 'listing_deactivated':
      case 'auction_won':
      case 'price_drop_alert':
        if (relatedId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ListingDeepLinkLoader(listingId: relatedId),
            ),
          );
        }
      case 'message':
        if (relatedId != null) {
          final username = extractHandle(title);
          final l = AppLocalizations.of(context)!;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DirectChatScreen(
                otherUserId: relatedId,
                displayName: username.isNotEmpty ? username : l.msgUserFallback,
                otherHandle: username,
              ),
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    if (_notifHasError && _notifications.isEmpty) {
      return NetworkErrorWidget(scrollable: true, onRetry: _load);
    }
    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.notifications_none_outlined,
              size: 64,
              color: Color(0xFFD1D5DB),
            ),
            const SizedBox(height: 16),
            Text(
              l.notifNone,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(l.notifNoneDesc),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _load,
      child: Column(
        children: [
          if (_notifHasError) StaleDataBanner(onRetry: _load),
          Expanded(
            child: ListView.separated(
              itemCount: _notifications.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 60),
              itemBuilder: (context, i) {
                final notif = _notifications[i];
                final type = notif['type'] as String?;
                final title = notif['title'] as String? ?? '';
                final body = notif['body'] as String?;
                final createdAt = notif['created_at'] as String?;
                final isRead = (notif['is_read'] as bool?) ?? true;

                final typeColor = _colorForType(type);
                // follow: body = username (navigasyon için), görüntüleme için kullanılmaz
                final displayBody = type == 'follow'
                    ? null
                    : _localizeBody(type, body, l);
                final displayTitle = _localizeTitle(type, title, l);
                return ListTile(
                  onTap: () {
                    setState(
                      () =>
                          (_notifications[i]
                                  as Map<String, dynamic>)['is_read'] =
                              true,
                    );
                    _navigate(_notifications[i] as Map<String, dynamic>);
                  },
                  tileColor: isRead ? null : kPrimary.withValues(alpha: 0.06),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: isRead ? 0.08 : 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _iconForType(type),
                      size: 20,
                      color: typeColor.withValues(alpha: isRead ? 0.55 : 1.0),
                    ),
                  ),
                  title: Text(
                    displayTitle,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (displayBody != null && displayBody.isNotEmpty)
                        Text(
                          displayBody,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      Text(
                        _timeAgo(createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: displayBody != null && displayBody.isNotEmpty,
                  trailing: isRead
                      ? null
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: kPrimary,
                            shape: BoxShape.circle,
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Screen ───────────────────────────────────────────────────────────────

class DirectChatScreen extends StatefulWidget {
  final int otherUserId;
  final String displayName;
  final String otherHandle;
  final String? otherAvatarUrl;
  final int? listingId;
  final Map<String, dynamic>? contextPurchase;
  final Map<String, dynamic>? contextSale;

  const DirectChatScreen({
    super.key,
    required this.otherUserId,
    required this.displayName,
    required this.otherHandle,
    this.otherAvatarUrl,
    this.listingId,
    this.contextPurchase,
    this.contextSale,
  });

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen>
    with WidgetsBindingObserver {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _error = false;
  bool _isOtherTyping = false;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  int? _myUserId;
  Timer? _typingDebounce;
  Timer? _typingHideTimer;

  // Send / Mic toggle
  bool _hasText = false;

  // Media upload
  bool _uploadingMedia = false;

  // Voice recording
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  int _recordSecs = 0;
  Timer? _recordTimer;
  bool _shouldCancelRec = false;

  // Audio playback
  final _audioPlayer = AudioPlayer();
  int? _playingMsgId;
  Duration _playPosition = Duration.zero;
  Duration _playDuration = Duration.zero;
  bool _audioPlaying = false;
  StreamSubscription? _audioPositionSub;
  StreamSubscription? _audioDurationSub;
  StreamSubscription? _audioCompleteSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textCtrl.addListener(() {
      final has = _textCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _audioPositionSub = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _playPosition = p);
    });
    _audioDurationSub = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _playDuration = d);
    });
    _audioCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted)
        setState(() {
          _audioPlaying = false;
          _playingMsgId = null;
          _playPosition = Duration.zero;
        });
    });
    _initScreen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadMessages(bypassCache: true);
  }

  Future<void> _initScreen() async {
    final info = await StorageService.getUserInfo();
    _myUserId = info?['id'] as int?;
    await _loadMessages();
    _listenWs();
  }

  Future<void> _loadMessages({bool bypassCache = false}) async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = false;
      });
    try {
      // SWR: önce Hive cache (anlık), sonra API (taze)
      await for (final data in ApiService.get<List<Map<String, dynamic>>>(
        url: '$kBaseUrl/messages/${widget.otherUserId}',
        cacheKey: 'chat_${widget.otherUserId}',
        cacheTtl: const Duration(minutes: 2),
        bypassCache: bypassCache,
        fromJson: (raw) => (raw as List)
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList(),
      )) {
        if (!mounted) return;
        // Bekleyen kuyruk mesajlarını API yanıtına birleştir
        final pending = OfflineQueueService.getPendingForReceiver(
          widget.otherUserId,
        );
        final merged = List<Map<String, dynamic>>.from(data);
        for (final p in pending) {
          // API zaten teslim ettiyse gösterme
          final alreadyIn = data.any(
            (m) =>
                m['content'] == p['content'] &&
                (m['sender_id'] as int?) == _myUserId,
          );
          if (!alreadyIn) {
            merged.add({
              'id': -(p['queued_at'] as int),
              'sender_id': _myUserId,
              'receiver_id': widget.otherUserId,
              'content': p['content'] as String,
              'is_read': false,
              'created_at': DateTime.fromMillisecondsSinceEpoch(
                p['queued_at'] as int,
              ).toUtc().toIso8601String(),
              '_pending': true,
              '_local_id': p['local_id'] as String?,
            });
          }
        }
        setState(() {
          _messages = merged;
          _loading = false;
        });
        _scrollToBottom(animate: false);
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  void _listenWs() {
    _wsSub = WsService.messageStream.stream.listen((data) {
      final type = data['type'] as String?;

      if (type == 'connected') {
        _loadMessages();
        return;
      }

      if (type == 'messages_read') {
        final byUserId = data['by_user_id'] as int?;
        if (byUserId == widget.otherUserId && mounted) {
          setState(() {
            _messages = _messages.map((m) {
              if ((m['sender_id'] as int?) == _myUserId) {
                return {...m, 'is_read': true};
              }
              return m;
            }).toList();
          });
        }
        return;
      }

      if (type == 'typing') {
        final senderId = data['sender_id'] as int?;
        if (senderId == widget.otherUserId && mounted) {
          setState(() => _isOtherTyping = true);
          _typingHideTimer?.cancel();
          _typingHideTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _isOtherTyping = false);
          });
        }
        return;
      }

      if (type == 'message_deleted') {
        final id = data['id'];
        if (mounted)
          setState(() => _messages.removeWhere((m) => m['id'] == id));
        return;
      }

      if (type != 'message') return;
      final senderId = data['sender_id'] as int?;
      final receiverId = data['receiver_id'] as int?;
      if ((senderId == _myUserId && receiverId == widget.otherUserId) ||
          (senderId == widget.otherUserId && receiverId == _myUserId)) {
        final msgId = data['id'];
        final exists = _messages.any((m) => m['id'] == msgId);
        if (!exists && mounted) {
          setState(() {
            if (senderId == _myUserId) {
              _messages.removeWhere(
                (m) =>
                    (m['id'] as int) < 0 &&
                    m['content'] == data['content'] &&
                    m['sender_id'] == _myUserId,
              );
            }
            _messages.add(data);
          });
          _scrollToBottom();
        }
      }
    });
  }

  void _onTextChanged(String text) {
    if (text.isEmpty) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 500), () {
      WsService.sendJson({
        'type': 'typing',
        'target_user_id': widget.otherUserId,
      });
    });
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (animate) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  // ─── Media upload ────────────────────────────────────────────────────

  Future<void> _uploadMedia({
    required List<int> bytes,
    required String contentType,
    required String fileName,
    required String mimeType,
    int? durationSecs,
  }) async {
    final l = AppLocalizations.of(context)!;
    final token = await StorageService.getToken();
    if (token == null || !mounted) return;
    setState(() => _uploadingMedia = true);
    try {
      final uri = Uri.parse('$kBaseUrl/messages/upload');
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['receiver_id'] = widget.otherUserId.toString()
        ..fields['content_type'] = contentType
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: fileName,
            contentType: MediaType.parse(mimeType),
          ),
        );
      if (durationSecs != null)
        req.fields['duration_secs'] = durationSecs.toString();
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      if (!mounted) return;
      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        final msg = Map<String, dynamic>.from(jsonDecode(body) as Map);
        // WS broadcast ile aynı mesajın iki kez eklenmesini önle
        final msgId = msg['id'];
        if (msgId != null && !_messages.any((m) => m['id'] == msgId)) {
          setState(() => _messages.add(msg));
        }
        _scrollToBottom();
      } else {
        String errMsg = l.attachSendFailed;
        try {
          final errBody = jsonDecode(body) as Map<String, dynamic>?;
          final detail = errBody?['detail'] as String?;
          if (detail != null && detail.isNotEmpty) errMsg = detail;
        } catch (_) {}
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errMsg)));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.attachSendFailed)));
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _showAttachSheet() async {
    final l = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.attachPickGallery),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(l.attachPickCamera),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(source: ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(l.attachPickVideo),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendVideo(source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_camera_back_outlined),
              title: Text(l.attachRecordVideo),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendVideo(source: ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: Text(l.attachPickFile),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendFile();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage({required ImageSource source}) async {
    final l = AppLocalizations.of(context)!;
    // iOS permission dialog'unu native paket tetikler (stream/LiveKit gibi).
    // Pre-check yapmak dialog'u bloke edebilir — null dönünce status'u kontrol et.
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (!mounted) return;
    if (picked == null) {
      final perm = source == ImageSource.camera
          ? Permission.camera
          : Permission.photos;
      final status = await perm.status;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return;
    }
    final raw = await picked.readAsBytes();
    if (raw.length > 5 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.attachFileTooLarge)));
      return;
    }
    final compressed = await FlutterImageCompress.compressWithList(
      raw,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    await _uploadMedia(
      bytes: compressed,
      contentType: 'image',
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
    );
  }

  Future<void> _pickAndSendVideo({
    ImageSource source = ImageSource.gallery,
  }) async {
    final l = AppLocalizations.of(context)!;
    final picked = await ImagePicker().pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 15),
    );
    if (picked == null || !mounted) return;
    final info = await VideoCompress.getMediaInfo(picked.path);
    if ((info.duration ?? 0) / 1000 > 15) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.attachVideoTooLong)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.attachVideoProcessing),
        duration: const Duration(seconds: 10),
      ),
    );
    final result = await VideoCompress.compressVideo(
      picked.path,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    final file = result?.file;
    if (file == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.attachSendFailed)));
      return;
    }
    final bytes = await file.readAsBytes();
    final dur = ((info.duration ?? 0) / 1000).round();
    await _uploadMedia(
      bytes: bytes,
      contentType: 'video',
      fileName: 'video.mp4',
      mimeType: 'video/mp4',
      durationSecs: dur,
    );
  }

  static const _allowedFileExts = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'];
  static const _mimeMap = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
  };

  Future<void> _pickAndSendFile() async {
    final l = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: _allowedFileExts,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    if (bytes.length > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.attachFileTooLarge)));
      return;
    }
    final ext = f.extension?.toLowerCase() ?? '';
    final mime = _mimeMap[ext] ?? 'application/octet-stream';
    await _uploadMedia(
      bytes: bytes,
      contentType: 'file',
      fileName: f.name,
      mimeType: mime,
    );
  }

  // ─── Voice recording ─────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final l = AppLocalizations.of(context)!;
    // iOS permission dialog'unu record paketi tetikler — pre-check yapmıyoruz.
    try {
      final tmpDir = await getTemporaryDirectory();
      final path =
          '${tmpDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _recordSecs = 0;
        _shouldCancelRec = false;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _recordSecs++);
        if (_recordSecs >= 10) {
          t.cancel();
          _stopAndSend();
        }
      });
    } catch (_) {
      if (!mounted) return;
      final micStatus = await Permission.microphone.status;
      if (!mounted) return;
      if (micStatus.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.voiceRecordFailed)));
      }
    }
  }

  Future<void> _stopAndSend() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (_shouldCancelRec || path == null || !mounted) return;
    final file = File(path);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    await _uploadMedia(
      bytes: bytes,
      contentType: 'voice',
      fileName: 'voice.m4a',
      mimeType: 'audio/mp4',
      durationSecs: _recordSecs.clamp(1, 10),
    );
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _shouldCancelRec = true;
    await _recorder.stop();
    setState(() => _isRecording = false);
  }

  // ─── Audio playback ──────────────────────────────────────────────────

  Future<void> _toggleVoicePlayback(
    int msgId,
    String url,
    int? durationSecs,
  ) async {
    final l = AppLocalizations.of(context)!;
    if (_playingMsgId == msgId && _audioPlaying) {
      await _audioPlayer.pause();
      setState(() => _audioPlaying = false);
      return;
    }
    if (_playingMsgId != msgId) {
      setState(() {
        _playingMsgId = msgId;
        _playPosition = Duration.zero;
        _playDuration = durationSecs != null
            ? Duration(seconds: durationSecs)
            : Duration.zero;
      });
    }
    try {
      await _audioPlayer.play(UrlSource(imgUrl(url)));
      if (mounted) setState(() => _audioPlaying = true);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.voicePlayFailed)));
    }
  }

  // ─── File download/open ──────────────────────────────────────────────

  Future<void> _downloadAndOpen(String url, String? fileName) async {
    final l = AppLocalizations.of(context)!;
    try {
      final response = await http.get(Uri.parse(imgUrl(url)));
      final dir = await getTemporaryDirectory();
      final name = fileName ?? url.split('/').last;
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(response.bodyBytes);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.attachOpenFailed)));
    }
  }

  // ─── Message content builder ─────────────────────────────────────────

  Widget _buildMsgContent(Map<String, dynamic> msg, bool isMe) {
    final l = AppLocalizations.of(context)!;
    final ct = msg['content_type'] as String? ?? 'text';
    final mediaUrl = msg['media_url'] as String?;
    final thumbUrl = msg['thumbnail_url'] as String?;
    final dur = msg['duration_secs'] as int?;
    final fileName = msg['file_name'] as String?;
    final fileSize = msg['file_size'] as int?;
    final msgId = msg['id'] as int;

    switch (ct) {
      case 'voice':
        final isThisPlaying = _playingMsgId == msgId && _audioPlaying;
        final totalDur = dur ?? 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                if (mediaUrl != null)
                  _toggleVoicePlayback(msgId, mediaUrl, dur);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe ? Colors.white24 : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isThisPlaying ? Icons.pause : Icons.play_arrow,
                  size: 20,
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value:
                        (_playingMsgId == msgId && _playDuration.inSeconds > 0)
                        ? (_playPosition.inMilliseconds /
                                  _playDuration.inMilliseconds)
                              .clamp(0.0, 1.0)
                        : 0.0,
                    backgroundColor: isMe
                        ? Colors.white24
                        : Colors.grey.shade300,
                    color: isMe ? Colors.white : const Color(0xFF06B6D4),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${totalDur}s',
                  style: TextStyle(
                    fontSize: 11,
                    color: isMe ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        );

      case 'image':
        return GestureDetector(
          onTap: () {
            if (mediaUrl != null)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _FullScreenImagePage(url: imgUrl(mediaUrl)),
                ),
              );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: imgUrl(thumbUrl ?? mediaUrl ?? ''),
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              placeholder: (_, _) => const SizedBox(
                width: 200,
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, _, _) => const Icon(Icons.broken_image),
            ),
          ),
        );

      case 'video':
        return GestureDetector(
          onTap: () {
            if (mediaUrl != null)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _FullScreenVideoPage(url: imgUrl(mediaUrl)),
                ),
              );
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: thumbUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imgUrl(thumbUrl),
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                      )
                    : Container(width: 200, height: 200, color: Colors.black),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              if (dur != null)
                Positioned(
                  bottom: 6,
                  right: 10,
                  child: Text(
                    '${dur}s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ),
            ],
          ),
        );

      case 'file':
        final sizeStr = fileSize != null
            ? ' · ${(fileSize / 1024).round()}KB'
            : '';
        return GestureDetector(
          onTap: () => _downloadAndOpen(mediaUrl ?? '', fileName),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 32,
                color: isMe ? Colors.white70 : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName ?? l.attachPickFile,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sizeStr.isNotEmpty)
                      Text(
                        sizeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe ? Colors.white60 : Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      default: // 'text'
        return _MessageText(
          content: msg['content'] as String? ?? '',
          isMe: isMe,
        );
    }
  }

  Future<void> _deleteMessage(int messageId) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l.msgDeleteMessageConfirm,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                l.msgDeleteMessage,
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l.btnCancel),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    // Optimistik kaldır
    setState(() => _messages.removeWhere((m) => m['id'] == messageId));
    final ok = await NotificationService.deleteMessage(messageId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.msgDeleteMessageFailed)));
      // Başarısız olursa listeyi yeniden yükle
      _loadMessages();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.msgDeleteMessageSuccess)));
    }
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _textCtrl.clear();

    // Optimistik ekleme — pending (saat ikonu) gösterir
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    if (_myUserId != null && mounted) {
      setState(
        () => _messages.add({
          'id': tempId,
          'sender_id': _myUserId,
          'receiver_id': widget.otherUserId,
          'content': text,
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          '_pending': true,
        }),
      );
      _scrollToBottom();
    }

    // Çevrimdışıysa doğrudan kuyruğa yaz
    final isOnline = await ConnectivityService().isConnected;
    if (!isOnline) {
      final localId = await OfflineQueueService.enqueue(
        widget.otherUserId,
        text,
        listingId: widget.listingId,
      );
      if (mounted) {
        setState(() {
          _sending = false;
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx >= 0) {
            _messages[idx] = {..._messages[idx], '_local_id': localId};
          }
        });
      }
      return;
    }

    // Çevrimiçi → API'ye gönder
    final ok = await NotificationService.sendMessage(
      widget.otherUserId,
      text,
      listingId: widget.listingId,
    );
    if (mounted) {
      setState(() => _sending = false);
      if (!ok) {
        // API başarısız → kuyruğa ekle, pending göster
        final localId = await OfflineQueueService.enqueue(
          widget.otherUserId,
          text,
          listingId: widget.listingId,
        );
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx >= 0) {
            _messages[idx] = {..._messages[idx], '_local_id': localId};
          }
        });
      } else {
        // Başarı → WS onaylı mesajı ekleyecek; optimistik geçiciyi sil
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
      }
    }
  }

  String _timeLabel(String? isoStr) {
    if (isoStr == null) return '';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    _typingDebounce?.cancel();
    _typingHideTimer?.cancel();
    _audioPositionSub?.cancel();
    _audioDurationSub?.cancel();
    _audioCompleteSub?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    VideoCompress.cancelCompression();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName),
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, size: 22),
            tooltip: l.callVoiceCall,
            onPressed: () async {
              if (CallService.instance.hasActiveCall) {
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '/call_screen'),
                    builder: (_) => const CallScreen(),
                    fullscreenDialog: true,
                  ),
                );
                return;
              }

              await CallService.instance.startCall(
                calleeId: widget.otherUserId,
                calleeUsername: widget.otherHandle,
                calleeAvatar: widget.otherAvatarUrl,
              );
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/call_screen'),
                  builder: (_) => const CallScreen(),
                  fullscreenDialog: true,
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.contextPurchase != null || widget.contextSale != null)
            _ContextBanner(
              purchase: widget.contextPurchase,
              sale: widget.contextSale,
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  )
                : Column(
                    children: [
                      if (_error && _messages.isNotEmpty)
                        StaleDataBanner(onRetry: _loadMessages),
                      Expanded(
                        child: _error && _messages.isEmpty
                            ? NetworkErrorWidget(
                                scrollable: true,
                                onRetry: _loadMessages,
                              )
                            : _messages.isEmpty
                            ? Center(
                                child: Text(
                                  l.msgNoChat,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollCtrl,
                                reverse: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                itemCount: _messages.length,
                                itemBuilder: (context, i) {
                                  final msg =
                                      _messages[_messages.length - 1 - i];
                                  final senderId = msg['sender_id'] as int?;
                                  final isMe = senderId == _myUserId;
                                  final time = _timeLabel(
                                    msg['created_at'] as String?,
                                  );
                                  final isRead =
                                      (msg['is_read'] as bool?) ?? false;
                                  final isPending =
                                      (msg['_pending'] as bool?) ?? false;
                                  final ct =
                                      msg['content_type'] as String? ?? 'text';
                                  final isMedia =
                                      ct == 'image' || ct == 'video';

                                  final msgId = msg['id'] as int? ?? -1;
                                  return Align(
                                    alignment: isMe
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: GestureDetector(
                                      onLongPress: (isMe && msgId > 0)
                                          ? () => _deleteMessage(msgId)
                                          : null,
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        padding: isMedia
                                            ? const EdgeInsets.all(2)
                                            : const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.72,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? kPrimary
                                              : AppColors.card(context),
                                          borderRadius: BorderRadius.only(
                                            topLeft: const Radius.circular(16),
                                            topRight: const Radius.circular(16),
                                            bottomLeft: isMe
                                                ? const Radius.circular(16)
                                                : const Radius.circular(4),
                                            bottomRight: isMe
                                                ? const Radius.circular(4)
                                                : const Radius.circular(16),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            _buildMsgContent(msg, isMe),
                                            const SizedBox(height: 2),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  time,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isMe
                                                        ? Colors.white
                                                              .withValues(
                                                                alpha: 0.75,
                                                              )
                                                        : const Color(
                                                            0xFF9CA3AF,
                                                          ),
                                                  ),
                                                ),
                                                if (isMe) ...[
                                                  const SizedBox(width: 3),
                                                  Icon(
                                                    isPending
                                                        ? Icons
                                                              .access_time_rounded
                                                        : (isRead
                                                              ? Icons.done_all
                                                              : Icons.done),
                                                    size: 12,
                                                    color: isPending
                                                        ? Colors.white
                                                              .withValues(
                                                                alpha: 0.45,
                                                              )
                                                        : (isRead
                                                              ? Colors
                                                                    .blue
                                                                    .shade200
                                                              : Colors.white
                                                                    .withValues(
                                                                      alpha:
                                                                          0.6,
                                                                    )),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ), // inner Expanded
                    ],
                  ), // Column
          ),
          // Yazıyor göstergesi
          if (_isOtherTyping)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  const _TypingIndicator(),
                  const SizedBox(width: 8),
                  Text(
                    l.msgTyping,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(context),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              border: Border(top: BorderSide(color: AppColors.border(context))),
            ),
            child: SafeArea(
              top: false,
              child: _isRecording ? _buildRecordingBar(l) : _buildNormalBar(l),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalBar(AppLocalizations l) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Ek dosya butonu
        GestureDetector(
          onTap: _uploadingMedia ? null : _showAttachSheet,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10, right: 4),
            child: _uploadingMedia
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimary,
                    ),
                  )
                : Icon(
                    Icons.attach_file_rounded,
                    color: AppColors.textSecondary(context),
                    size: 24,
                  ),
          ),
        ),
        // Metin alanı
        Expanded(
          child: TextField(
            key: const Key('chat_input_mesaj'),
            controller: _textCtrl,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            maxLines: null,
            minLines: 1,
            onChanged: _onTextChanged,
            decoration: InputDecoration(
              hintText: l.msgWriteHint,
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              filled: true,
              fillColor: AppColors.inputFill(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Gönder / Mikrofon butonu
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: _hasText || _sending
              ? GestureDetector(
                  key: const ValueKey('send'),
                  onTap: _send,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: kPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                )
              : GestureDetector(
                  key: const ValueKey('mic'),
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopAndSend(),
                  onLongPressMoveUpdate: (details) {
                    if (details.localOffsetFromOrigin.dx < -60) {
                      setState(() => _shouldCancelRec = true);
                    }
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: kPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRecordingBar(AppLocalizations l) {
    final mins = _recordSecs ~/ 60;
    final secs = _recordSecs % 60;
    final timer =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    return Row(
      children: [
        // Kırmızı kayıt noktası + süre
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 6),
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        ),
        Text(
          timer,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(width: 8),
        // Kaydır iptal
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chevron_left, size: 18, color: Colors.grey),
              Text(
                l.voiceSwipeToCancel,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        // İptal butonu
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delete_outline,
              color: Colors.red,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Gönder (bırak)
        GestureDetector(
          onTap: _stopAndSend,
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: kPrimary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.send_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Alışveriş/Satış bağlam bandı ─────────────────────────────────────────────

class _ContextBanner extends StatelessWidget {
  final Map<String, dynamic>? purchase;
  final Map<String, dynamic>? sale;

  const _ContextBanner({this.purchase, this.sale});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final item = purchase ?? sale!;
    final isPurchase = purchase != null;
    final itemName = item['item_name'] as String? ?? l.msgItemFallback;
    final price = (item['final_price'] as num?)?.toDouble() ?? 0.0;
    final thumbnailUrl =
        item['thumbnail_url'] as String? ?? item['image_url'] as String?;
    final label = isPurchase ? l.msgContextPurchase : l.msgContextSale;

    return InkWell(
      onTap: () {
        if (isPurchase) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PurchaseDetailScreen(purchase: item),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SaleDetailScreen(sale: item)),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          border: Border(bottom: BorderSide(color: AppColors.border(context))),
        ),
        child: Row(
          children: [
            if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: imgUrl(thumbnailUrl),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _thumb(context, isPurchase),
                  placeholder: (_, _) => _thumb(context, isPurchase),
                ),
              )
            else
              _thumb(context, isPurchase),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isPurchase ? const Color(0xFF6B21A8) : kPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    itemName,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              fmtPrice(price),
              style: const TextStyle(
                color: Color(0xFF4ADE80),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.iconSecondary(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(BuildContext context, bool isPurchase) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: (isPurchase ? const Color(0xFF6B21A8) : kPrimary).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        isPurchase ? Icons.shopping_bag_outlined : Icons.storefront_outlined,
        size: 22,
        color: isPurchase ? const Color(0xFF6B21A8) : kPrimary,
      ),
    );
  }
}

// ── Tıklanabilir URL'li mesaj metni ──────────────────────────────────────────

class _MessageText extends StatelessWidget {
  final String content;
  final bool isMe;

  const _MessageText({required this.content, required this.isMe});

  // teqlif.com/ilan/{id} veya teqlif://auction/{id} linklerini tespit et
  static final _linkRegex = RegExp(
    r'(https?://[^\s]+/ilan/(\d+)|teqlif://auction/(\d+))',
  );

  Future<void> _openListing(BuildContext context, int listingId) async {
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/listings/$listingId'));
      if (resp.statusCode == 200 && context.mounted) {
        final listing = jsonDecode(resp.body) as Map<String, dynamic>;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ListingDetailScreen(listing: listing),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _openAuctionDetail(BuildContext context, int auctionId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/auth/me/auction/$auctionId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && context.mounted) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final role = body['role'] as String?;
        final data = body['data'] as Map<String, dynamic>;
        if (role == 'buyer') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PurchaseDetailScreen(purchase: data),
            ),
          );
        } else if (role == 'seller') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SaleDetailScreen(sale: data)),
          );
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final normalColor = isMe ? Colors.white : AppColors.textPrimary(context);
    const linkColor = Color(0xFF38BDF8);
    const auctionLinkColor = Color(0xFF4ADE80);

    final matches = _linkRegex.allMatches(content).toList();
    if (matches.isEmpty) {
      return Text(
        content,
        style: TextStyle(color: normalColor, fontSize: 14.5),
      );
    }

    final spans = <TextSpan>[];
    int cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: content.substring(cursor, match.start),
            style: TextStyle(color: normalColor, fontSize: 14.5),
          ),
        );
      }

      if (match.group(2) != null) {
        // İlan linki
        final listingId = int.parse(match.group(2)!);
        spans.add(
          TextSpan(
            text: l.msgGoToListing,
            style: const TextStyle(
              color: linkColor,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: linkColor,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openListing(context, listingId),
          ),
        );
      } else if (match.group(3) != null) {
        // Açık artırma detay linki
        final auctionId = int.parse(match.group(3)!);
        spans.add(
          TextSpan(
            text: l.msgGoToAuctionDetail,
            style: const TextStyle(
              color: auctionLinkColor,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: auctionLinkColor,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openAuctionDetail(context, auctionId),
          ),
        );
      }
      cursor = match.end;
    }

    if (cursor < content.length) {
      spans.add(
        TextSpan(
          text: content.substring(cursor),
          style: TextStyle(color: normalColor, fontSize: 14.5),
        ),
      );
    }

    return RichText(text: TextSpan(children: spans));
  }
}

// ── Yazıyor animasyonu ────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (((_ctrl.value * 3) - i) % 3) / 3;
            final opacity = (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(
              0.25,
              1.0,
            );
            return Container(
              margin: const EdgeInsets.only(right: 3),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Tam ekran resim görüntüleyici ─────────────────────────────────────────────

class _FullScreenImagePage extends StatelessWidget {
  final String url;
  const _FullScreenImagePage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, _) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (_, _, _) =>
                const Icon(Icons.broken_image, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ── Tam ekran video oynatıcı ──────────────────────────────────────────────────

class _FullScreenVideoPage extends StatefulWidget {
  final String url;
  const _FullScreenVideoPage({required this.url});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  late VideoPlayerController _vCtrl;
  bool _initialized = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _vCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted)
          setState(() {
            _initialized = true;
          });
        _vCtrl.play();
        setState(() => _playing = true);
      });
    _vCtrl.addListener(() {
      if (mounted && _vCtrl.value.isPlaying != _playing) {
        setState(() => _playing = _vCtrl.value.isPlaying);
      }
    });
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _initialized
            ? GestureDetector(
                onTap: () {
                  _vCtrl.value.isPlaying ? _vCtrl.pause() : _vCtrl.play();
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _vCtrl.value.aspectRatio,
                      child: VideoPlayer(_vCtrl),
                    ),
                    if (!_playing)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                  ],
                ),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
