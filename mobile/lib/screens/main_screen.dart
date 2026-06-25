import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/deep_link_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/push_notification_service.dart';
import '../services/ws_service.dart';
import 'home_screen.dart';
import 'listing_detail_screen.dart';
import 'profile_screen.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';
import 'search_screen.dart';
import 'live/live_list_screen.dart';
import 'live/swipe_live_screen.dart';
import '../l10n/app_localizations.dart';
import '../widgets/offline_banner.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  int _unreadMessages = 0;
  int _unreadNotifs = 0;

  Timer? _badgeTimer;
  StreamSubscription<RemoteMessage>? _fcmSub;
  StreamSubscription<Map<String, dynamic>>? _notifStreamSub;
  StreamSubscription<void>? _badgeRefreshSub;
  StreamSubscription<Uri>? _deepLinkSub;
  StreamSubscription<void>? _authFailedSub;

  final GlobalKey<LiveListScreenState> _liveListKey = GlobalKey();
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      LiveListScreen(key: _liveListKey),
      const HomeScreen(),
      const SearchScreen(),
      const MessagesScreen(),
      const ProfileScreen(),
    ];
    WidgetsBinding.instance.addObserver(this);
    WsService.connect();
    _refreshBadges();
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBadges());
    _fcmSub = FirebaseMessaging.onMessage.listen((_) => _refreshBadges());
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

  void _onNavTap(int index) {
    // Canlı yayınlar tabına dönüşte listeyi ve hikayeleri güncelle
    if (index == 0 && _currentIndex != 0) {
      _liveListKey.currentState?.refresh();
    }
    setState(() => _currentIndex = index);
    // Mesajlar tabına geçince listeyi ve badge'i güncelle
    if (index == 3) {
      PushNotificationService.notificationStream.add({});
      Future.delayed(const Duration(milliseconds: 300), _refreshBadges);
    }
  }

  /// FCM bildirim datasını parse edip ilgili ekrana yönlendirir.
  /// Hem cold-start hem warm/background start için kullanılır.
  void _handleNotifNavigation(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type'] as String? ?? '';
    switch (type) {
      case 'stream_started':
      case 'new_bid':
      case 'outbid':
      case 'smart_auction_alert':
        // stream_id varsa onu kullan; yoksa sender_id'ye (eski bildirimler) düş
        final sid = int.tryParse(data['stream_id']?.toString() ?? '') ??
            int.tryParse(data['sender_id']?.toString() ?? '');
        if (sid != null) _navigateToLiveStream(sid);
        break;
      case 'new_listing':
      case 'auction_won':
        final lid = int.tryParse(data['listing_id']?.toString() ?? '') ??
            int.tryParse(data['sender_id']?.toString() ?? '');
        if (lid != null) _navigateToListing(lid);
        break;
      case 'message':
        final senderId = int.tryParse(data['sender_id']?.toString() ?? '');
        if (senderId != null) _navigateToDirectChat(data);
        break;
      case 'follow':
        final username = data['sender_username'] as String? ?? '';
        if (username.isNotEmpty) _navigateToProfile(username);
        break;
    }
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

    // Aynı URI kısa sürede tekrar geldiyse (WhatsApp IAB + Universal Link
    // çakışması gibi durumlarda) ikinci işlemi yoksay.
    if (!DeepLinkService.shouldHandle(uri)) return;

    final segments = uri.pathSegments;
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
