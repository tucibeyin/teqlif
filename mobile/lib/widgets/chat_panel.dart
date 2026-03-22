import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../screens/public_profile_screen.dart';
import '../services/storage_service.dart';
import '../utils/username_color.dart';

class _TimedMessage {
  final ChatMessage message;
  final ValueNotifier<double> opacity = ValueNotifier(1.0);
  bool _disposed = false;
  bool _permanent = false; // true → timer expired but last-3 protection kept it

  _TimedMessage(this.message, {required bool Function() shouldRemove, required VoidCallback onExpired}) {
    Future.delayed(const Duration(seconds: 6), () {
      if (_disposed) return;
      if (!shouldRemove()) {
        _permanent = true;
        return; // keep it — it's in the last 3
      }
      opacity.value = 0.0;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!_disposed) onExpired();
      });
    });
  }

  void dispose() {
    _disposed = true;
    opacity.dispose();
  }
}

class ChatPanel extends StatefulWidget {
  final int streamId;
  final VoidCallback? onStreamEnded;
  final void Function(int count)? onViewerCountChanged;
  /// Host için: kullanıcı adına tıklanınca çağrılır
  final void Function(String username)? onUsernameTap;
  /// Viewer için: susturulunca çağrılır
  final VoidCallback? onMuted;
  /// Viewer için: susturma kaldırılınca çağrılır
  final VoidCallback? onUnmuted;
  /// Viewer için: yayından atılınca çağrılır
  final VoidCallback? onKicked;

