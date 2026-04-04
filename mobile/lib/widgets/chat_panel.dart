import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
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
  /// Tüm izleyicilere broadcast — birisi moderatör yapıldı (rozet gösterimi için).
  final void Function(String targetUsername, String promotedBy)? onModPromoted;
  /// Tüm izleyicilere broadcast — birinin moderatörlüğü kaldırıldı.
  final void Function(String targetUsername, String demotedBy)? onModDemoted;

  /// Sadece bu kullanıcıya hedefli — BEN moderatör yapıldım.
  final void Function(String promotedBy)? onModPromotedSelf;
  /// Sadece bu kullanıcıya hedefli — benim moderatörlüğüm kaldırıldı.
  final void Function(String demotedBy)? onModDemotedSelf;

  /// Yeniden bağlanmada sessizce moderatör statüsü geri yüklendi (bildirim yok).
  final VoidCallback? onModRestored;

  /// Bir izleyici kalp gönderdiğinde tetiklenir (`stream_like` WS sinyali).
  /// [userId] ve [username] gönderen kişiyi içerir.
  final void Function(int userId, String username)? onStreamLike;

  /// Host, birini sahneye davet ettiğinde tüm odaya gelir.
  /// [hostUsername] daveti gönderen host, [targetUsername] davet edilen kullanıcı.
  final void Function(String hostUsername, String targetUsername)? onCoHostInvite;

  /// Host, sahnedeki konuğu kaldırdığında tüm odaya gelir.
  final void Function(String targetUsername)? onCoHostRemoved;

  /// true ise pin banner mesaj input'unun altında gösterilir (host ekranı için).
  final bool pinAtBottom;

  /// true ise pin banner'da ✕ kapat butonu gösterilir (sadece host).
  final bool pinDismissible;

  /// Input row'unun en sağına eklenen widget — token kontrolünden bağımsız,
  /// her zaman render edilir (ör. viewer kalp butonu).
  final Widget? trailingAction;

  const ChatPanel({
    super.key,
    required this.streamId,
    this.onStreamEnded,
    this.onViewerCountChanged,
    this.onUsernameTap,
    this.onMuted,
    this.onUnmuted,
    this.onKicked,
    this.onModPromoted,
    this.onModDemoted,
    this.onModPromotedSelf,
    this.onModDemotedSelf,
    this.onModRestored,
    this.onStreamLike,
    this.pinAtBottom = false,
    this.pinDismissible = false,
    this.trailingAction,
    this.onCoHostInvite,
    this.onCoHostRemoved,
  });

  @override
  State<ChatPanel> createState() => ChatPanelState();
}

class ChatPanelState extends State<ChatPanel> {
  final List<_TimedMessage> _messages = [];
  final List<ChatMessage> _history = []; // last 50 messages
  final _inputCtrl = TextEditingController();
  final _inputScrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _autoScroll = true; // kullanıcı yukarı kaydırınca false olur
  bool _selfMuted = false;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
  bool _streamEnded = false;
  String? _token;
  int? _myUserId;
  bool _inputFocused = false;

