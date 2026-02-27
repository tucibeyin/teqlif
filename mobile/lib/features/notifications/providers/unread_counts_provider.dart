import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/endpoints.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

class UnreadCounts {
  final int messages;
  final int notifications;

  UnreadCounts({required this.messages, required this.notifications});
}

class UnreadCountsNotifier extends StateNotifier<AsyncValue<UnreadCounts>> {
  final Ref ref;
  UnreadCountsNotifier(this.ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      if (!mounted) return;
      // If we already have a value, don't wipe it out. Emitting loading 
      // without copying the previous state causes the UI to flicker.
      if (!state.hasValue) {
        state = const AsyncValue.loading();
      }
      final notificationsRes = await ApiClient().get(Endpoints.notifications);
      final messagesRes = await ApiClient().get(Endpoints.messagesUnread);

      if (!mounted) return;
      
      int unreadNotifications = 0;
      if (notificationsRes.data != null && notificationsRes.data['unreadCount'] != null) {
        unreadNotifications = notificationsRes.data['unreadCount'] as int;
      }

      int unreadMessages = 0;
      if (messagesRes.data != null && messagesRes.data['unreadCount'] != null) {
        unreadMessages = messagesRes.data['unreadCount'] as int;
      }

      final totalUnread = unreadMessages + unreadNotifications;
      if (await FlutterAppBadger.isAppBadgeSupported()) {
        if (totalUnread > 0) {
          FlutterAppBadger.updateBadgeCount(totalUnread);
        } else {
          FlutterAppBadger.removeBadge();
        }
      }

      if (!mounted) return;

      state = AsyncValue.data(UnreadCounts(
        messages: unreadMessages,
        notifications: unreadNotifications,
      ));
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        // User not logged in, siliently return 0 counts
        state = AsyncValue.data(UnreadCounts(messages: 0, notifications: 0));
      } else {
        state = AsyncValue.error(e, e.stackTrace);
      }
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }
}

final unreadCountsProvider =
    StateNotifierProvider<UnreadCountsNotifier, AsyncValue<UnreadCounts>>((ref) {
  return UnreadCountsNotifier(ref);
});
