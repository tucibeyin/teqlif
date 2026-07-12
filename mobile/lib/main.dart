import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/app_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'config/theme.dart';
import 'core/logger_service.dart';
import 'firebase_options.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/splash_screen.dart';
import 'services/analytics_service.dart';
import 'services/cache_service.dart';
import 'services/storage_service.dart';
import 'services/feed_telemetry_service.dart';
import 'services/offline_queue_service.dart';
import 'services/push_notification_service.dart';
import 'services/background_audio_handler.dart';
import 'widgets/global_keyboard_accessory.dart';
import 'widgets/global_call_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

      // iOS'ta Keychain uygulama silinse de korunur; SharedPreferences silinir.
      // Fresh install tespiti: SharedPreferences'ta flag yoksa → stale Keychain'i temizle.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('app_installed') != true) {
        await StorageService.clear();
        await prefs.setBool('app_installed', true);
      }

      await CacheService.init();
      // Süresi dolmuş Hive kayıtlarını arka planda temizle — startup'ı bloke etme
      CacheService.clearExpired().ignore();
      await StorageService.restoreAvatarUrl();
      await OfflineQueueService.init();
      OfflineQueueService.startDrainOnReconnect();
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await ThemeProvider.instance.load();
      // Background handler kaydı senkron çalışır; geri kalanı (foreground options,
      // getInitialMessage) non-blocking olarak başlat — runApp'i bloke etme
      PushNotificationService.initEarly();
      FeedTelemetryService.instance.init();
      await initBackgroundAudio();

      // Sentry appRunner zaten runZonedGuarded ile sarılı olduğundan
      // async hataları da Sentry tarafından yakalanır.
      runApp(const ProviderScope(child: TeqlifApp()));
    },
  );
  // --- SENTRY + GLOBAL HATA YAKALAMA ENTEGRASYONU SONU ---
}

class TeqlifApp extends ConsumerStatefulWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const TeqlifApp({super.key});

  @override
  ConsumerState<TeqlifApp> createState() => _TeqlifAppState();
}

class _TeqlifAppState extends ConsumerState<TeqlifApp> {
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
    final locale = ref.watch(localeProvider);
    return ListenableBuilder(
      listenable: ThemeProvider.instance,
      builder: (context, _) => MaterialApp(
        title: 'teqlif',
        theme: appTheme,
        darkTheme: darkTheme,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeProvider.instance.themeMode,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: TeqlifApp.navigatorKey,
        navigatorObservers: [AnalyticsRouteObserver()],
        builder: (context, child) {
          return GlobalCallOverlay(
            navigatorKey: TeqlifApp.navigatorKey,
            child: GlobalKeyboardAccessory(child: child!),
          );
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

