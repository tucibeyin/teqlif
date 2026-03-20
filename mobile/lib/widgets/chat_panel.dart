import 'dart:async';
import 'dart:convert';
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
    if (!_permanent) opacity.dispose();
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
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            if (json['type'] == 'message') {
              _addMessage(ChatMessage.fromJson(json));
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
              widget.onStreamEnded?.call();
            } else if (json['type'] == 'muted') {
              if (mounted) setState(() => _selfMuted = true);
              widget.onMuted?.call();
            } else if (json['type'] == 'unmuted') {
              if (mounted) setState(() => _selfMuted = false);
              widget.onUnmuted?.call();
            } else if (json['type'] == 'kicked') {
              _streamEnded = true; // yeniden bağlanmayı engelle
              widget.onKicked?.call();
            }
          } catch (_) {}
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
                  final color = usernameColor(msg.username);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Wrap(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(
                                    username: msg.username),
                              ),
                            );
                          },
                          child: Text(
                            '@${msg.username} ',
                            style: TextStyle(
                              fontSize: 13,
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          msg.content,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        children: [
          GestureDetector(
            onTap: onUsernameTap != null
                ? () => onUsernameTap!(message.username)
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PublicProfileScreen(username: message.username),
                      ),
                    ),
            child: Text(
              '@${message.username} ',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: usernameColor(message.username),
                fontWeight: FontWeight.w700,
                shadows: shadow,
              ),
            ),
          ),
          Text(
            message.content,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Colors.white,
              shadows: shadow,
            ),
          ),
        ],
      ),
    );
  }
}
