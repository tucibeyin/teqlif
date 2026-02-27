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
import 'features/notifications/providers/notifications_provider.dart';
import 'features/ad/providers/ad_detail_provider.dart';
import 'features/messages/screens/chat_screen.dart';
import 'features/messages/screens/conversations_screen.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification is shown automatically for background messages by FCM
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

void _handleNotificationTap(Map<String, dynamic> data, WidgetRef ref) {
  // Force a global synchronization the moment the user taps a push notification
  ref.read(unreadCountsProvider.notifier).refresh();
  ref.read(conversationsProvider.notifier).refresh();
  final activeConvId = ref.read(activeChatIdProvider);
  if (activeConvId != null) {
    ref.invalidate(chatMessagesProvider(activeConvId));
  }

  final type = data['type'] as String?;
  final link = data['link'] as String?;
  
  String route = (type == 'NEW_MESSAGE') ? '/messages' : '/notifications';

  if ((type == 'BID_RECEIVED' || type == 'BID_ACCEPTED') && link != null) {
    try {
      final adId = link.split('/').last;
      if (adId.isNotEmpty) {
        ref.invalidate(adDetailProvider(adId));
      }
    } catch (_) {}
  }

  // If it's a message, try to extract specific conversation ID for deep linking
  if (type == 'NEW_MESSAGE' && link != null) {
    try {
      final uri = Uri.parse(link);
      final conversationId = uri.queryParameters['conversationId'];
      if (conversationId != null) {
        route = '/messages/$conversationId';
      }
    } catch (_) {}
  }

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

  // Explicitly create the high-importance Android channel for Firebase to use in the background
  if (defaultTargetPlatform == TargetPlatform.android) {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'teqlif_channel',
      'Teqlif Bildirimleri',
      description: 'Teqlif uygulaması için önemli bildirimler.',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
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
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint('[FCM] Foreground push received! Title: ${message.notification?.title}');
    
    // Multi-Stage Refresh: Trigger refreshes at different intervals to ensure 
    // we catch the backend update even if there's a slight delay or race condition.
    for (final delay in [500, 3000, 8000]) {
      Future.delayed(Duration(milliseconds: delay), () {
        if (ref.read(authProvider).isAuthenticated) {
          ref.read(unreadCountsProvider.notifier).refresh();
          ref.invalidate(notificationsProvider);
        }
      });
    }
    
    final payloadData = message.data;
    final type = payloadData['type'] as String?;
    
    if (type == 'NEW_MESSAGE') {
      // Refresh the Inbox list so the new message snippet appears
      ref.read(conversationsProvider.notifier).refresh();

      // Extract conversationId from the deep link payload (e.g. /dashboard/messages?conversationId=123)
      final link = payloadData['link'] as String?;
      String? incomingConvId;
      if (link != null) {
        try {
          // link can be a path like /dashboard/messages?conversationId=...
          // If it doesn't have a scheme, Uri.parse parses it as a path/query
          final uri = Uri.parse(link);
          incomingConvId = uri.queryParameters['conversationId'];
          debugPrint('[FCM] Parsed conversationId: $incomingConvId from link: $link');
        } catch (e) {
          debugPrint('[FCM] Failed to parse link: $link error: $e');
        }
      }

      // Check if the user is currently looking at this very conversation
      final activeConvId = ref.read(activeChatIdProvider);
      if (incomingConvId != null && activeConvId != null && incomingConvId == activeConvId) {
        // User is currently chatting with this person!
        // Silently refresh the chat screen messages list
        ref.invalidate(chatMessagesProvider(incomingConvId));
        debugPrint('[FCM] Silently refreshed active chat screen $incomingConvId');
        // DO NOT show a banner/toast if they are already looking at the chat
        return; 
      }
    }
    
    if (type == 'BID_RECEIVED' || type == 'BID_ACCEPTED') {
      final link = payloadData['link'] as String?;
      if (link != null) {
        try {
          final adId = link.split('/').last;
          if (adId.isNotEmpty) {
            ref.invalidate(adDetailProvider(adId));
            debugPrint('[FCM] Invalidated adDetailProvider for $adId in foreground');
          }
        } catch (_) {}
      }
    }

    final notification = message.notification;
    if (notification != null) {
      try {
        await _localNotifications.show(
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
        debugPrint('[FCM] Local notification displayed successfully!');
      } catch (e, stack) {
        debugPrint('[FCM] CRASH while showing local notification: $e');
        debugPrint(stack.toString());
      }
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
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  
  // Preserve the native OS splash screen until the Animated Flutter Splash Screen is ready
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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

class _TeqlifAppState extends ConsumerState<TeqlifApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Setup FCM after the first frame (so auth provider is ready)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initLocalNotifications(ref);
      await _setupFCM(ref);
      _startGlobalSyncTimer();
    });
  }

  Timer? _syncTimer;

  void _startGlobalSyncTimer() {
    _syncTimer?.cancel();
    // Refresh unread counts every 30 seconds as long as app is open and user is authed.
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (ref.read(authProvider).isAuthenticated) {
        ref.read(unreadCountsProvider.notifier).refresh();
        // Also refresh conversations if we are NOT on the chat screen to avoid heavy polling
        if (ref.read(activeChatIdProvider) == null) {
          ref.read(conversationsProvider.notifier).refresh();
        }
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When the app comes back to the foreground from the OS background, 
    // silently re-sync all badges and messages to catch any silent pushes we missed.
    if (state == AppLifecycleState.resumed) {
      if (ref.read(authProvider).isAuthenticated) {
        ref.read(unreadCountsProvider.notifier).refresh();
        ref.read(conversationsProvider.notifier).refresh();
        
        final activeConvId = ref.read(activeChatIdProvider);
        if (activeConvId != null) {
          ref.invalidate(chatMessagesProvider(activeConvId));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for Authentication state changes to dynamically register Push Tokens upon successful Login/Registration mid-session.
    ref.listen(authProvider, (previous, next) async {
      if (previous?.isAuthenticated != true && next.isAuthenticated) {
        try {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await ApiClient().post(Endpoints.pushRegister, data: {'fcmToken': token});
          }
        } catch (_) {}
      }
    });

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'teqlif',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
