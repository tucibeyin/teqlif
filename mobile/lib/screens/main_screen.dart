import '../services/analytics_service.dart';
import 'direct_sale_detail_screen.dart';
import 'home_screen.dart';
import 'listing_detail_screen.dart';
import 'profile_screen.dart';
import 'messages_screen.dart';
import 'public_profile_screen.dart';
import 'search_screen.dart';
import 'follow_requests_screen.dart';
import 'live/live_list_screen.dart';
import 'live/swipe_live_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import '../widgets/offline_banner.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'viewmodels/main_view_model.dart';

/// Global visibility notifier for the Live tab.
/// Prevents background ghost joining of streams when the user is on other tabs.
final ValueNotifier<bool> globalIsLiveTabVisible = ValueNotifier<bool>(true);

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final GlobalKey<LiveListScreenState> _liveListKey = GlobalKey();
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey();
  final GlobalKey<SearchScreenState> _searchKey = GlobalKey();
  final GlobalKey<MessagesScreenState> _messagesKey = GlobalKey();
  final GlobalKey<ProfileScreenState> _profileKey = GlobalKey();
  late final List<Widget> _screens;

  final Map<int, DateTime> _lastTabRefresh = {};

  static const Map<int, Duration> _kTabTtl = {
    0: Duration(seconds: 30),
    1: Duration(seconds: 60),
    2: Duration(seconds: 60),
    3: Duration(seconds: 120),
    4: Duration(seconds: 120),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(mainViewModelProvider.notifier).handleLifecycleResumed();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(mainViewModelProvider.notifier).handleLifecycleResumed();
      // App arka plandan döndü: aktif sekmenin TTL'i dolmuşsa SWR ile yenile
      _maybeRefreshCurrentTab();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      ref.read(mainViewModelProvider.notifier).handleLifecyclePausedOrDetached(_kTabNames[_currentIndex]);
    }
  }

  void _maybeRefreshCurrentTab() {
    final ttl = _kTabTtl[_currentIndex];
    if (ttl == null) return;
    final last = _lastTabRefresh[_currentIndex];
    if (last == null || DateTime.now().difference(last) > ttl) {
      if (_currentIndex == 0) _liveListKey.currentState?.refresh(bypassCache: false);
      if (_currentIndex == 1) _homeKey.currentState?.refresh(bypassCache: false);
      // if (_currentIndex == 2) SearchScreen handles own refresh via view model
      if (_currentIndex == 3) _messagesKey.currentState?.refresh(bypassCache: false);
      if (_currentIndex == 4) _profileKey.currentState?.refresh(bypassCache: false);
      _lastTabRefresh[_currentIndex] = DateTime.now();
    }
  }

  final _kTabNames = const ['live', 'home', 'search', 'messages', 'profile'];

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
          // if (index == 2) SearchScreen handles own refresh via view model
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
    
    globalIsLiveTabVisible.value = (index == 0);

    // Mesajlar tabına geçince badge'i güncelle (içerik TTL ile yönetiliyor)
    if (index == 3) {
      ref.read(mainViewModelProvider.notifier).refreshBadgesNow();
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



  Widget _buildMessageIcon(int unreadMessages, int unreadNotifs) {
    final dmCount = unreadMessages;
    final hasNotifs = unreadNotifs > 0;
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

  Widget _buildMessageActiveIcon(int unreadMessages, int unreadNotifs) {
    final dmCount = unreadMessages;
    final hasNotifs = unreadNotifs > 0;
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
    final loc = ref.watch(localizationProvider);
    final mainState = ref.watch(mainViewModelProvider);

    ref.listen<AsyncValue<MainState>>(mainViewModelProvider, (_, state) {
      if (!state.hasValue) return;
      final navData = state.value!.navigationData;
      if (navData.event != MainNavigationEvent.none) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          switch (navData.event) {
            case MainNavigationEvent.toLiveStream:
              _navigateToLiveStream(navData.payload as int);
              break;
            case MainNavigationEvent.toListing:
              _navigateToListing(navData.payload as int);
              break;
            case MainNavigationEvent.toNotificationsTab:
              _navigateToNotificationsTab();
              break;
            case MainNavigationEvent.toProfile:
              _navigateToProfile(navData.payload as String);
              break;
            case MainNavigationEvent.toDirectChat:
              _navigateToDirectChat(navData.payload as Map<String, dynamic>);
              break;
            case MainNavigationEvent.toFollowRequests:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
              );
              break;
            case MainNavigationEvent.toLogin:
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              break;
            case MainNavigationEvent.toDirectSaleDetail:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DirectSaleDetailScreen(saleId: navData.payload as int),
                ),
              );
              break;
            case MainNavigationEvent.none:
              break;
          }
          ref.read(mainViewModelProvider.notifier).clearNavigation();
        });
      }
    });

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
            activeIcon: Icon(Icons.videocam, color: kPrimary),
            label: loc.t('navLive'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.grid_view_outlined),
            activeIcon: const Icon(Icons.grid_view),
            label: loc.t('navListings'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.search_outlined),
            activeIcon: const Icon(Icons.search),
            label: loc.t('navSearch'),
          ),
          BottomNavigationBarItem(
            icon: _buildMessageIcon(mainState.value?.unreadMessages ?? 0, mainState.value?.unreadNotifs ?? 0),
            activeIcon: _buildMessageActiveIcon(mainState.value?.unreadMessages ?? 0, mainState.value?.unreadNotifs ?? 0),
            label: loc.t('navMessages'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: loc.t('navProfile'),
          ),
        ],
      ),
    );
  }
}
