import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/message.dart';
import '../../../core/providers/auth_provider.dart';

final conversationsProvider =
    FutureProvider<List<ConversationModel>>((ref) async {
  ref.watch(authProvider); // React to auth state changes (login/logout)
  final res = await ApiClient().get(Endpoints.conversations);
  final list = res.data as List<dynamic>;
  return list
      .map((e) => ConversationModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convAsync = ref.watch(conversationsProvider);
    final currentUserId = ref.watch(authProvider).user?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Mesajlar')),
      body: convAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (convs) => convs.isEmpty
            ? const Center(child: Text('Henüz mesajınız yok.'))
            : RefreshIndicator(
                onRefresh: () => ref.refresh(conversationsProvider.future),
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
                            ),
                          Text(
                            lastMsg?.content ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF9AAAB8)),
                          ),
                        ],
                      ),
                      trailing: Column(
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
                      onTap: () => context.push('/messages/${conv.id}'),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
