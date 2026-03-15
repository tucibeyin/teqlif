import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/api.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/push_notification_service.dart';
import '../services/ws_service.dart';
import 'public_profile_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
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
    _badgeSub = PushNotificationService.badgeRefreshNeeded.stream
        .listen((_) => _loadUnreadNotifs());
    // notificationStream: yeni FCM bildirimi gelince (follow, bid, vb.) noktayı güncelle
    _fcmSub = PushNotificationService.notificationStream.stream
        .listen((_) => _loadUnreadNotifs());
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesajlar'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: kPrimary,
          unselectedLabelColor: const Color(0xFF9CA3AF),
          indicatorColor: kPrimary,
          tabs: [
            const Tab(text: 'Mesajlar'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bildirimler'),
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
        children: const [
          _MessagesTab(),
          _NotificationsTab(),
        ],
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
  StreamSubscription<Map<String, dynamic>>? _fcmSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _load();
    // FCM / app-resume olayları (arka plan → ön plan geçişi)
    _fcmSub = PushNotificationService.notificationStream.stream.listen((_) => _load(silent: true));
    // WebSocket: yeni mesaj gelince anında güncelle
    _wsSub = WsService.messageStream.stream.listen((data) {
      if (data['type'] == 'message') {
        _load(silent: true);
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

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final data = await NotificationService.getConversations();
    if (mounted) {
      setState(() {
        _conversations = data;
        _loading = false;
      });
    }
  }

  String _timeAgo(String? isoStr) {
    if (isoStr == null) return '';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'şimdi';
      if (diff.inMinutes < 60) return '${diff.inMinutes}d önce';
      if (diff.inHours < 24) return '${diff.inHours}s önce';
      return '${diff.inDays}g önce';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    if (_conversations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Color(0xFFD1D5DB)),
            SizedBox(height: 16),
            Text(
              'Henüz mesajın yok',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Bir ilanla ilgilendiğinde\nburada görüntülenecek',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final conv = _conversations[i];
          final username = conv['username'] as String? ?? '';
          final fullName = conv['full_name'] as String? ?? username;
          final lastMsg = conv['last_message'] as String? ?? '';
          final lastAt = conv['last_at'] as String?;
          final unread = (conv['unread_count'] as int?) ?? 0;
          final otherId = (conv['user_id'] as int?) ?? 0;
          final initial = (fullName.isNotEmpty ? fullName[0] : '?').toUpperCase();

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: kPrimary.withOpacity(0.15),
              child: Text(
                initial,
                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    fullName,
                    style: TextStyle(
                      fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  _timeAgo(lastAt),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
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
                      color: unread > 0 ? const Color(0xFF374151) : const Color(0xFF9CA3AF),
                      fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
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
                  ),
                ),
              ).then((_) {
              _load(silent: true);
              PushNotificationService.badgeRefreshNeeded.add(null);
            });
            },
          );
        },
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
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = PushNotificationService.notificationStream.stream.listen((_) => _load(silent: true));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final data = await NotificationService.getNotifications();
    if (mounted) {
      setState(() {
        _notifications = data;
        _loading = false;
      });
    }
  }

  String _timeAgo(String? isoStr) {
    if (isoStr == null) return '';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'şimdi';
      if (diff.inMinutes < 60) return '${diff.inMinutes}d önce';
      if (diff.inHours < 24) return '${diff.inHours}s önce';
      return '${diff.inDays}g önce';
    } catch (_) {
      return '';
    }
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'message':
        return Icons.chat_bubble_outline;
      case 'bid':
        return Icons.gavel_outlined;
      case 'sale':
        return Icons.shopping_bag_outlined;
      case 'system':
        return Icons.info_outline;
      default:
        return Icons.notifications_none_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    if (_notifications.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_outlined, size: 64, color: Color(0xFFD1D5DB)),
            SizedBox(height: 16),
            Text(
              'Bildirim yok',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Yeni bildirimler burada görünecek',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _notifications.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
        itemBuilder: (context, i) {
          final notif = _notifications[i];
          final type = notif['type'] as String?;
          final title = notif['title'] as String? ?? '';
          final body = notif['body'] as String?;
          final createdAt = notif['created_at'] as String?;
          final isRead = (notif['is_read'] as bool?) ?? true;

          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isRead
                    ? const Color(0xFFF3F4F6)
                    : kPrimary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconForType(type),
                size: 20,
                color: isRead ? const Color(0xFF6B7280) : kPrimary,
              ),
            ),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (body != null && body.isNotEmpty)
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                Text(
                  _timeAgo(createdAt),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
            isThreeLine: body != null && body.isNotEmpty,
          );
        },
      ),
    );
  }
}

// ── Chat Screen ───────────────────────────────────────────────────────────────

class DirectChatScreen extends StatefulWidget {
  final int otherUserId;
  final String displayName;
  final String otherHandle;

  const DirectChatScreen({
    super.key,
    required this.otherUserId,
    required this.displayName,
    required this.otherHandle,
  });

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  int? _myUserId;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    final info = await StorageService.getUserInfo();
    _myUserId = info?['id'] as int?;
    await _loadMessages();
    _listenWs();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    final data = await NotificationService.getMessages(widget.otherUserId);
    if (mounted) {
      setState(() {
        _messages = data.map((m) => Map<String, dynamic>.from(m as Map)).toList();
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  void _listenWs() {
    _wsSub = WsService.messageStream.stream.listen((data) {
      if (data['type'] != 'message') return;
      final senderId = data['sender_id'] as int?;
      final receiverId = data['receiver_id'] as int?;
      if ((senderId == _myUserId && receiverId == widget.otherUserId) ||
          (senderId == widget.otherUserId && receiverId == _myUserId)) {
        final msgId = data['id'];
        final exists = _messages.any((m) => m['id'] == msgId);
        if (!exists && mounted) {
          setState(() {
            if (senderId == _myUserId) {
              _messages.removeWhere((m) =>
                  (m['id'] as int) < 0 &&
                  m['content'] == data['content'] &&
                  m['sender_id'] == _myUserId);
            }
            _messages.add(data);
          });
          _scrollToBottom();
        }
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _textCtrl.clear();

    // Optimistically add message to UI immediately
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    if (_myUserId != null && mounted) {
      setState(() => _messages.add({
        'id': tempId,
        'sender_id': _myUserId,
        'receiver_id': widget.otherUserId,
        'content': text,
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }));
      _scrollToBottom();
    }

    final ok = await NotificationService.sendMessage(widget.otherUserId, text);
    if (mounted) {
      setState(() => _sending = false);
      if (!ok) {
        // Remove temp message on failure
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj gönderilemedi')),
        );
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
    _wsSub?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName),
        leading: const BackButton(),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Henüz mesaj yok.\nİlk mesajı gönder!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF9CA3AF)),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final msg = _messages[i];
                          final senderId = msg['sender_id'] as int?;
                          final isMe = senderId == _myUserId;
                          final content = msg['content'] as String? ?? '';
                          final time = _timeLabel(msg['created_at'] as String?);

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.72,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? kPrimary
                                    : const Color(0xFFE5E7EB),
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
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    content,
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : const Color(0xFF1F2937),
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe
                                          ? Colors.white.withOpacity(0.75)
                                          : const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Mesaj yaz...',
                        hintStyle:
                            const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
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
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Inline profile navigation wrapper (avoids circular import)
class _ProfileView extends StatelessWidget {
  final String username;
  final int userId;
  final String displayName;

  const _ProfileView({
    required this.username,
    required this.userId,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    return PublicProfileScreen(username: username, userId: userId);
  }
}
