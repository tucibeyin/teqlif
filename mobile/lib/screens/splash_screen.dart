import 'dart:async';
import 'dart:convert';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';
import 'package:http/http.dart' as http;
import 'listing_detail_screen.dart';
import 'public_profile_screen.dart';
import 'live/swipe_live_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  /// Gelen deep link URL'ini parse edip ilgili ekrana yönlendirir.
  /// Uygulama açıkken (foreground) ve arka planda beklerken çalışır.
  void _handleDeepLink(Uri uri) {
    if (!mounted) return;
    final segments = uri.pathSegments;
    if (segments.length < 2) return;

    final type = segments[0];
    final param = segments[1];

    switch (type) {
      case 'profil':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PublicProfileScreen(username: param),
        ));
        break;
      case 'ilan':
        final id = int.tryParse(param);
        if (id != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ListingDeepLinkLoader(listingId: id),
          ));
        }
        break;
      case 'yayin':
        final id = int.tryParse(param);
        if (id != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SwipeLiveScreen.single(streamId: id),
          ));
        }
        break;
    }
  }

  /// Deep link dinleyiciyi başlatır.
  /// - getInitialLink: uygulama kapalıyken gelen link (cold start)
  /// - uriLinkStream: uygulama açıkken gelen link (warm/hot start)
  Future<void> _startDeepLinkListener() async {
    final appLinks = AppLinks();
    // Cold start: uygulama bu link ile açıldıysa
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) {
      _handleDeepLink(initialUri);
    }
    // Warm/hot start: uygulama açıkken link gelirse
    _linkSub = appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  Future<void> _boot() async {
    final token = await StorageService.getToken();
    FlutterNativeSplash.remove();

    // Rozeti sıfırla (non-blocking)
    AppBadgePlus.isSupported().then((ok) {
      if (ok) AppBadgePlus.updateBadge(0);
    });

    if (!mounted) return;

    await AnalyticsService.setConsent(true);
    await AnalyticsService.init();

    if (!mounted) return;

    if (token == null) {
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    // Face ID kontrolü
    final biometricEnabled = await StorageService.isBiometricEnabled();
    if (biometricEnabled) {
      final ok = await BiometricService.authenticate(
        reason: 'teqlif hesabınıza giriş yapmak için doğrulayın',
      );
      if (!mounted) return;
      if (!ok) {
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
    }

    // Pre-fetching: kullanıcı + ilan verilerini ve görselleri ön yükle
    // Timeout: 4sn — yavaş ağda bekletmeden devam et
    await _prefetch(token).timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );

    if (!mounted) return;
    PushNotificationService.initialize();
    await _startDeepLinkListener();
    Navigator.of(context).pushReplacementNamed('/home');
  }

  Future<void> _prefetch(String token) async {
    final futures = <Future>[
      _fetchUser(token),
      _fetchListings(),
    ];

    final results = await Future.wait(futures, eagerError: false);

    if (!mounted) return;

    final urlsToPrecache = <String>[];

    // Kullanıcı profil görseli (thumb öncelikli)
    final user = results[0];
    if (user != null) {
      final thumbUrl = user['profile_image_thumb_url'] as String?;
      final imageUrl = thumbUrl ?? user['profile_image_url'] as String?;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        urlsToPrecache.add(imgUrl(imageUrl));
      }
    }

    // İlk 5 ilanın thumbnail'ı
    final listings = results[1];
    if (listings is List) {
      for (final l in listings.take(5)) {
        final m = l as Map<String, dynamic>;
        final thumbUrl = m['thumbnail_url'] as String?;
        final imageUrl = thumbUrl ?? m['image_url'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          urlsToPrecache.add(imgUrl(imageUrl));
        }
      }
    }

    // precacheImage — paralel, hatalar sessizce yutulur
    await Future.wait(
      urlsToPrecache.map((url) => _precache(url)),
      eagerError: false,
    );
  }

  Future<Map<String, dynamic>?> _fetchUser(String token) async {
    try {
      final user = await AuthService.me();
      return {
        'profile_image_url': user.profileImageUrl,
        'profile_image_thumb_url': user.profileImageThumbUrl,
      };
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> _fetchListings() async {
    try {
      final resp = await http.get(Uri.parse('$kBaseUrl/listings'));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as List;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _precache(String url) async {
    try {
      await precacheImage(CachedNetworkImageProvider(url), context);
    } catch (_) {}
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
