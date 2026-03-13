import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/storage_service.dart';

void main() {
  runApp(const TeqlifApp());
}

class TeqlifApp extends StatelessWidget {
  const TeqlifApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'teqlif',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      home: const _SplashGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const MainScreen(),
      },
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
    await Future.delayed(const Duration(milliseconds: 300));
    final token = await StorageService.getToken();
    if (!mounted) return;
    if (token != null) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'teqlif',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: kPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}
