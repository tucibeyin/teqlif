import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'config/theme.dart';
import 'core/logger_service.dart';
import 'firebase_options.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/splash_screen.dart';
import 'services/analytics_service.dart';
import 'services/push_notification_service.dart';
import 'widgets/global_keyboard_accessory.dart';

void main() async {
  // --- SENTRY + GLOBAL HATA YAKALAMA ENTEGRASYONU ---
  // NOT: ensureInitialized ve runApp aynı zone'da çağrılmalı.
  // SentryFlutter.init appRunner'ı kendi zone'unda çalıştırır; bu nedenle
  // tüm başlatma işlemleri appRunner içine taşındı.
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://d9535262385699cee49c13cc02add8f2@o4511052861538304.ingest.us.sentry.io/4511053904478208';
      // Üretim ortamı için performansı artırmak adına oranı düşürebilirsiniz (örn: 0.2)
      options.tracesSampleRate = 1.0;
    },
    appRunner: () async {
      // ensureInitialized ve runApp aynı (Sentry) zone'unda çalışır
      WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      // Flutter/UI katmanındaki yakalanmamış hataları yakala
      PlatformDispatcher.instance.onError = (error, stack) {
        LoggerService.instance.captureException(
          error,
          stackTrace: stack,
          tag: 'PlatformDispatcher',
        );
        return true; // hatayı "işlendi" olarak işaretle, uygulama çökmez
      };

      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await ThemeProvider.instance.load();
      // Background handler kaydı senkron çalışır; geri kalanı (foreground options,
      // getInitialMessage) non-blocking olarak başlat — runApp'i bloke etme
      PushNotificationService.initEarly();

      // Sentry appRunner zaten runZonedGuarded ile sarılı olduğundan
      // async hataları da Sentry tarafından yakalanır.
      runApp(const ProviderScope(child: TeqlifApp()));
    },
  );
  // --- SENTRY + GLOBAL HATA YAKALAMA ENTEGRASYONU SONU ---
}

class TeqlifApp extends StatefulWidget {
  const TeqlifApp({super.key});

  @override
  State<TeqlifApp> createState() => _TeqlifAppState();
}

class _TeqlifAppState extends State<TeqlifApp> {
  final _lifecycleObserver = AnalyticsLifecycleObserver();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeProvider.instance,
      builder: (context, _) => MaterialApp(
        title: 'teqlif',
        theme: appTheme,
        darkTheme: darkTheme,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeProvider.instance.themeMode,
        navigatorObservers: [AnalyticsRouteObserver()],
        builder: (context, child) {
          return GlobalKeyboardAccessory(child: child!);
        },
        home: const SplashScreen(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/home': (_) => const MainScreen(),
        },
      ),
    );
  }
}

