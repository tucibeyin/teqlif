import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/home/screens/home_screen.dart';
import '../features/notifications/providers/unread_counts_provider.dart';

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/dashboard')) return 1;
    if (location.startsWith('/messages')) return 3;
    if (location.startsWith('/notifications')) return 4;
    return 0; // default
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _locationToIndex(location);
    final unreadCounts = ref.watch(unreadCountsProvider);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) {
                switch (index) {
                  case 0:
                    if (location == '/home') {
                      ref.invalidate(adsProvider);
                    } else {
                      context.go('/home');
                    }
                    break;
                  case 1:
                    context.go('/dashboard');
                    break;
                  case 2:
                    context.push('/post-ad');
                    break;
                  case 3:
                    ref.read(unreadCountsProvider.notifier).refresh();
                    context.go('/messages');
                    break;
                  case 4:
                    ref.read(unreadCountsProvider.notifier).refresh();
                    context.go('/notifications');
                    break;
                }
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Anasayfa',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Panelim',
                ),
                NavigationDestination(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00B4CC),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  label: 'İlan Ver',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: (unreadCounts.value?.messages ?? 0) > 0,
                    label: Text(unreadCounts.value?.messages.toString() ?? ''),
                    child: const Icon(Icons.message_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: (unreadCounts.value?.messages ?? 0) > 0,
                    label: Text(unreadCounts.value?.messages.toString() ?? ''),
                    child: const Icon(Icons.message),
                  ),
                  label: 'Mesajlar',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: (unreadCounts.value?.notifications ?? 0) > 0,
                    label: Text(unreadCounts.value?.notifications.toString() ?? ''),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: (unreadCounts.value?.notifications ?? 0) > 0,
                    label: Text(unreadCounts.value?.notifications.toString() ?? ''),
                    child: const Icon(Icons.notifications),
                  ),
                  label: 'Bildirimler',
                ),
              ],
            ),
    );
  }
}
