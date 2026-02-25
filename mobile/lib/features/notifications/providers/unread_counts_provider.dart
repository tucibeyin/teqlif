import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/endpoints.dart';

class UnreadCounts {
  final int messages;
  final int notifications;

  UnreadCounts({required this.messages, required this.notifications});
}

class UnreadCountsNotifier extends StateNotifier<AsyncValue<UnreadCounts>> {
  UnreadCountsNotifier() : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      state = const AsyncValue.loading();
      final notificationsRes = await ApiClient().get(Endpoints.notifications);
      final messagesRes = await ApiClient().get(Endpoints.unreadMessages);

      int unreadNotifications = 0;
      if (notificationsRes.data is List) {
        unreadNotifications = (notificationsRes.data as List)
            .where((n) => n['isRead'] == false)
            .length;
      }

      int unreadMessages = 0;
      if (messagesRes.data != null && messagesRes.data['count'] != null) {
        unreadMessages = messagesRes.data['count'] as int;
      }

      state = AsyncValue.data(UnreadCounts(
        messages: unreadMessages,
        notifications: unreadNotifications,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final unreadCountsProvider =
    StateNotifierProvider<UnreadCountsNotifier, AsyncValue<UnreadCounts>>((ref) {
  return UnreadCountsNotifier();
});
