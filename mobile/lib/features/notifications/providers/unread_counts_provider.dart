import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/endpoints.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import '../../../core/providers/auth_provider.dart';

class UnreadCounts {
  final int messages;
  final int notifications;

  UnreadCounts({required this.messages, required this.notifications});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnreadCounts &&
          runtimeType == other.runtimeType &&
          messages == other.messages &&
          notifications == other.notifications;

  @override
  int get hashCode => messages.hashCode ^ notifications.hashCode;
}

class UnreadCountsNotifier extends AsyncNotifier<UnreadCounts> {
  Timer? _timer;

  @override
  FutureOr<UnreadCounts> build() async {
    // Only start polling if authenticated
    final auth = ref.watch(authProvider);
    
    _timer?.cancel();
    if (auth.isAuthenticated) {
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (state.hasValue &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          refresh();
        }
      });
    }

    ref.onDispose(() {
      _timer?.cancel();
    });

    return _fetch();
  }

  Future<UnreadCounts> _fetch() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final notificationsRes = await ApiClient().get(Endpoints.notifications, params: {'_t': timestamp});
      final messagesRes = await ApiClient().get(Endpoints.messagesUnread, params: {'_t': timestamp});

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

      debugPrint('[API] Unread Counts Fetched: Messages: $unreadMessages, Notifications: $unreadNotifications (Poll)');

      return UnreadCounts(
        messages: unreadMessages,
        notifications: unreadNotifications,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return UnreadCounts(messages: 0, notifications: 0);
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    debugPrint('[SYNC] Provider refresh() called manually or via timer');
    // Using copyWithPrevious ensures the old data is still available while loading
    state = const AsyncLoading<UnreadCounts>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _fetch());
  }
}

final unreadCountsProvider =
    AsyncNotifierProvider<UnreadCountsNotifier, UnreadCounts>(() {
  return UnreadCountsNotifier();
});
