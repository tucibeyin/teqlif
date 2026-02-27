import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
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
  final _scrollCtrl = ScrollController();
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
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool instant = false}) {
    // Proactively call multiple times to handle laggy frame updates
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 50), () {
        if (mounted && _scrollCtrl.hasClients) {
          if (instant) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          } else {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      });
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
                return ListView.builder(
                  controller: _scrollCtrl,
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
