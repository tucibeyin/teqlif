import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'config/app_router.dart';
import 'config/theme.dart';
import 'core/api/api_client.dart';
import 'core/api/endpoints.dart';
import 'core/providers/auth_provider.dart';
import 'features/notifications/providers/unread_counts_provider.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification is shown automatically for background messages by FCM
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

void _handleNotificationTap(Map<String, dynamic> data, WidgetRef ref) {
  final type = data['type'] as String?;
  final route = (type == 'NEW_MESSAGE') ? '/messages' : '/notifications';

  final router = ref.read(routerProvider);
  final location = router.routerDelegate.currentConfiguration.uri.path;

  if (location == '/splash') {
    ref.read(pendingRouteProvider.notifier).state = route;
  } else {
    router.go(route);
  }
}

Future<void> _initLocalNotifications(WidgetRef ref) async {
  const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  await _localNotifications.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        try {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          _handleNotificationTap(data, ref);
        } catch (_) {}
      }
    },
  );
}

Future<void> _setupFCM(WidgetRef ref) async {
  final messaging = FirebaseMessaging.instance;

  // Clear native app badge on launch
  FlutterAppBadger.removeBadge();

  // Request permission (iOS)
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Get FCM token — may fail on iOS Simulator (no APNS), safe to ignore
  try {
    // For iOS, the APNs token must be fetched before FCM gets its token
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      String? apnsToken;
      for (int i = 0; i < 5; i++) {
        apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      debugPrint('[FCM] APNS Token: $apnsToken');
    }

    final token = await messaging.getToken();
    if (token != null) {
      if (ref.read(authProvider).isAuthenticated) {
        await ApiClient().post(Endpoints.pushRegister, data: {'fcmToken': token});
      }
    }
  } catch (e) {
    debugPrint('[FCM] Token fetch skipped/failed: $e');
  }

  // Listen for token refresh
  messaging.onTokenRefresh.listen((newToken) async {
    try {
      if (ref.read(authProvider).isAuthenticated) {
        await ApiClient()
            .post(Endpoints.pushRegister, data: {'fcmToken': newToken});
      }
    } catch (_) {}
  });

  // Foreground messages → show local notification AND refresh badges
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    ref.read(unreadCountsProvider.notifier).refresh();
    
    final notification = message.notification;
    if (notification != null) {
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'teqlif_channel',
            'Teqlif Bildirimleri',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/launcher_icon',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    }
  });

  // Handle tap from background state
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationTap(message.data, ref);
  });

  // Handle tap from terminated state
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationTap(initialMessage.data, ref);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('tr_TR', null);

  // Turkish locale for timeago
  timeago.setLocaleMessages('tr', timeago.TrMessages());

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const ProviderScope(child: TeqlifApp()));
}

class TeqlifApp extends ConsumerStatefulWidget {
  const TeqlifApp({super.key});

  @override
  ConsumerState<TeqlifApp> createState() => _TeqlifAppState();
}

class _TeqlifAppState extends ConsumerState<TeqlifApp> {
  @override
  void initState() {
    super.initState();
    
    // Listen for Authentication state changes to dynamically register Push Tokens upon successful Login/Registration mid-session.
    ref.listenManual(authProvider, (previous, next) async {
      if (previous?.isAuthenticated != true && next.isAuthenticated) {
        try {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await ApiClient().post(Endpoints.pushRegister, data: {'fcmToken': token});
          }
        } catch (_) {}
      }
    });

    // Setup FCM after the first frame (so auth provider is ready)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initLocalNotifications(ref);
      await _setupFCM(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'teqlif',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
