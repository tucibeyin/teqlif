import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/ad/screens/ad_detail_screen.dart';
import '../features/ad/screens/post_ad_screen.dart';
import '../features/ad/screens/edit_ad_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/messages/screens/conversations_screen.dart';
import '../features/messages/screens/chat_screen.dart';
import '../features/notifications/screens/notifications_screen.dart';
import '../features/auth/screens/edit_profile_screen.dart';
import '../features/auth/screens/verify_profile_screen.dart';
import '../features/splash/screens/splash_screen.dart';
import '../widgets/main_shell.dart';

// ── Pending Route ───────────────────────────────────────────────────────────
// Stores deep links / push notification taps that arrive while the app
// is still on the splash screen or loading.
final pendingRouteProvider = StateProvider<String?>((ref) => null);

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
    final location = state.matchedLocation;

    // If still initializing from storage, keep them on splash
    if (auth.isLoading && location == '/splash') return null;
    
    // If auth state is just toggling 'isLoading' during an API call (like login/register),
    // we should NOT redirect them. We let the current screen show its loading spinner.
    if (auth.isLoading) return null;
    final isAuth = auth.isAuthenticated;

    final isProtected = _protected.any((r) => location.startsWith(r)) ||
        location.startsWith('/edit-ad');

    if (!isAuth && isProtected) return '/login';
    
    // Prevent logged-in users from seeing login/register screens
    if (isAuth && (location == '/login' || location == '/register' || location == '/forgot-password')) {
      return '/home';
    }
    
    // Maintain current route for everything else
    return null;
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final _routerNotifierProvider =
    ChangeNotifierProvider((ref) => RouterNotifier(ref));

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.read(_routerNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen()),
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
          GoRoute(
              path: '/profile/edit',
              builder: (_, __) => const EditProfileScreen()),
          GoRoute(
            path: '/profile/verify',
            builder: (_, state) => VerifyProfileScreen(
              profileData: state.extra as Map<String, dynamic>,
            ),
          ),
        ],
      ),
    ],
  );
});
