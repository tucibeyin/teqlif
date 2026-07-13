import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/deep_link_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/push_notification_service.dart';
import '../services/stream_service.dart';
import '../services/ws_service.dart';
import '../services/analytics_service.dart';
import 'home_screen.dart';
import 'listing_detail_screen.dart';
import 'profile_screen.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';
import 'search_screen.dart';
import 'follow_requests_screen.dart';
import 'live/live_list_screen.dart';
import 'live/swipe_live_screen.dart';
import '../l10n/app_localizations.dart';
import '../widgets/offline_banner.dart';

import '../services/call_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  int _unreadMessages = 0;
  int _unreadNotifs = 0;
  DateTime _sessionStart = DateTime.now();

  Timer? _badgeTimer;
  StreamSubscription<RemoteMessage>? _fcmSub;
  StreamSubscription<Map<String, dynamic>>? _notifStreamSub;
  StreamSubscription<void>? _badgeRefreshSub;
  StreamSubscription<Uri>? _deepLinkSub;
  StreamSubscription<void>? _authFailedSub;

  final GlobalKey<LiveListScreenState> _liveListKey = GlobalKey();
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey();
  final GlobalKey<SearchScreenState> _searchKey = GlobalKey();
  final GlobalKey<MessagesScreenState> _messagesKey = GlobalKey();
  final GlobalKey<ProfileScreenState> _profileKey = GlobalKey();
  late final List<Widget> _screens;

  // Tab başına son SWR yenileme zamanı
  final Map<int, DateTime> _lastTabRefresh = {};

  // Tab TTL'leri: bu süreden önce geçilmişse ağ isteği atılmaz, cache gösterilir
  static const Map<int, Duration> _kTabTtl = {
    0: Duration(seconds: 30),   // Canlı — yayınlar sık değişir
    1: Duration(seconds: 60),   // İlanlar
    2: Duration(seconds: 60),   // Keşfet
    3: Duration(seconds: 120),  // Mesajlar
    4: Duration(seconds: 120),  // Profil
  };

  @override
  void initState() {
    super.initState();
    _screens = [
      LiveListScreen(key: _liveListKey),
      HomeScreen(key: _homeKey),
      SearchScreen(key: _searchKey),
      MessagesScreen(key: _messagesKey),
      ProfileScreen(key: _profileKey),
    ];
    WidgetsBinding.instance.addObserver(this);
    WsService.connect();
    _refreshBadges();
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBadges());
    _fcmSub = FirebaseMessaging.onMessage.listen((msg) {
      _refreshBadges();
      AnalyticsService.trackEvent('push_received', {
        'notification_type': msg.data['type'] ?? 'unknown',
      });
    });
    _notifStreamSub = PushNotificationService.notificationStream.stream.listen((data) {
      _refreshBadges();
      if (data['type'] != null && (data['type'] as String).isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotifNavigation(data));
      }
    });
    _authFailedSub = AuthService.authFailedStream.stream.listen((_) => _handleAuthFailed());
    _badgeRefreshSub = PushNotificationService.badgeRefreshNeeded.stream.listen((_) {
      _refreshBadges();
    });
    // Deep link dinleyici — warm/hot start + cold start tüketimi
    _deepLinkSub = DeepLinkService.uriStream.listen(_handleDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Cold-start URL deep link
      final pending = DeepLinkService.consumePending();
      if (pending != null) _handleDeepLink(pending);

      // Cold-start FCM bildirim (uygulama kapalıyken tıklama)
      final pendingNotif = PushNotificationService.consumePendingNavigation();
      if (pendingNotif != null && (pendingNotif['type'] as String? ?? '').isNotEmpty) {
        _handleNotifNavigation(pendingNotif);
      }

      // Proactively request microphone permission on app launch
      Permission.microphone.request();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WsService.disconnect();
    _badgeTimer?.cancel();
    _fcmSub?.cancel();
    _notifStreamSub?.cancel();
    _badgeRefreshSub?.cancel();
    _deepLinkSub?.cancel();
    _authFailedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppBadgePlus.isSupported().then((ok) {
        if (ok) AppBadgePlus.updateBadge(0);
      });
      _refreshBadges();
      WsService.connect();
      PushNotificationService.notificationStream.add({});
      // App arka plandan döndü: aktif sekmenin TTL'i dolmuşsa SWR ile yenile
      _maybeRefreshCurrentTab();
      _sessionStart = DateTime.now();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      final durationSec = DateTime.now().difference(_sessionStart).inSeconds;
      if (durationSec > 2) {
        AnalyticsService.trackEvent('session_end', {
          'duration_sec': durationSec,
          'active_tab': _kTabNames[_currentIndex],
        });
      }
    }
  }

  void _maybeRefreshCurrentTab() {
    final ttl = _kTabTtl[_currentIndex];
    if (ttl == null) return;
    final last = _lastTabRefresh[_currentIndex];
    if (last == null || DateTime.now().difference(last) > ttl) {
      if (_currentIndex == 0) _liveListKey.currentState?.refresh(bypassCache: false);
      if (_currentIndex == 1) _homeKey.currentState?.refresh(bypassCache: false);
      if (_currentIndex == 2) _searchKey.currentState?.refresh(bypassCache: false);
      if (_currentIndex == 3) _messagesKey.currentState?.refresh(bypassCache: false);
      if (_currentIndex == 4) _profileKey.currentState?.refresh(bypassCache: false);
      _lastTabRefresh[_currentIndex] = DateTime.now();
    }
  }

  Future<void> _refreshBadges() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final msgs = await NotificationService.getUnreadMessageCount();
      final notifs = await NotificationService.getUnreadNotifCount();
      if (mounted) {
        setState(() {
          _unreadMessages = msgs;
          _unreadNotifs = notifs;
        });
      }
      final total = msgs + notifs;
      final supported = await AppBadgePlus.isSupported();
      if (supported) {
        await AppBadgePlus.updateBadge(total);
      }
    } catch (_) {}
  }

  static const _kTabNames = ['live', 'home', 'search', 'messages', 'profile'];

  void _onNavTap(int index) {
    if (index != _currentIndex) {
      final ttl = _kTabTtl[index];
      if (ttl != null) {
        final last = _lastTabRefresh[index];
        final stale = last == null || DateTime.now().difference(last) > ttl;
        if (stale) {
          // TTL dolmuş: SWR — cache'i anında göster, arka planda API'yi çek
          if (index == 0) _liveListKey.currentState?.refresh(bypassCache: false);
          if (index == 1) _homeKey.currentState?.refresh(bypassCache: false);
          if (index == 2) _searchKey.currentState?.refresh(bypassCache: false);
          if (index == 3) _messagesKey.currentState?.refresh(bypassCache: false);
          if (index == 4) _profileKey.currentState?.refresh(bypassCache: false);
          _lastTabRefresh[index] = DateTime.now();
        }
        // TTL dolmamış: içerik olduğu gibi kalır, ağ isteği atılmaz
      }
      AnalyticsService.trackEvent('tab_switch', {
        'from': _kTabNames[_currentIndex],
        'to': _kTabNames[index],
      });
    }
    setState(() => _currentIndex = index);
    // Mesajlar tabına geçince badge'i güncelle (içerik TTL ile yönetiliyor)
    if (index == 3) {
      Future.delayed(const Duration(milliseconds: 300), _refreshBadges);
    }
  }

  /// FCM bildirim datasını parse edip ilgili ekrana yönlendirir.
  /// Hem cold-start hem warm/background start için kullanılır.
  void _handleNotifNavigation(Map<String, dynamic> data) {
    if (!mounted) return;
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
      // ── Canlı yayın bildirimleri ────────────────────────────────────────
      case 'stream_started':
      case 'outbid':
      case 'smart_auction_alert':
        // Host yayınını kapatma
        if (StreamService.isHosting) break;
        final sid = streamId();
        if (sid != null) _navigateToLiveStream(sid);
        break;

      // ── İlan bildirimleri ────────────────────────────────────────────────
      case 'new_listing':
      case 'auction_won':
      case 'search_alert':   // related_id = listing_id, sender_id olarak gelir
      case 'budget_match':   // related_id = listing_id, sender_id olarak gelir
      case 'churn_airdrop':  // related_id = listing_id, sender_id olarak gelir
        final lid = listingId();
        if (lid != null) {
          _navigateToListing(lid);
        } else {
          _navigateToNotificationsTab();
        }
        break;

      // ── Toplu Kitle Bildirimleri (Retargeting) ───────────────────────────
      case 'lead_blast':
        final campaignIdRaw = data['campaign_id'];
        if (campaignIdRaw != null) {
          final campaignId = int.tryParse(campaignIdRaw.toString());
          if (campaignId != null) {
            // Ateşle ve unut (Fire-and-forget)
            AnalyticsService.trackCampaignClick(campaignId);
            AnalyticsService.trackEvent('push_click', {'campaign_id': campaignId});
          }
        }
        
        final lid = listingId();
        final sid = streamId();
        
        if (sid != null && !StreamService.isHosting) {
          _navigateToLiveStream(sid);
        } else if (lid != null) {
          _navigateToListing(lid);
        } else {
          _navigateToNotificationsTab();
        }
        break;

      // ── Mesaj bildirimi ──────────────────────────────────────────────────
      case 'message':
        final senderId = int.tryParse(data['sender_id']?.toString() ?? '');
        if (senderId != null) {
          _navigateToDirectChat(data);
        } else {
          _navigateToNotificationsTab();
        }
        break;

      // ── Profil bildirimi ─────────────────────────────────────────────────
      case 'follow_accepted':
      case 'follow':
        final username = data['sender_username'] as String? ?? '';
        if (username.isNotEmpty) {
          _navigateToProfile(username);
        } else {
          _navigateToNotificationsTab();
        }
        break;

      case 'follow_request':
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
        );
        break;

      // ── Gelen arama ───────────────────────────────────────────────────────
      case 'incoming_call':
      case 'call_incoming':
        // Cold-start fix: push_notification_service zaten CallService'i haberdar etti
        // ama eğer FCM tap üzerinden geldiyse (pendingNavData) burada da kur.
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PublicProfileScreen(username: username),
            ),
          );
        }
        break;

      case 'incoming_call_notification_tap':
      case 'incoming_call_auto_accept':
        // IncomingCallOverlay kendi stream'ini dinler.
        break;

      // ── new_bid: host HostStreamScreen'de zaten görüyor, nav gerekmez ───
      case 'new_bid':
        break;

      // ── Bilgilendirme bildirimleri → Bildirimler sekmesi ─────────────────
      case 'listing_removed':
      case 'listing_deactivated':
      case 'listing_deleted':
        _navigateToNotificationsTab();
        break;

      // ── Bilinmeyen tür → Bildirimler sekmesi ─────────────────────────────
      default:
        if (type.isNotEmpty) _navigateToNotificationsTab();
        break;
    }
  }

  void _navigateToNotificationsTab() {
    if (!mounted) return;
    setState(() => _currentIndex = 3);
    // Kısa gecikme: IndexedStack widget'ı build edebilsin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messagesKey.currentState?.switchToNotificationsTab();
    });
  }

  void _navigateToLiveStream(int streamId) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => SwipeLiveScreen.single(streamId: streamId),
      ),
      (route) => route.isFirst,
    ).then((_) => _liveListKey.currentState?.refresh());
  }

  void _navigateToListing(int listingId) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListingDeepLinkLoader(listingId: listingId),
    ));
  }

  void _navigateToProfile(String username) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PublicProfileScreen(username: username),
    ));
  }

  void _navigateToDirectChat(Map<String, dynamic> data) {
    if (!mounted) return;
    final senderId = int.tryParse(data['sender_id']?.toString() ?? '');
    if (senderId == null) return;
    final senderUsername = data['sender_username'] as String? ?? '';
    setState(() => _currentIndex = 3);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DirectChatScreen(
        otherUserId: senderId,
        displayName: senderUsername.isNotEmpty ? senderUsername : 'Kullanıcı',
        otherHandle: senderUsername,
      ),
    ));
  }

  /// Her iki token da geçersizleştiğinde kullanıcıyı çıkış yaptır.
  Future<void> _handleAuthFailed() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  /// Deep link URL'ini parse ederek ilgili ekrana yönlendirir.
  /// Hem cold-start (pending) hem warm/hot start (uriStream) için kullanılır.
  void _handleDeepLink(Uri uri) {
    if (!mounted) return;

    // Aynı URI kısa sürede tekrar geldiyse ikinci işlemi yoksay.
    if (!DeepLinkService.shouldHandle(uri)) return;

    final segments = uri.scheme == 'teqlif'
        ? [if (uri.host.isNotEmpty) uri.host, ...uri.pathSegments.where((s) => s.isNotEmpty)]
        : uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (segments.length < 2) return;

    final type = segments[0];
    final param = segments[1];

    switch (type) {
      case 'profil':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PublicProfileScreen(username: param),
        ));
        break;
      case 'ilan':
        final id = int.tryParse(param);
        if (id != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ListingDeepLinkLoader(listingId: id),
          ));
        }
        break;
      case 'yayin':
        final id = int.tryParse(param);
        if (id != null) {
          // Stack'teki mevcut SwipeLiveScreen'leri temizle, yenisini push et.
          // Böylece aynı yayına birden fazla kez girildiğinde çakışma olmaz.
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => SwipeLiveScreen.single(streamId: id),
            ),
            (route) => route.settings.name == '/home' || route.isFirst,
          ).then((_) => _liveListKey.currentState?.refresh());
        }
        break;
    }
  }

  Widget _buildMessageIcon() {
    final dmCount = _unreadMessages;
    final hasNotifs = _unreadNotifs > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble_outline),
        if (dmCount > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$dmCount',
                style: const TextStyle(color: Colors.white, fontSize: 9),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (hasNotifs)
          Positioned(
            right: -3,
            top: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageActiveIcon() {
    final dmCount = _unreadMessages;
    final hasNotifs = _unreadNotifs > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble),
        if (dmCount > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$dmCount',
                style: const TextStyle(color: Colors.white, fontSize: 9),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (hasNotifs)
          Positioned(
            right: -3,
            top: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        key: const Key('main_bottom_nav'),
        currentIndex: _currentIndex,
        onTap: _onNavTap,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.videocam_outlined, color: Colors.red),
            activeIcon: const Icon(Icons.videocam, color: kPrimary),
            label: l.navLive,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.grid_view_outlined),
            activeIcon: const Icon(Icons.grid_view),
            label: l.navListings,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.search_outlined),
            activeIcon: const Icon(Icons.search),
            label: l.navSearch,
          ),
          BottomNavigationBarItem(
            icon: _buildMessageIcon(),
            activeIcon: _buildMessageActiveIcon(),
            label: l.navMessages,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: l.navProfile,
          ),
        ],
      ),
    );
  }
}
