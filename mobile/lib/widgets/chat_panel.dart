import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../models/chat.dart';
import '../services/storage_service.dart';

class ChatPanel extends StatefulWidget {
  final int streamId;

  const ChatPanel({super.key, required this.streamId});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<ChatMessage> _messages = [];
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
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
    if (mounted) _connectWS();
  }

  @override
  void dispose() {
    _reconnecting = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _wsBaseUrl {
    return kBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
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
              setState(() {
                _messages.add(ChatMessage.fromJson(json));
                if (_messages.length > 50) _messages.removeAt(0);
              });
              _scrollToBottom();
            } else if (json['type'] == 'history') {
              final msgs = (json['messages'] as List)
                  .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                  .toList();
              setState(() => _messages.addAll(msgs));
              _scrollToBottom();
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
    if (_reconnecting || !mounted) return;
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
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

  @override
  Widget build(BuildContext context) {
    // Son 6 mesajı göster (daha fazlası videoyu kapatır)
    final visibleMessages = _messages.length > 6
        ? _messages.sublist(_messages.length - 6)
        : _messages;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mesaj listesi — sol tarafa yaslı, transparan
        if (visibleMessages.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 180),
            child: ListView.builder(
              controller: _scrollCtrl,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              itemCount: visibleMessages.length,
              itemBuilder: (_, i) => _MessageItem(visibleMessages[i]),
            ),
          ),

        // Input satırı
        if (_token != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
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
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLength: 200,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Mesaj yaz...',
                        hintStyle:
                            TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0D9488),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MessageItem extends StatelessWidget {
  final ChatMessage message;

  const _MessageItem(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12.5, height: 1.35),
          children: [
            TextSpan(
              text: '@${message.username} ',
              style: const TextStyle(
                color: Color(0xFF60A5FA),
                fontWeight: FontWeight.w700,
                shadows: [
                  Shadow(blurRadius: 6, color: Colors.black),
                  Shadow(blurRadius: 12, color: Colors.black),
                ],
              ),
            ),
            TextSpan(
              text: message.content,
              style: const TextStyle(
                color: Colors.white,
                shadows: [
                  Shadow(blurRadius: 6, color: Colors.black),
                  Shadow(blurRadius: 12, color: Colors.black),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
