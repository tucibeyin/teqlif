import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/storage_service.dart';
import '../../services/ws_service.dart';

// ─── Messages Screen View Model ──────────────────────────────────────────────

class MessagesUiState {
  final int unreadNotifs;
  const MessagesUiState({this.unreadNotifs = 0});
  
  MessagesUiState copyWith({int? unreadNotifs}) {
    return MessagesUiState(
      unreadNotifs: unreadNotifs ?? this.unreadNotifs,
    );
  }
}

class MessagesScreenViewModel extends AutoDisposeAsyncNotifier<MessagesUiState> {
  StreamSubscription<void>? _badgeSub;
  StreamSubscription<Map<String, dynamic>>? _fcmSub;

  @override
  FutureOr<MessagesUiState> build() async {
    _badgeSub = PushNotificationService.badgeRefreshNeeded.stream.listen((_) => _loadUnreadNotifs());
    _fcmSub = PushNotificationService.notificationStream.stream.listen((_) => _loadUnreadNotifs());
    
    ref.onDispose(() {
      _badgeSub?.cancel();
      _fcmSub?.cancel();
    });
    
    final count = await NotificationService.getUnreadNotifCount();
    return MessagesUiState(unreadNotifs: count);
  }

  Future<void> _loadUnreadNotifs() async {
    final count = await NotificationService.getUnreadNotifCount();
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(unreadNotifs: count));
    }
  }

  Future<void> markAllRead() async {
    await NotificationService.markAllRead();
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(unreadNotifs: 0));
      PushNotificationService.badgeRefreshNeeded.add(null);
    }
  }
}

final messagesScreenViewModelProvider = AutoDisposeAsyncNotifierProvider<MessagesScreenViewModel, MessagesUiState>(
  () => MessagesScreenViewModel(),
);

// ─── Messages Tab View Model ──────────────────────────────────────────────────

class ConversationsUiState {
  final List<dynamic> conversations;
  final bool loading;
  final bool hasError;
  final int? myUserId;

  const ConversationsUiState({
    this.conversations = const [],
    this.loading = true,
    this.hasError = false,
    this.myUserId,
  });

  ConversationsUiState copyWith({
    List<dynamic>? conversations,
    bool? loading,
    bool? hasError,
    int? myUserId,
  }) {
    return ConversationsUiState(
      conversations: conversations ?? this.conversations,
      loading: loading ?? this.loading,
      hasError: hasError ?? this.hasError,
      myUserId: myUserId ?? this.myUserId,
    );
  }
}

class MessagesTabViewModel extends AutoDisposeAsyncNotifier<ConversationsUiState> {
  StreamSubscription<Map<String, dynamic>>? _fcmSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _loadInProgress = false;

  @override
  FutureOr<ConversationsUiState> build() async {
    _fcmSub = PushNotificationService.notificationStream.stream.listen((_) => load(silent: true));
    _wsSub = WsService.messageStream.stream.listen((data) {
      if (data['type'] == 'message') {
        _updateConversationInMemory(data);
        PushNotificationService.badgeRefreshNeeded.add(null);
      }
    });

    ref.onDispose(() {
      _fcmSub?.cancel();
      _wsSub?.cancel();
    });

    final info = await StorageService.getUserInfo();
    final myUserId = info?['id'] as int?;

    final cached = await StorageService.getCachedData(StorageService.cacheMessages);
    
    Future.microtask(() => load(silent: cached != null));

    return ConversationsUiState(
      myUserId: myUserId,
      conversations: cached != null ? (cached as List) : [],
      loading: cached == null,
    );
  }

  Future<void> load({bool silent = false}) async {
    if (_loadInProgress || !state.hasValue) return;
    _loadInProgress = true;
    
    if (!silent) {
      state = AsyncValue.data(state.value!.copyWith(loading: true));
    }

    try {
      final data = await NotificationService.getConversations();
      await StorageService.cacheData(StorageService.cacheMessages, data);
      state = AsyncValue.data(state.value!.copyWith(
        conversations: data,
        loading: false,
        hasError: false,
      ));
    } catch (e) {
      state = AsyncValue.data(state.value!.copyWith(
        hasError: true,
        loading: false,
      ));
    } finally {
      _loadInProgress = false;
    }
  }

  void _updateConversationInMemory(Map<String, dynamic> data) {
    if (!state.hasValue) return;
    final currentState = state.value!;
    final senderId = data['sender_id'] as int?;
    final receiverId = data['receiver_id'] as int?;
    final createdAt = data['created_at'] as String?;
    final otherId = senderId == currentState.myUserId ? receiverId : senderId;

    if (otherId == null || currentState.myUserId == null) {
      load(silent: true);
      return;
    }

    final idx = currentState.conversations.indexWhere((c) => (c['user_id'] as int?) == otherId);
    if (idx < 0) {
      load(silent: true);
      return;
    }

    final updated = List<dynamic>.from(currentState.conversations);
    final conv = Map<String, dynamic>.from(updated[idx] as Map);
    
    final ct = data['content_type'] as String? ?? 'text';
    String lastMsg = (data['content'] as String?) ?? '';
    
    if (ct != 'text') {
      conv['last_message_type'] = ct; 
    } else {
      conv['last_message'] = lastMsg;
      conv['last_message_type'] = 'text';
    }
    
    conv['last_at'] = createdAt;
    if (senderId != currentState.myUserId) {
      conv['unread_count'] = ((conv['unread_count'] as int?) ?? 0) + 1;
    }
    updated..removeAt(idx)..insert(0, conv);
    state = AsyncValue.data(currentState.copyWith(conversations: updated));
  }

