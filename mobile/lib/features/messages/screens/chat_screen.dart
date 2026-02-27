import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/message.dart';
import '../../../core/providers/auth_provider.dart';
import '../../notifications/providers/unread_counts_provider.dart';
import 'conversations_screen.dart';

final singleConversationProvider =
    FutureProvider.family<ConversationModel, String>((ref, id) async {
  final res = await ApiClient().get('${Endpoints.conversations}/$id');
  return ConversationModel.fromJson(res.data as Map<String, dynamic>);
});

final chatMessagesProvider =
    FutureProvider.family<List<MessageModel>, String>((ref, conversationId) async {
  final res = await ApiClient().get(Endpoints.messages,
      params: {'conversationId': conversationId, 'read': 'true'});
  final list = res.data as List<dynamic>;
  // Reverse the list so the latest messages (bottom) are at index 0
  return list
      .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
      .toList()
      .reversed
      .toList();
});

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

// Tracks the currently opened conversation ID, so push notifications
// know whether to refresh this specific chat screen or just show an OS popup.
final activeChatIdProvider = StateProvider<String?>((ref) => null);

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final ItemScrollController _itemScrollCtrl = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  bool _sending = false;
  bool _isFirstLoad = true;
  Timer? _pollTimer;
  MessageModel? _replyingTo;

  // Capture notifiers in initState so we don't need to use 'ref' in dispose()
  // after the widget/element might already be defunct.
  late StateController<String?> _activeChatNotifier;
  late UnreadCountsNotifier _countsNotifier;
  late ConversationsNotifier _convsNotifier;

  @override
  void initState() {
    super.initState();
    _activeChatNotifier = ref.read(activeChatIdProvider.notifier);
    _countsNotifier = ref.read(unreadCountsProvider.notifier);
    _convsNotifier = ref.read(conversationsProvider.notifier);

    // Mark this chat as active so push notifications can silent-refresh it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _activeChatNotifier.state = widget.conversationId;
        // Immediate badge refresh when entering the chat
        _countsNotifier.refresh();
      }
    });
    // Poll for new incoming messages every 5 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.invalidate(chatMessagesProvider(widget.conversationId));
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // Use the captured notifiers. We use addPostFrameCallback to ensure 
    // we don't update state during the build/dispose phase itself if possible,
    // although for these specific side effects it's mostly about safety.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeChatNotifier.state = null;
      // Immediate badge refresh when leaving the chat
      _countsNotifier.refresh();
      _convsNotifier.refresh();
    });
    _msgCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool instant = false}) {
    if (!_itemScrollCtrl.isAttached) return;
    if (instant) {
      _itemScrollCtrl.jumpTo(index: 0);
    } else {
      _itemScrollCtrl.scrollTo(
        index: 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToMessage(String messageId, List<MessageModel> messages) {
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1 && _itemScrollCtrl.isAttached) {
      _itemScrollCtrl.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        alignment: 0.5, // Center the message
      );
      // Highlight effect logic will be in the message bubble itself
    }
  }

  Future<void> _send() async {
    final conv = ref.read(singleConversationProvider(widget.conversationId)).value;
    if (conv == null) return;
    
    final currentUserId = ref.read(authProvider).user?.id ?? '';
    final recipientId = conv.otherUser(currentUserId)?.id;
    if (recipientId == null) return;

    final content = _msgCtrl.text.trim();
    if (content.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ApiClient().post(Endpoints.messages, data: {
        'conversationId': widget.conversationId,
        'content': content,
        'recipientId': recipientId,
        'parentMessageId': _replyingTo?.id,
      });
      _msgCtrl.clear();
      setState(() => _replyingTo = null);
      ref.invalidate(chatMessagesProvider(widget.conversationId));
      // Also refresh the conversations list so last message updates immediately
      ref.invalidate(conversationsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mesaj gönderilemedi.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authProvider).user?.id ?? '';
    final convAsync =
        ref.watch(singleConversationProvider(widget.conversationId));
    final messagesAsync = ref.watch(chatMessagesProvider(widget.conversationId));

    // Listen for incoming messages and scroll down automatically
    ref.listen<AsyncValue<List<MessageModel>>>(
      chatMessagesProvider(widget.conversationId),
      (_, next) {
        // With reverse: true, we don't need manual scrolling logic 
        // as new messages (index 0) naturally appear at the bottom
      },
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/messages');
            }
          },
        ),
        title: convAsync.when(
          data: (conv) {
            final other = conv.otherUser(currentUserId);
            return Text(other?.name ?? 'Sohbet');
          },
          loading: () => const Text('Yükleniyor...'),
          error: (_, __) => const Text('Sohbet'),
        ),
      ),
      body: Column(
        children: [
          convAsync.when(
            data: (conv) {
              if (conv.ad == null) {
                return Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    border:
                        Border(bottom: BorderSide(color: Color(0xFFE2EBF0))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: Color(0xFF9AAAB8)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bu ilan yayından kaldırılmıştır.',
                          style: const TextStyle(
                            color: Color(0xFF9AAAB8),
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return GestureDetector(
                onTap: () => context.push('/ad/${conv.ad!.id}'),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F7FA),
                    border:
                        Border(bottom: BorderSide(color: Color(0xFFE2EBF0))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sell_outlined,
                          size: 18, color: Color(0xFF00B4CC)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'İlan: ${conv.ad!.title}',
                          style: const TextStyle(
                            color: Color(0xFF00B4CC),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 18, color: Color(0xFF00B4CC)),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text('Henüz mesaj yok.'));
                }
                return ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollCtrl,
                  itemPositionsListener: _itemPositionsListener,
                  reverse: true, // index 0 is at the bottom
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final isMine = msg.senderId == currentUserId;
                    return _SwipeableMessage(
                      message: msg,
                      isMine: isMine,
                      onReply: (m) => setState(() => _replyingTo = m),
                      onJumpTo: (id) => _jumpToMessage(id, messages),
                    );
                  },
                );
              },
            ),
          ),
          // Input bar or Read-Only Banner
          ...[
            convAsync.when(
              data: (conv) {
              final isSold = conv.ad?.status == 'SOLD';
              final isWinner = conv.ad?.winnerId == currentUserId;
              final isSeller = conv.ad?.userId == currentUserId;
              final isRestricted = isSold && !isWinner && !isSeller;

              if (conv.ad == null) {
                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                      top: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    border: Border(top: BorderSide(color: Color(0xFFE2EBF0))),
                  ),
                  child: const Text(
                    'Bu ilan yayından kaldırıldığı için mesaj gönderilemez.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF9AAAB8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }

              if (isRestricted) {
                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                      top: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    border: Border(top: BorderSide(color: Color(0xFFE2EBF0))),
                  ),
                  child: const Text(
                    'İlan satıldı. Mesajlaşma sadece alıcı ve satıcı için aktiftir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF9AAAB8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }

              return Container(
                padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                    top: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyingTo != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF9FAFB),
                          border: Border(bottom: BorderSide(color: Color(0xFFE2EBF0))),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.reply, size: 16, color: Color(0xFF00B4CC)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  final msgs = ref.read(chatMessagesProvider(widget.conversationId)).value ?? [];
                                  _jumpToMessage(_replyingTo!.id, msgs);
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _replyingTo!.sender?.name ?? 'Kullanıcı',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: Color(0xFF00B4CC),
                                      ),
                                    ),
                                    Text(
                                      _replyingTo!.content,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9AAAB8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() => _replyingTo = null),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                      child: TextField(
                        controller: _msgCtrl,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Mesajınızı yazın...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send),
                      style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF00B4CC)),
                      ),
                    ],
                  ),
                ],
              ),
            );
              },
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwipeableMessage extends StatefulWidget {
  final MessageModel message;
  final bool isMine;
  final Function(MessageModel) onReply;
  final Function(String) onJumpTo;

  const _SwipeableMessage({
    required this.message,
    required this.isMine,
    required this.onReply,
    required this.onJumpTo,
  });

  @override
  State<_SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<_SwipeableMessage> with SingleTickerProviderStateMixin {
  double _offset = 0.0;
  bool _triggered = false;
  late AnimationController _highlightCtrl;
  late Animation<Color?> _highlightAnim;

  @override
  void initState() {
    super.initState();
    _highlightCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _highlightAnim = ColorTween(
      begin: Colors.transparent,
      end: const Color(0xFF00B4CC).withOpacity(0.2),
    ).animate(CurvedAnimation(parent: _highlightCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _highlightCtrl.dispose();
    super.dispose();
  }

  void _runHighlight() {
    _highlightCtrl.forward().then((_) => _highlightCtrl.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx > 0) {
          setState(() {
            _offset += details.delta.dx;
            if (_offset > 60 && !_triggered) {
              _triggered = true;
              widget.onReply(widget.message);
            }
          });
        }
      },
      onHorizontalDragEnd: (details) {
        setState(() {
          _offset = 0.0;
          _triggered = false;
        });
      },
      onHorizontalDragCancel: () {
        setState(() {
          _offset = 0.0;
          _triggered = false;
        });
      },
      child: Transform.translate(
        offset: Offset(_offset > 70 ? 70 : _offset, 0),
        child: AnimatedBuilder(
          animation: _highlightAnim,
          builder: (context, child) {
            return Container(
              color: _highlightAnim.value,
              child: child,
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_offset > 10)
                Positioned(
                  left: -40,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(
                      Icons.reply,
                      color: const Color(0xFF00B4CC).withOpacity((_offset / 60).clamp(0.0, 1.0)),
                      size: 24,
                    ),
                  ),
                ),
              Align(
                alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72),
                  decoration: BoxDecoration(
                    color: widget.isMine
                        ? const Color(0xFF00B4CC)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(widget.isMine ? 16 : 4),
                      bottomRight: Radius.circular(widget.isMine ? 4 : 16),
                    ),
                    border: widget.isMine
                        ? null
                        : Border.all(color: const Color(0xFFE2EBF0)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 4),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: widget.isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (widget.message.parentMessage != null)
                        GestureDetector(
                          onTap: () => widget.onJumpTo(widget.message.parentMessage!.id),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: widget.isMine
                                  ? Colors.white.withOpacity(0.15)
                                  : const Color(0xFFF4F7FA),
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(
                                  color: widget.isMine ? Colors.white : const Color(0xFF00B4CC),
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.message.parentMessage!.sender?.name ?? 'Kullanıcı',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: widget.isMine ? Colors.white : const Color(0xFF00B4CC),
                                  ),
                                ),
                                Text(
                                  widget.message.parentMessage!.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: widget.isMine ? Colors.white.withOpacity(0.9) : const Color(0xFF9AAAB8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        widget.message.content,
                        style: TextStyle(
                          color:
                              widget.isMine ? Colors.white : const Color(0xFF0F1923),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeago.format(widget.message.createdAt, locale: 'tr'),
                        style: TextStyle(
                          color: widget.isMine
                              ? Colors.white.withOpacity(0.7)
                              : const Color(0xFF9AAAB8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
