import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'config/app_router.dart';
import 'config/theme.dart';
import 'core/api/api_client.dart';
import 'core/api/endpoints.dart';

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification is shown automatically for background messages by FCM
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  await _localNotifications.initialize(
    const InitializationSettings(
        android: androidSettings, iOS: iosSettings),
  );
}

Future<void> _setupFCM() async {
  final messaging = FirebaseMessaging.instance;

  // Request permission (iOS)
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Get token and send to server
  final token = await messaging.getToken();
  if (token != null) {
    try {
      await ApiClient().post(Endpoints.pushRegister, data: {'fcmToken': token});
    } catch (_) {}
  }

  // Listen for token refresh
  messaging.onTokenRefresh.listen((newToken) async {
    try {
      await ApiClient()
          .post(Endpoints.pushRegister, data: {'fcmToken': newToken});
    } catch (_) {}
  });

  // Foreground messages → show local notification
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
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
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Turkish locale for timeago
  timeago.setLocaleMessages('tr', timeago.TrMessages());

  // Firebase
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);

  // Background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Local notifications
  await _initLocalNotifications();

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
    // Setup FCM after the first frame (so auth provider is ready)
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupFCM());
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
