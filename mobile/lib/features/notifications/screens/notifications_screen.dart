import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/notification.dart';
import '../../../core/providers/auth_provider.dart';
import '../providers/notifications_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _typeIcon(String type) {
    switch (type) {
      case 'BID_RECEIVED':
        return Icons.gavel;
      case 'BID_ACCEPTED':
        return Icons.check_circle_outline;
      case 'NEW_MESSAGE':
        return Icons.message_outlined;
      default:
        return Icons.info_outline;
    }
  }

  String? _translateLink(String? link) {
    if (link == null) return null;
    if (link == '/') return '/home';
    if (link.startsWith('/dashboard/messages?conversationId=')) {
      final id = link.split('=')[1];
      return '/messages/$id';
    }
    return link; // Normal routes like /ad/XYZ
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            tooltip: 'Tümünü Sil',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Tümünü Sil'),
                  content: const Text(
                      'Tüm bildirimleri kalıcı olarak silmek istediğinize emin misiniz?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('İptal'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sil',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ApiClient().delete(Endpoints.notifications);
                ref.invalidate(notificationsProvider);
              }
            },
          ),
          TextButton(
            onPressed: () async {
              await ApiClient().patch(Endpoints.notifications);
              ref.invalidate(notificationsProvider);
              ref.read(unreadCountsProvider.notifier).refresh();
            },
            child: const Text('Tümünü Oku'),
          ),
        ],
      ),
      body: notifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (notifs) => notifs.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🔔', style: TextStyle(fontSize: 48)),
                    SizedBox(height: 12),
                    Text('Henüz bildiriminiz yok.',
                        style: TextStyle(color: Color(0xFF9AAAB8))),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(notificationsProvider.future),
                child: ListView.separated(
                  itemCount: notifs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = notifs[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: n.isRead
                            ? const Color(0xFFF4F7FA)
                            : const Color(0xFFE6F9FC),
                        child: Icon(
                          _typeIcon(n.type),
                          color: n.isRead
                              ? const Color(0xFF9AAAB8)
                              : const Color(0xFF00B4CC),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        n.message,
                        style: TextStyle(
                          fontWeight:
                              n.isRead ? FontWeight.w400 : FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        timeago.format(n.createdAt, locale: 'tr'),
                        style: const TextStyle(
                            color: Color(0xFF9AAAB8), fontSize: 12),
                      ),
                      tileColor: n.isRead
                          ? null
                          : const Color(0xFFE6F9FC).withOpacity(0.3),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                        onPressed: () async {
                            await ApiClient().delete('${Endpoints.notifications}?id=${n.id}');
                            ref.invalidate(notificationsProvider);
                        },
                      ),
                      onTap: n.link != null
                          ? () async {
                              if (!n.isRead) {
                                // Background API call to mark this single notification as read
                                ApiClient().patch(Endpoints.notifications,
                                    data: {'id': n.id}).then((_) {
                                  ref.invalidate(notificationsProvider);
                                });
                              }
                              final path = _translateLink(n.link);
                              if (path != null) {
                                context.push(path);
                              }
                            }
                          : null,
                    );
                  },
                ),
              ),
      ),
    );
  }
}
