import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config/theme.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'create_listing_screen.dart';
import 'messages_screen.dart';
import 'live/live_list_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Gerçek sayfa indeksi: 0=Canlı, 1=İlanlar, 2=Mesajlar, 3=Profilim
  int _pageIndex = 0;

  // Nav bar indeksi: 0=Canlı, 1=İlanlar, 2=Plus, 3=Mesajlar, 4=Profilim
  int _navIndex = 0;

  int _unreadMessages = 0;
  int _unreadNotifs = 0;

  Timer? _badgeTimer;
  StreamSubscription<RemoteMessage>? _fcmSub;

  final _liveKey = GlobalKey<LiveListScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      LiveListScreen(key: _liveKey),
      const HomeScreen(),
      const MessagesScreen(),
      const ProfileScreen(),
    ];
    _refreshBadges();
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBadges());
    // Refresh badge immediately when a push notification arrives in foreground
    _fcmSub = FirebaseMessaging.onMessage.listen((_) => _refreshBadges());
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _fcmSub?.cancel();
    super.dispose();
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
    } catch (_) {}
  }

  void _onNavTap(int navIndex) {
    if (navIndex == 2) {
      // Plus butonu: bağlama göre farklı aksiyon
      if (_pageIndex == 0) {
        _liveKey.currentState?.triggerStartDialog();
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateListingScreen()),
        );
      }
      return;
    }
    final pageIndex = navIndex > 2 ? navIndex - 1 : navIndex;
    setState(() {
      _pageIndex = pageIndex;
      _navIndex = navIndex;
    });
    // Refresh badges when switching to messages tab
    if (pageIndex == 2) {
      Future.delayed(const Duration(milliseconds: 500), _refreshBadges);
    }
  }

  Widget _buildMessageIcon() {
    final count = _unreadMessages + _unreadNotifs;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble_outline),
        if (count > 0)
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
                '$count',
                style: const TextStyle(color: Colors.white, fontSize: 9),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageActiveIcon() {
    final count = _unreadMessages + _unreadNotifs;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble),
        if (count > 0)
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
                '$count',
                style: const TextStyle(color: Colors.white, fontSize: 9),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _pageIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: _onNavTap,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.videocam_outlined),
            activeIcon: Icon(Icons.videocam),
            label: 'Canlı',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            activeIcon: Icon(Icons.grid_view),
            label: 'İlanlar',
          ),
          BottomNavigationBarItem(
            icon: _PlusIcon(isLive: _pageIndex == 0),
            label: _pageIndex == 0 ? 'Yayın Aç' : 'İlan Ver',
          ),
          BottomNavigationBarItem(
            icon: _buildMessageIcon(),
            activeIcon: _buildMessageActiveIcon(),
            label: 'Mesajlar',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profilim',
          ),
        ],
      ),
    );
  }
}

class _PlusIcon extends StatelessWidget {
  final bool isLive;
  const _PlusIcon({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isLive ? Colors.red : kPrimary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isLive ? Icons.videocam_outlined : Icons.add,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}
