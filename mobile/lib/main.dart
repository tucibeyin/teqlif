import 'package:flutter/material.dart';
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

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeProvider.instance.load();
  // Background handler kaydı senkron çalışır; geri kalanı (foreground options,
  // getInitialMessage) non-blocking olarak başlat — runApp'i bloke etme
  PushNotificationService.initEarly();
  runApp(const TeqlifApp());
}

class TeqlifApp extends StatelessWidget {
  const TeqlifApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeProvider.instance,
      builder: (context, _) => MaterialApp(
        title: 'teqlif',
        theme: appTheme,
        darkTheme: darkTheme,
        themeMode: ThemeProvider.instance.themeMode,
        debugShowCheckedModeBanner: false,
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
    return const Scaffold(
      backgroundColor: kPrimary,
      body: Center(
        child: Text(
          'teqlif',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w300,
            color: Colors.white,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}