  Future<bool> deleteConversation(int otherId) async {
    final ok = await NotificationService.deleteConversation(otherId);
    if (ok && state.hasValue) {
      final updated = List<dynamic>.from(state.value!.conversations);
      updated.removeWhere((c) => (c['user_id'] as int?) == otherId);
      state = AsyncValue.data(state.value!.copyWith(conversations: updated));
    }
    return ok;
  }
}

final messagesTabViewModelProvider = AutoDisposeAsyncNotifierProvider<MessagesTabViewModel, ConversationsUiState>(
  () => MessagesTabViewModel(),
);

// ─── Notifications Tab View Model ─────────────────────────────────────────────

class NotificationsUiState {
  final List<dynamic> notifications;
  final bool loading;
  final bool hasError;

  const NotificationsUiState({
    this.notifications = const [],
    this.loading = true,
    this.hasError = false,
  });

  NotificationsUiState copyWith({
    List<dynamic>? notifications,
    bool? loading,
    bool? hasError,
  }) {
    return NotificationsUiState(
      notifications: notifications ?? this.notifications,
      loading: loading ?? this.loading,
      hasError: hasError ?? this.hasError,
    );
  }
}

class NotificationsTabViewModel extends AutoDisposeAsyncNotifier<NotificationsUiState> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  FutureOr<NotificationsUiState> build() async {
    _sub = PushNotificationService.notificationStream.stream.listen((_) => load(silent: true));
    ref.onDispose(() => _sub?.cancel());

    final cached = await StorageService.getCachedData(StorageService.cacheNotifications);
    
    Future.microtask(() => load(silent: cached != null));

    return NotificationsUiState(
      notifications: cached != null ? (cached as List) : [],
      loading: cached == null,
    );
  }

  Future<void> load({bool silent = false}) async {
    if (!state.hasValue) return;
    if (!silent) {
      state = AsyncValue.data(state.value!.copyWith(loading: true));
    }

    try {
      final data = await NotificationService.getNotifications();
      await StorageService.cacheData(StorageService.cacheNotifications, data);
      state = AsyncValue.data(state.value!.copyWith(
        notifications: data,
        loading: false,
        hasError: false,
      ));
    } catch (e) {
      state = AsyncValue.data(state.value!.copyWith(
        hasError: true,
        loading: false,
      ));
    }
  }

  void markAsRead(int index) {
    if (state.hasValue) {
      final updated = List<dynamic>.from(state.value!.notifications);
      if (index >= 0 && index < updated.length) {
        final notif = Map<String, dynamic>.from(updated[index] as Map);
        notif['is_read'] = true;
        updated[index] = notif;
        state = AsyncValue.data(state.value!.copyWith(notifications: updated));
      }
    }
  }
}

final notificationsTabViewModelProvider = AutoDisposeAsyncNotifierProvider<NotificationsTabViewModel, NotificationsUiState>(
  () => NotificationsTabViewModel(),
);

// ─── Requests Tab View Model ──────────────────────────────────────────────────

class RequestsTabViewModel extends AutoDisposeAsyncNotifier<ConversationsUiState> {
  StreamSubscription<Map<String, dynamic>>? _fcmSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _loadInProgress = false;

  @override
  FutureOr<ConversationsUiState> build() async {
    _fcmSub = PushNotificationService.notificationStream.stream.listen((_) => load(silent: true));
    _wsSub = WsService.messageStream.stream.listen((data) {
      if (data['type'] == 'message') load(silent: true);
    });
    ref.onDispose(() {
      _fcmSub?.cancel();
      _wsSub?.cancel();
    });

    Future.microtask(() => load(silent: false));
    return const ConversationsUiState(loading: true);
  }

  Future<void> load({bool silent = false}) async {
    if (_loadInProgress || !state.hasValue) return;
    _loadInProgress = true;
    if (!silent) {
      state = AsyncValue.data(state.value!.copyWith(loading: true));
    }
    try {
      final data = await NotificationService.getMessageRequests();
      state = AsyncValue.data(state.value!.copyWith(
        conversations: data,
        loading: false,
        hasError: false,
      ));
    } catch (e) {
      state = AsyncValue.data(state.value!.copyWith(
        hasError: true,
        loading: false,
      ));
    } finally {
      _loadInProgress = false;
    }
  }
}

final requestsTabViewModelProvider = AutoDisposeAsyncNotifierProvider<RequestsTabViewModel, ConversationsUiState>(
  () => RequestsTabViewModel(),
);
