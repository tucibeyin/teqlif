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

class ConversationsNotifier extends AsyncNotifier<List<ConversationModel>> {
  @override
  Future<List<ConversationModel>> build() async {
    ref.watch(authProvider); // React to auth state changes
    return _fetchConversations();
  }

  Future<List<ConversationModel>> _fetchConversations() async {
    final res = await ApiClient().get(Endpoints.conversations);
    final list = res.data as List<dynamic>;
    return list
        .map((e) => ConversationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  bool updateShouldNotify(AsyncValue<List<ConversationModel>> previous, AsyncValue<List<ConversationModel>> next) {
    // Always force the UI to rebuild when a refresh occurs, 
    // bypassing deep equality checks that might swallow updates 
    // where only inner fields (like lastMessage) changed.
    return true;
  }

  Future<void> refresh() async {
    // Refresh without destroying the current UI state
    state = const AsyncValue.loading();
    try {
      final newConversations = await _fetchConversations();
      // Yielding a completely fresh list instance guarantees reference inequality
      state = AsyncValue.data(List.from(newConversations));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<ConversationModel>>(() {
  return ConversationsNotifier();
});

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh instantly when entering the tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(conversationsProvider.notifier).refresh();
      }
    });
    // Continuous polling fallback every 10 seconds while the screen is active
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.read(conversationsProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final convAsync = ref.watch(conversationsProvider);
    final currentUserId = ref.watch(authProvider).user?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Mesajlar')),
      body: convAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (convs) => convs.isEmpty
            ? const Center(child: Text('Henüz mesajınız yok.'))
            : RefreshIndicator(
                onRefresh: () async {
                  await ref.read(conversationsProvider.notifier).refresh();
                },
                child: ListView.builder(
                  itemCount: convs.length,
                  itemBuilder: (_, i) {
                    final conv = convs[i];
                    final other = conv.otherUser(currentUserId);
                    final lastMsg = conv.lastMessage;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF00B4CC),
                        child: Text(
                          (other?.name ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(other?.name ?? 'Kullanıcı',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (conv.ad != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                'İlan: ${conv.ad!.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF00B4CC),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(bottom: 2),
                              child: Text(
                                'İlan silinmiştir',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFF9AAAB8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          Text(
                            lastMsg?.content ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF9AAAB8)),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (lastMsg != null)
                                Text(
                                  timeago.format(lastMsg.createdAt, locale: 'tr'),
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF9AAAB8)),
                                ),
                              if (conv.unreadCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00B4CC),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    '${conv.unreadCount}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 10),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Sohbeti Sil'),
                                  content: const Text(
                                      'Bu sohbeti kalıcı olarak silmek istediğinizden emin misiniz?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('İptal'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Sil',
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ApiClient().delete(
                                    '/api/conversations/${conv.id}');
                                ref.read(conversationsProvider.notifier).refresh();
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () async {
                        await context.push('/messages/${conv.id}');
                        // Refresh both the list and the bottom tab badges when returning
                        ref.read(conversationsProvider.notifier).refresh();
                        ref.read(unreadCountsProvider.notifier).refresh();
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }
}
