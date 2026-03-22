import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'config/theme.dart';
import 'firebase_options.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/biometric_service.dart';
import 'services/storage_service.dart';
import 'services/push_notification_service.dart';
import 'services/analytics_service.dart';
import 'widgets/global_keyboard_accessory.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeProvider.instance.load();
  // Background handler kaydı senkron çalışır; geri kalanı (foreground options,
  // getInitialMessage) non-blocking olarak başlat — runApp'i bloke etme
  PushNotificationService.initEarly();

// --- SENTRY ENTEGRASYONU BAŞLANGICI ---
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://d9535262385699cee49c13cc02add8f2@o4511052861538304.ingest.us.sentry.io/4511053904478208';
      // Üretim ortamı için performansı artırmak adına oranı düşürebilirsiniz (örn: 0.2)
      options.tracesSampleRate = 1.0; 
    },
    // Uygulamamızı Sentry üzerinden başlatıyoruz
    appRunner: () => runApp(const ProviderScope(child: TeqlifApp())),
  );
  // --- SENTRY ENTEGRASYONU BITISI ---
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
        home: const _SplashGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/home': (_) => const MainScreen(),
        },
      ),
    );
  }
}

class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final token = await StorageService.getToken();
    FlutterNativeSplash.remove();
    // Rozeti sıfırla (non-blocking)
    AppBadgePlus.isSupported().then((ok) {
      if (ok) AppBadgePlus.updateBadge(0);
    });
    if (!mounted) return;

    // Analytics Çerez/İzleme İzni Kontrolü
    final consent = await AnalyticsService.getConsentStatus();
    if (consent == null && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B), // Dark theme modal
          title: const Text('Kullanım İzni', style: TextStyle(color: Colors.white)),
          content: const Text(
            'teqlif deneyiminizi iyileştirmek ve analiz yapmak için kullanım verilerinizi anonim olarak toplamamıza izin verir misiniz?',
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                AnalyticsService.setConsent(false);
                Navigator.of(ctx).pop();
              },
              child: const Text('Reddet', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () {
                AnalyticsService.setConsent(true);
                Navigator.of(ctx).pop();
              },
              child: const Text('Kabul Et', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else if (consent != null) {
      await AnalyticsService.init();
    }

    if (!mounted) return;

    if (token != null) {
      // Face ID aktifse doğrula
      final biometricEnabled = await StorageService.isBiometricEnabled();
      if (biometricEnabled) {
        final ok = await BiometricService.authenticate(
          reason: 'teqlif hesabınıza giriş yapmak için doğrulayın',
        );
        if (!mounted) return;
        if (!ok) {
          // Doğrulama başarısız → login ekranına yönlendir (token silinmez)
          Navigator.of(context).pushReplacementNamed('/login');
          return;
        }
      }
      PushNotificationService.initialize();
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: kPrimary,
      body: Center(
        child: Image(
          image: const AssetImage('assets/splash.png'),
          width: w * 0.6,
        ),
      ),
    );
  }
}