  const ChatPanel({
    super.key,
    required this.streamId,
    this.onStreamEnded,
    this.onViewerCountChanged,
    this.onUsernameTap,
    this.onMuted,
    this.onUnmuted,
    this.onKicked,
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<_TimedMessage> _messages = [];
  final List<ChatMessage> _history = []; // last 50 messages
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _selfMuted = false;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
  bool _streamEnded = false;
  String? _token;
  bool _inputFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _inputFocused = _focusNode.hasFocus);
    });
    _init();
  }

  Future<void> _init() async {
    _token = await StorageService.getToken();
    if (!mounted) return;
    setState(() {});
    _connectWS();
  }

  @override
  void dispose() {
    _reconnecting = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    for (final m in _messages) {
      m.dispose();
    }
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _wsBaseUrl {
    return kBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
  }

  void _addMessage(ChatMessage msg) {
    if (!mounted) return;
    late _TimedMessage timed;
    timed = _TimedMessage(
      msg,
      shouldRemove: () {
        final idx = _messages.indexOf(timed);
        if (idx < 0) return true;
        return idx < _messages.length - 3;
      },
      onExpired: () {
        if (mounted) {
          setState(() => _messages.removeWhere((m) => m == timed));
        }
      },
    );
    setState(() {
      _messages.add(timed);
      if (_messages.length > 20) {
        _messages.removeAt(0).dispose();
      }
      _history.add(msg);
      if (_history.length > 50) {
        _history.removeAt(0);
      }
    });
    _evictStalePermanents();
  }

  /// Yeni mesaj gelince: _permanent işaretli ama artık son 3'te olmayan
  /// mesajları fade-out yaparak listeden temizler.
  void _evictStalePermanents() {
    final toEvict = <_TimedMessage>[];
    final protectedStart = _messages.length - 3;
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i]._permanent && i < protectedStart) {
        toEvict.add(_messages[i]);
      }
    }
    for (final m in toEvict) {
      m._permanent = false;
      m.opacity.value = 0.0;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() => _messages.removeWhere((x) => x == m));
        }
      });
    }
  }

  void _connectWS() {
    if (!mounted || _token == null) return;
    _heartbeat?.cancel();
    try {
      final uri = Uri.parse(
        '$_wsBaseUrl/chat/${widget.streamId}/ws?token=${Uri.encodeComponent(_token!)}',
      );
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        (data) {
          if (!mounted) return;
          String? _eventType;
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            if (json['type'] == 'message') {
              _addMessage(ChatMessage.fromJson(json));
            } else if (json['type'] == 'system_join') {
              final uname = json['username'] as String? ?? '';
              _addMessage(ChatMessage(
                id: 'join_${DateTime.now().millisecondsSinceEpoch}',
                username: uname,
                content: 'yayına katıldı',
                createdAt: DateTime.now(),
                isSystem: true,
              ));
            } else if (json['type'] == 'history') {
              final msgs = (json['messages'] as List)
                  .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                  .toList();
              for (final m in msgs) {
                _addMessage(m);
              }
            } else if (json['type'] == 'viewer_count') {
              final count = (json['count'] as num?)?.toInt() ?? 0;
              widget.onViewerCountChanged?.call(count);
            } else if (json['type'] == 'stream_ended') {
              _streamEnded = true;
              _eventType = 'stream_ended';
            } else if (json['type'] == 'muted') {
              if (mounted) setState(() => _selfMuted = true);
              _eventType = 'muted';
            } else if (json['type'] == 'unmuted') {
              if (mounted) setState(() => _selfMuted = false);
              _eventType = 'unmuted';
            } else if (json['type'] == 'kicked') {
              _streamEnded = true;
              _eventType = 'kicked';
            }
          } catch (e) {
            debugPrint('[CHAT] JSON parse hatası: $e');
          }
          // Callback'leri try-catch dışında çağır — exception gizlenmesin
          if (_eventType == 'stream_ended') widget.onStreamEnded?.call();
          if (_eventType == 'muted') widget.onMuted?.call();
          if (_eventType == 'unmuted') widget.onUnmuted?.call();
          if (_eventType == 'kicked') {
            debugPrint('[CHAT] kicked — onKicked null:${widget.onKicked == null}');
            widget.onKicked?.call();
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: false,
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        if (!mounted) return;
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting || !mounted || _streamEnded) return;
    _reconnecting = true;
    _heartbeat?.cancel();
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      _reconnecting = false;
      _sub?.cancel();
      try {
        _channel?.sink.close();
      } catch (_) {}
      _connectWS();
    });
  }

  void _sendMessage() {
    final content = _inputCtrl.text.trim();
    if (content.isEmpty) return;
    try {
      _channel?.sink.add(jsonEncode({'type': 'message', 'content': content}));
      _inputCtrl.clear();
    } catch (_) {}
  }

  void _showHistory() {
    final history = List<ChatMessage>.from(_history.reversed);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HistorySheet(history: history),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _messages.length > 6
        ? _messages.sublist(_messages.length - 6)
        : _messages;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (visible.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: visible
                  .map(
                    (m) => ValueListenableBuilder<double>(
                      valueListenable: m.opacity,
                      builder: (_, op, __) => AnimatedOpacity(
                        opacity: op,
                        duration: const Duration(milliseconds: 700),
                        child: _MessageItem(
                          m.message,
                          onUsernameTap: widget.onUsernameTap,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        if (_token != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                // History button
                if (_history.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      key: const Key('chat_panel_btn_gecmis'),
                      onTap: _showHistory,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0x88000000),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.history_rounded,
                            color: Colors.white70, size: 18),
                      ),
                    ),
                  ),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: _inputFocused
                          ? const Color(0xCC000000)
                          : const Color(0x88000000),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _inputFocused
                            ? Colors.white38
                            : Colors.transparent,
                      ),
                    ),
                    child: TextField(
                      key: const Key('chat_panel_input_mesaj'),
                      controller: _inputCtrl,
                      focusNode: _focusNode,
                      enabled: !_selfMuted,
                      style: TextStyle(
                          color: _selfMuted ? Colors.white38 : Colors.white,
                          fontSize: 13),
                      maxLength: 200,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: _selfMuted
                            ? '🔇 Susturuldunuz'
                            : 'Mesaj yaz...',
                        hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 12),
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  key: const Key('chat_panel_btn_gonder'),
                  onTap: _selfMuted ? null : _sendMessage,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _selfMuted
                          ? const Color(0x44000000)
                          : kPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send_rounded,
                        color: _selfMuted
                            ? Colors.white24
                            : Colors.white,
                        size: 16),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HistorySheet extends StatelessWidget {
  final List<ChatMessage> history;

  const _HistorySheet({required this.history});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xF0111827),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded,
                      color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Sohbet Geçmişi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Son ${history.length} mesaj',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // Messages
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                itemCount: history.length,
                itemBuilder: (_, i) {
                  final msg = history[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: _ChatAvatar(
                              username: msg.username,
                              imageUrl: msg.profileImageUrl,
                            ),
                          ),
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: SizedBox(width: 4),
                          ),
                          TextSpan(
                            text: '@${msg.username} ',
                            style: TextStyle(
                              fontSize: 13,
                              color: usernameColor(msg.username),
                              fontWeight: FontWeight.w700,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PublicProfileScreen(
                                        username: msg.username),
                                  ),
                                );
                              },
                          ),
                          TextSpan(
                            text: msg.content,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Relative URL'leri (/uploads/...) tam URL'ye çevirir.
/// Diğer ekranlarla aynı mantık: kBaseUrl'den origin alınır.
String _resolveImageUrl(String url) {
  if (url.startsWith('http')) return url;
  final origin = kBaseUrl.replaceFirst(RegExp(r'/api.*'), '');
  return '$origin$url';
}

/// Satır içi avatar: 18×18 yuvarlak resim, OOM korumalı (memCache 60×60).
/// URL null/boş veya hata durumunda kullanıcı baş harfini gösterir.
class _ChatAvatar extends StatelessWidget {
  final String username;
  final String? imageUrl;
  static const double _size = 18;

  const _ChatAvatar({required this.username, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final color = usernameColor(username);
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    final fallback = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 8,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: _resolveImageUrl(imageUrl!),
        width: _size,
        height: _size,
        memCacheWidth: 60,
        memCacheHeight: 60,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  final ChatMessage message;
  final void Function(String username)? onUsernameTap;

  const _MessageItem(this.message, {this.onUsernameTap});

  @override
  Widget build(BuildContext context) {
    const shadow = [
      Shadow(blurRadius: 6, color: Colors.black),
      Shadow(blurRadius: 12, color: Colors.black),
    ];

    // Sistem mesajları (katılma bildirimi): avatar yok, italik stil
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Wrap(
          children: [
            Text(
              '@${message.username} ',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: usernameColor(message.username),
                fontWeight: FontWeight.w700,
                shadows: shadow,
              ),
            ),
            Text(
              message.content,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.white54,
                fontStyle: FontStyle.italic,
                shadows: shadow,
              ),
            ),
          ],
        ),
      );
    }

    // Normal mesaj: avatar + kullanıcı adı + içerik — Text.rich ile satır
    // yüksekliği bozulmadan hizalama sağlanır (PlaceholderAlignment.middle).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _ChatAvatar(
                username: message.username,
                imageUrl: message.profileImageUrl,
              ),
            ),
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox(width: 4),
            ),
            TextSpan(
              text: '@${message.username} ',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: usernameColor(message.username),
                fontWeight: FontWeight.w700,
                shadows: shadow,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = onUsernameTap != null
                    ? () => onUsernameTap!(message.username)
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PublicProfileScreen(username: message.username),
                          ),
                        ),
            ),
            TextSpan(
              text: message.content,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.white,
                shadows: shadow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
