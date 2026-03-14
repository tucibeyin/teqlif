import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../config/theme.dart';
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

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
  String? _token;

  @override
  void initState() {
    super.initState();
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mesaj listesi
          if (_messages.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                controller: _scrollCtrl,
                shrinkWrap: true,
                itemCount: _messages.length,
                itemBuilder: (_, i) => _MessageItem(_messages[i]),
              ),
            ),
          const SizedBox(height: 6),
          // Input satırı
          if (_token != null)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13),
                    maxLength: 200,
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Mesaj yaz...',
                      hintStyle: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 12),
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0x99000000),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: kPrimary,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 17),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  final ChatMessage message;

  const _MessageItem(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, height: 1.3),
          children: [
            TextSpan(
              text: '@${message.username} ',
              style: const TextStyle(
                color: Color(0xFF60A5FA),
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
            TextSpan(
              text: message.content,
              style: const TextStyle(
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