  // ── Sabitlenen mesaj ──────────────────────────────────────────────────────
  String? _pinnedMessage;

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
    final info = await StorageService.getUserInfo();
    _myUserId = info?['id'] as int?;
    debugPrint('[CHAT] _init tamamlandı — myUserId:$_myUserId');
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
    _inputScrollCtrl.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      // reverse:true'da "en alt" (en yeni mesaj) = minScrollExtent (0.0)
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
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
        return idx < _messages.length - 5;
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
    _scrollToBottom();
  }

  /// Yeni mesaj gelince: _permanent işaretli ama artık son 3'te olmayan
  /// mesajları fade-out yaparak listeden temizler.
  void _evictStalePermanents() {
    final toEvict = <_TimedMessage>[];
    final protectedStart = _messages.length - 5;
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
            } else if (json['type'] == 'mod_promoted') {
              final target   = json['username'] as String? ?? '';
              final by       = json['promoted_by'] as String? ?? '';
              final targetId = (json['user_id'] as num?)?.toInt();
              _eventType = 'mod_promoted:$target:$by';
              // user_id eşleşirse hedefli self eventi tetikle (backend deploy beklenmeden)
              if (_myUserId != null && targetId != null && targetId == _myUserId) {
                debugPrint('[CHAT] mod_promoted self-match via user_id=$targetId');
                _eventType = 'mod_promoted_self:$by';
              }
            } else if (json['type'] == 'mod_demoted') {
              final target   = json['username'] as String? ?? '';
              final by       = json['demoted_by'] as String? ?? '';
              final targetId = (json['user_id'] as num?)?.toInt();
              _eventType = 'mod_demoted:$target:$by';
              if (_myUserId != null && targetId != null && targetId == _myUserId) {
                debugPrint('[CHAT] mod_demoted self-match via user_id=$targetId');
                _eventType = 'mod_demoted_self:$by';
              }
            } else if (json['type'] == 'mod_status') {
              // Yeniden bağlanmada mevcut mod durumu — sessiz geri yükleme
              final isMod = json['is_mod'] as bool? ?? false;
              if (isMod) _eventType = 'mod_status_restored';
            } else if (json['type'] == 'mod_promoted_self') {
              // Hedefli event — sadece atanan kullanıcı alır
              final by = json['promoted_by'] as String? ?? '';
              _eventType = 'mod_promoted_self:$by';
            } else if (json['type'] == 'mod_demoted_self') {
              // Hedefli event — sadece etkilenen kullanıcı alır
              final by = json['demoted_by'] as String? ?? '';
              _eventType = 'mod_demoted_self:$by';
            } else if (json['type'] == 'host_pin') {
              final content = json['content'] as String? ?? '';
              if (mounted) {
                // Boş string = sabiti kaldır; dolu string = sabitle
                setState(() => _pinnedMessage = content.isEmpty ? null : content);
              }
            } else if (json['type'] == 'stream_like') {
              final likeUserId = (json['user_id'] as num?)?.toInt() ?? 0;
              final likeUsername = json['username'] as String? ?? '';
              // Kendi gönderdiğimiz kalpleri tekrar gösterme
              if (_myUserId == null || likeUserId != _myUserId) {
                _eventType = 'stream_like:$likeUserId:$likeUsername';
              }
            } else if (json['type'] == 'cohost_invite') {
              final hostUsername   = json['host_username'] as String? ?? '';
              final targetUsername = json['target_username'] as String? ?? '';
              _eventType = 'cohost_invite:$hostUsername:$targetUsername';
            } else if (json['type'] == 'cohost_removed') {
              final targetUsername = json['target_username'] as String? ?? '';
              _eventType = 'cohost_removed:$targetUsername';
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
          if (_eventType != null && _eventType!.startsWith('mod_promoted:')) {
            final rest  = _eventType!.substring('mod_promoted:'.length);
            final colon = rest.indexOf(':');
            final targetUsername = colon >= 0 ? rest.substring(0, colon) : rest;
            final promotedBy     = colon >= 0 ? rest.substring(colon + 1) : '';
            debugPrint('[CHAT] mod_promoted — target:$targetUsername promotedBy:$promotedBy myUserId:$_myUserId');
            widget.onModPromoted?.call(targetUsername, promotedBy);
          }
          if (_eventType != null && _eventType!.startsWith('mod_demoted:')) {
            final rest  = _eventType!.substring('mod_demoted:'.length);
            final colon = rest.indexOf(':');
            final targetUsername = colon >= 0 ? rest.substring(0, colon) : rest;
            final demotedBy      = colon >= 0 ? rest.substring(colon + 1) : '';
            debugPrint('[CHAT] mod_demoted — target:$targetUsername demotedBy:$demotedBy myUserId:$_myUserId');
            widget.onModDemoted?.call(targetUsername, demotedBy);
          }
          if (_eventType == 'mod_status_restored') {
            debugPrint('[CHAT] mod_status_restored — sessiz geri yükleme');
            widget.onModRestored?.call();
          }
          if (_eventType != null && _eventType!.startsWith('mod_promoted_self:')) {
            final promotedBy = _eventType!.substring('mod_promoted_self:'.length);
            debugPrint('[CHAT] mod_promoted_self — promotedBy:$promotedBy | onModPromotedSelf null:${widget.onModPromotedSelf == null}');
            widget.onModPromotedSelf?.call(promotedBy);
            debugPrint('[CHAT] mod_promoted_self — callback çağrısı tamamlandı');
          }
          if (_eventType != null && _eventType!.startsWith('mod_demoted_self:')) {
            final demotedBy = _eventType!.substring('mod_demoted_self:'.length);
            debugPrint('[CHAT] mod_demoted_self — demotedBy:$demotedBy');
            widget.onModDemotedSelf?.call(demotedBy);
          }
          if (_eventType != null && _eventType!.startsWith('stream_like:')) {
            final rest = _eventType!.substring('stream_like:'.length);
            final colon = rest.indexOf(':');
            final likeUserId = colon >= 0 ? int.tryParse(rest.substring(0, colon)) ?? 0 : 0;
            final likeUsername = colon >= 0 ? rest.substring(colon + 1) : '';
            widget.onStreamLike?.call(likeUserId, likeUsername);
          }
          if (_eventType != null && _eventType!.startsWith('cohost_invite:')) {
            final rest  = _eventType!.substring('cohost_invite:'.length);
            final colon = rest.indexOf(':');
            final hostUsername   = colon >= 0 ? rest.substring(0, colon) : rest;
            final targetUsername = colon >= 0 ? rest.substring(colon + 1) : '';
            widget.onCoHostInvite?.call(hostUsername, targetUsername);
          }
          if (_eventType != null && _eventType!.startsWith('cohost_removed:')) {
            final targetUsername = _eventType!.substring('cohost_removed:'.length);
            widget.onCoHostRemoved?.call(targetUsername);
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

  /// Host tarafından çağrılır — sabitlenen mesajı tüm izleyicilere gönderir.
  void sendHostPin(String content) {
    // Boş string = kaldır komutu, gönderilmeli
    try {
      _channel?.sink.add(jsonEncode({'type': 'host_pin', 'content': content.trim()}));
    } catch (_) {}
  }

  void _showHistory() {
    final history = List<ChatMessage>.from(_history.reversed);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black54,
      builder: (_) => _HistorySheet(history: history),
    );
  }

  Widget _buildPinBanner({required bool bottomMargin}) {
    return Container(
      margin: bottomMargin
          ? const EdgeInsets.fromLTRB(12, 4, 12, 0)
          : const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.55), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.push_pin_rounded, color: Colors.amber, size: 12),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _pinnedMessage!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 12, color: Colors.black)],
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.pinDismissible)
            GestureDetector(
              onTap: () => setState(() => _pinnedMessage = null),
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.close, color: Colors.white38, size: 14),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pinnedMessage != null && !widget.pinAtBottom)
          _buildPinBanner(bottomMargin: false),
        if (_history.isNotEmpty)
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollUpdateNotification) {
                final atBottom = _scrollController.hasClients &&
                    _scrollController.position.pixels <= 32;
                if (_autoScroll != atBottom) {
                  _autoScroll = atBottom;
                }
              }
              return false;
            },
            child: AnimatedContainer(
              // Yükseklik _messages.length'e göre dinamik:
              // Aktif chat → 6 satıra kadar büyür.
              // Mesajlar expire olunca 3'e küçülür (last-3 protected).
              // Her mesaj yaklaşık 22px, +4 ListView top padding.
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: _messages.length.clamp(5, 8) * 22.0 + 4.0,
              child: ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                // Scroll alanı: history'nin son 20'si
                itemCount: min(_history.length, 20),
                itemBuilder: (_, i) {
                  // i=0 → en yeni mesaj (reverse:true'da alta denk gelir)
                  final msg = _history[_history.length - 1 - i];
                  // Aktif timed mesajı bul (fade animasyonu için)
                  _TimedMessage? timed;
                  for (final t in _messages) {
                    if (t.message.id == msg.id) {
                      timed = t;
                      break;
                    }
                  }
                  if (timed != null) {
                    return ValueListenableBuilder<double>(
                      valueListenable: timed.opacity,
                      builder: (_, op, __) => AnimatedOpacity(
                        opacity: op,
                        duration: const Duration(milliseconds: 700),
                        child: _MessageItem(
                          msg,
                          onUsernameTap: widget.onUsernameTap,
                        ),
                      ),
                    );
                  }
                  return _MessageItem(
                    msg,
                    onUsernameTap: widget.onUsernameTap,
                  );
                },
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              if (_token != null) ...[
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
                      scrollController: _inputScrollCtrl,
                      focusNode: _focusNode,
                      enabled: !_selfMuted,
                      style: TextStyle(
                          color: _selfMuted ? Colors.white38 : Colors.white,
                          fontSize: 13),
                      maxLength: 200,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_inputScrollCtrl.hasClients) {
                            _inputScrollCtrl.jumpTo(
                                _inputScrollCtrl.position.maxScrollExtent);
                          }
                        });
                      },
                      decoration: InputDecoration(
                        hintText: _selfMuted
                            ? AppLocalizations.of(context)!.chatMutedHint
                            : AppLocalizations.of(context)!.chatMessageHint,
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
              // trailingAction her zaman görünür — token bağımsız
              if (widget.trailingAction != null) ...[
                const SizedBox(width: 8),
                widget.trailingAction!,
              ],
            ],
          ),
        ),
        if (_pinnedMessage != null && widget.pinAtBottom)
          _buildPinBanner(bottomMargin: true),
      ],
    );
  }
}

class _HistorySheet extends StatelessWidget {
  final List<ChatMessage> history;

  const _HistorySheet({required this.history});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
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
                  Text(
                    l.chatHistoryTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    l.chatHistoryCount(history.length),
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

    // Normal mesaj: avatar + rozet + kullanıcı adı + içerik
    final content = Padding(
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
            // Moderatör rozeti
            if (message.isMod)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '🛡 MOD',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: 0.3,
                        shadows: [],
                      ),
                    ),
                  ),
                ),
              ),
            // Host rozeti
            if (message.isHost)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '⚡ HOST',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: 0.3,
                        shadows: [],
                      ),
                    ),
                  ),
                ),
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

    if (!message.isAuctionResult) return content;

    // Açık artırma kazanan duyurusu — altın sol kenar + hafif vurgu
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x14FACC15),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: Color(0xFFFACC15), width: 3),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: content,
    );
  }
}
