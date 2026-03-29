import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import '../config/theme.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/push_notification_service.dart';
import '../services/ws_service.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'messages_screen.dart';
import 'search_screen.dart';
import 'live/live_list_screen.dart';
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

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const LiveListScreen(),
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
    _notifStreamSub = PushNotificationService.notificationStream.stream.listen((_) {
      _refreshBadges();
    });
    _badgeRefreshSub = PushNotificationService.badgeRefreshNeeded.stream.listen((_) {
      _refreshBadges();
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
    setState(() => _currentIndex = index);
    // Mesajlar tabına geçince listeyi ve badge'i güncelle
    if (index == 3) {
      PushNotificationService.notificationStream.add({});
      Future.delayed(const Duration(milliseconds: 300), _refreshBadges);
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
