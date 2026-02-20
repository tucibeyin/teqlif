import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/ad/screens/ad_detail_screen.dart';
import '../features/ad/screens/post_ad_screen.dart';
import '../features/ad/screens/edit_ad_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/messages/screens/conversations_screen.dart';
import '../features/messages/screens/chat_screen.dart';
import '../features/notifications/screens/notifications_screen.dart';
import '../widgets/main_shell.dart';

// ── RouterNotifier ──────────────────────────────────────────────────────────
// Bridges Riverpod auth state → GoRouter refreshListenable.
// When authProvider changes, this calls notifyListeners(), causing GoRouter
// to re-evaluate its redirect function immediately.
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) {
      notifyListeners();
    });
  }

  // Routes that require authentication
  static const _protected = [
    '/dashboard',
    '/messages',
    '/notifications',
    '/post-ad',
  ];

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = _ref.read(authProvider);
    if (auth.isLoading) return null;

    final location = state.matchedLocation;
    final isAuth = auth.isAuthenticated;

    final isProtected = _protected.any((r) => location.startsWith(r)) ||
        location.startsWith('/edit-ad');

    if (!isAuth && isProtected) return '/login';
    if (isAuth && (location == '/login' || location == '/register')) {
      return '/home';
    }
    return null;
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final _routerNotifierProvider =
    ChangeNotifierProvider((ref) => RouterNotifier(ref));

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
          GoRoute(
              path: '/register', builder: (_, __) => const RegisterScreen()),
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/ad/:id',
            builder: (_, state) =>
                AdDetailScreen(adId: state.pathParameters['id']!),
          ),
          GoRoute(
              path: '/post-ad', builder: (_, __) => const PostAdScreen()),
          GoRoute(
            path: '/edit-ad/:id',
            builder: (_, state) =>
                EditAdScreen(adId: state.pathParameters['id']!),
          ),
          GoRoute(
              path: '/dashboard',
              builder: (_, __) => const DashboardScreen()),
          GoRoute(
              path: '/messages',
              builder: (_, __) => const ConversationsScreen()),
          GoRoute(
            path: '/messages/:id',
            builder: (_, state) =>
                ChatScreen(conversationId: state.pathParameters['id']!),
          ),
          GoRoute(
              path: '/notifications',
              builder: (_, __) => const NotificationsScreen()),
        ],
      ),
    ],
  );
});
