import 'package:flutter/material.dart';
import '../config/theme.dart';
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
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
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
