import 'dart:async';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/deep_link_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/push_notification_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/stream_service.dart';
import '../../../services/ws_service.dart';
import '../../../services/call_service.dart';

enum MainNavigationEvent {
  none,
  toLiveStream,
  toListing,
  toNotificationsTab,
  toProfile,
  toDirectChat,
  toFollowRequests,
  toLogin,
  toDirectSaleDetail,
}

class MainNavigationData {
  final MainNavigationEvent event;
  final dynamic payload;

  const MainNavigationData({this.event = MainNavigationEvent.none, this.payload});
}

class MainState {
  final int unreadMessages;
  final int unreadNotifs;
  final MainNavigationData navigationData;

  const MainState({
    this.unreadMessages = 0,
    this.unreadNotifs = 0,
    this.navigationData = const MainNavigationData(),
  });

  MainState copyWith({
    int? unreadMessages,
    int? unreadNotifs,
    MainNavigationData? navigationData,
  }) {
    return MainState(
      unreadMessages: unreadMessages ?? this.unreadMessages,
      unreadNotifs: unreadNotifs ?? this.unreadNotifs,
      navigationData: navigationData ?? const MainNavigationData(), // Reset navigation on copy if not explicitly set
    );
  }
}

class MainViewModel extends AutoDisposeAsyncNotifier<MainState> {
  Timer? _badgeTimer;
  StreamSubscription<RemoteMessage>? _fcmSub;
  StreamSubscription<Map<String, dynamic>>? _notifStreamSub;
  StreamSubscription<void>? _badgeRefreshSub;
  StreamSubscription<Uri>? _deepLinkSub;
  StreamSubscription<void>? _authFailedSub;
  
  DateTime _sessionStart = DateTime.now();

  @override
  FutureOr<MainState> build() {
    _initListeners();
    _refreshBadges();
    
    // Check pending deep links / notifs on boot
    Future.microtask(() {
      final pending = DeepLinkService.consumePending();
      if (pending != null) handleDeepLink(pending);

      final pendingNotif = PushNotificationService.consumePendingNavigation();
      if (pendingNotif != null && (pendingNotif['type'] as String? ?? '').isNotEmpty) {
        handleNotifNavigation(pendingNotif);
      }
    });

    ref.onDispose(() {
      _badgeTimer?.cancel();
      _fcmSub?.cancel();
      _notifStreamSub?.cancel();
      _badgeRefreshSub?.cancel();
      _deepLinkSub?.cancel();
      _authFailedSub?.cancel();
    });
    
    return const MainState();
  }

  void _initListeners() {
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBadges());
    
    _fcmSub = FirebaseMessaging.onMessage.listen((msg) {
      _refreshBadges();
      AnalyticsService.trackEvent('push_received', {
        'notification_type': msg.data['type'] ?? 'unknown',
      });
    });
    
    _notifStreamSub = PushNotificationService.notificationStream.stream.listen((data) {
      _refreshBadges();
      final isForegroundReceive = data['is_foreground_receive'] == true;
      if (isForegroundReceive) {
        return; // Ön planda (açıkken) gelen bildirim doğrudan yönlendirme yapmamalı
      }
      if (data['type'] != null && (data['type'] as String).isNotEmpty) {
        handleNotifNavigation(data);
      }
    });
    
    _authFailedSub = AuthService.authFailedStream.stream.listen((_) {
      AuthService.logout().then((_) {
        state = AsyncValue.data(state.value!.copyWith(
          navigationData: const MainNavigationData(event: MainNavigationEvent.toLogin)
        ));
      });
    });
    
    _badgeRefreshSub = PushNotificationService.badgeRefreshNeeded.stream.listen((_) {
      _refreshBadges();
    });
    
