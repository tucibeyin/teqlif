import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  // Routes that require authentication
  const protectedRoutes = [
    '/dashboard',
    '/messages',
    '/notifications',
    '/post-ad',
  ];

  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final isLoading = authState.isLoading;
      if (isLoading) return null;

      final isAuth = authState.isAuthenticated;
      final location = state.matchedLocation;

      // Redirect to login if trying to access protected route without auth
      final isProtected =
          protectedRoutes.any((r) => location.startsWith(r)) ||
          location.startsWith('/edit-ad');
      if (!isAuth && isProtected) return '/login';

      // Redirect away from auth screens if already logged in
      if (isAuth &&
          (location == '/login' || location == '/register')) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/ad/:id',
            builder: (_, state) =>
                AdDetailScreen(adId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/post-ad', builder: (_, __) => const PostAdScreen()),
          GoRoute(
            path: '/edit-ad/:id',
            builder: (_, state) =>
                EditAdScreen(adId: state.pathParameters['id']!),
          ),
          GoRoute(
              path: '/dashboard', builder: (_, __) => const DashboardScreen()),
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