    _deepLinkSub = DeepLinkService.uriStream.listen(handleDeepLink);
  }

  Future<void> _refreshBadges() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final msgs = await NotificationService.getUnreadMessageCount();
      final notifs = await NotificationService.getUnreadNotifCount();
      
      final current = state.value ?? const MainState();
      state = AsyncValue.data(current.copyWith(
        unreadMessages: msgs,
        unreadNotifs: notifs,
      ));
      
      final total = msgs + notifs;
      final supported = await AppBadgePlus.isSupported();
      if (supported) {
        await AppBadgePlus.updateBadge(total);
      }
    } catch (_) {}
  }
  
  void refreshBadgesNow() {
    _refreshBadges();
  }
  
  void handleLifecycleResumed() {
    AppBadgePlus.isSupported().then((ok) {
      if (ok) AppBadgePlus.updateBadge(0);
    });
    _refreshBadges();
    WsService.connect();
    PushNotificationService.notificationStream.add({});
    _sessionStart = DateTime.now();
  }
  
  void handleLifecyclePausedOrDetached(String currentTabName) {
    final durationSec = DateTime.now().difference(_sessionStart).inSeconds;
    if (durationSec > 2) {
      AnalyticsService.trackEvent('session_end', {
        'duration_sec': durationSec,
        'active_tab': currentTabName,
      });
    }
  }

  void handleDeepLink(Uri uri) {
    if (!DeepLinkService.shouldHandle(uri)) return;

    final segments = uri.scheme == 'teqlif'
        ? [if (uri.host.isNotEmpty) uri.host, ...uri.pathSegments.where((s) => s.isNotEmpty)]
        : uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (segments.length < 2) return;

    final type = segments[0];
    final param = segments[1];

    switch (type) {
      case 'profil':
        _navigate(MainNavigationEvent.toProfile, param);
        break;
      case 'ilan':
        final id = int.tryParse(param);
        if (id != null) {
          _navigate(MainNavigationEvent.toListing, id);
        }
        break;
      case 'yayin':
        final id = int.tryParse(param);
        if (id != null) {
          _navigate(MainNavigationEvent.toLiveStream, id);
        }
        break;
      case 'direct-sale':
        final id = int.tryParse(param);
        if (id != null) {
          _navigate(MainNavigationEvent.toDirectSaleDetail, id);
        }
        break;
    }
  }

  void handleNotifNavigation(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';

    // listing_id veya related_id (sender_id olarak iletilir) — hangisi varsa
    int? listingId() =>
        int.tryParse(data['listing_id']?.toString() ?? '') ??
        int.tryParse(data['sender_id']?.toString() ?? '');

    // stream_id veya related_id (sender_id olarak iletilir) — hangisi varsa
    int? streamId() =>
        int.tryParse(data['stream_id']?.toString() ?? '') ??
        int.tryParse(data['sender_id']?.toString() ?? '');

    switch (type) {
      case 'stream_started':
      case 'outbid':
      case 'smart_auction_alert':
        if (StreamService.isHosting) break;
        final sid = streamId();
        if (sid != null) _navigate(MainNavigationEvent.toLiveStream, sid);
        break;

      case 'new_listing':
      case 'auction_won':
      case 'search_alert':
      case 'budget_match':
      case 'churn_airdrop_buyer':
      case 'churn_airdrop_seller':
        final lid = listingId();
        if (lid != null) {
          _navigate(MainNavigationEvent.toListing, lid);
        } else {
          _navigate(MainNavigationEvent.toNotificationsTab, null);
        }
        break;

      case 'lead_blast':
        final campaignIdRaw = data['campaign_id'];
        if (campaignIdRaw != null) {
          final campaignId = int.tryParse(campaignIdRaw.toString());
          if (campaignId != null) {
            AnalyticsService.trackCampaignClick(campaignId);
            AnalyticsService.trackEvent('push_click', {'campaign_id': campaignId});
          }
        }
        
        final lid = listingId();
        final sid = streamId();
        
        if (sid != null && !StreamService.isHosting) {
          _navigate(MainNavigationEvent.toLiveStream, sid);
        } else if (lid != null) {
          _navigate(MainNavigationEvent.toListing, lid);
        } else {
          _navigate(MainNavigationEvent.toNotificationsTab, null);
        }
        break;

      case 'message':
        final senderId = int.tryParse(data['sender_id']?.toString() ?? '');
        if (senderId != null) {
          _navigate(MainNavigationEvent.toDirectChat, data);
        } else {
          _navigate(MainNavigationEvent.toNotificationsTab, null);
        }
        break;

      case 'follow_accepted':
      case 'follow':
        final username = data['sender_username'] as String? ?? '';
        if (username.isNotEmpty) {
          _navigate(MainNavigationEvent.toProfile, username);
        } else {
          _navigate(MainNavigationEvent.toNotificationsTab, null);
        }
        break;

      case 'follow_request':
        _navigate(MainNavigationEvent.toFollowRequests, null);
        break;

      case 'incoming_call':
      case 'call_incoming':
        if (CallService.instance.state.value.status == CallStatus.idle &&
            data['call_id'] != null) {
          CallService.instance.onIncomingCall(data);
        }
        break;

      case 'call_accepted':
      case 'call_rejected':
      case 'call_ended':
      case 'call_missed':
        final username = data['caller_username'] as String?;
        if (username != null && username.isNotEmpty) {
          _navigate(MainNavigationEvent.toProfile, username);
        }
        break;

      case 'direct_sale_purchased':
        final saleId = int.tryParse(data['sale_id']?.toString() ?? '');
        if (saleId != null) {
          _navigate(MainNavigationEvent.toDirectSaleDetail, saleId);
        } else {
          _navigate(MainNavigationEvent.toNotificationsTab, null);
        }
        break;

      case 'listing_removed':
      case 'listing_deactivated':
      case 'listing_deleted':
        _navigate(MainNavigationEvent.toNotificationsTab, null);
        break;

      default:
        if (type.isNotEmpty) _navigate(MainNavigationEvent.toNotificationsTab, null);
        break;
    }
  }

  void _navigate(MainNavigationEvent event, dynamic payload) {
    final current = state.value ?? const MainState();
    state = AsyncValue.data(current.copyWith(
      navigationData: MainNavigationData(event: event, payload: payload),
    ));
  }
  
  void clearNavigation() {
    final current = state.value ?? const MainState();
    state = AsyncValue.data(current.copyWith(
      navigationData: const MainNavigationData(event: MainNavigationEvent.none),
    ));
  }
}

final mainViewModelProvider =
    AsyncNotifierProvider.autoDispose<MainViewModel, MainState>(() {
  return MainViewModel();
});
