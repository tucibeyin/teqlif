import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:in_app_update/in_app_update.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/deep_link_service.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';
import '../services/version_service.dart';
import 'force_update_screen.dart';
import '../widgets/soft_update_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';
import '../services/localization_service.dart';

import 'viewmodels/splash_view_model.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boot();
    });
  }

  Future<void> _boot() async {
    try {
      final localizationReady = ref.read(localizationProvider.notifier).ready;
      final state = await ref.read(splashViewModelProvider.notifier).boot(localizationReady);
      
      if (!mounted) return;

      if (state.result == SplashResult.forceUpdate) {
        if (Platform.isAndroid) {
          try {
            final info = await InAppUpdate.checkForUpdate();
            if (info.updateAvailability == UpdateAvailability.updateAvailable) {
              await InAppUpdate.performImmediateUpdate();
            }
          } catch (_) {}
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ForceUpdateScreen()),
        );
        return;
      }
      
      if (state.hasSoftUpdate) {
        if (Platform.isAndroid) {
          try {
            final info = await InAppUpdate.checkForUpdate();
            if (info.updateAvailability == UpdateAvailability.updateAvailable) {
              await InAppUpdate.startFlexibleUpdate();
              await InAppUpdate.completeFlexibleUpdate();
            }
          } catch (_) {}
        }
        
        if (Platform.isIOS || true) {
          if (!mounted) return;
          await showDialog(
            context: context,
            barrierDismissible: true,
            builder: (_) => const SoftUpdateDialog(),
          );
        }
      }

      // Rozeti sıfırla (non-blocking)
      AppBadgePlus.isSupported().then((ok) {
        if (ok) AppBadgePlus.updateBadge(0);
      });

      if (!mounted) return;

      if (state.result == SplashResult.unauthenticated) {
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      // Locale sync
      if (state.locale != null && state.locale!.isNotEmpty) {
        await ref.read(localeProvider.notifier)
            .syncWithServer(state.locale!, state.localeUpdatedAt);
      }

      // Precache images
      await _precacheImages(state.user, state.listings);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e, st) {
      debugPrint('[SPLASH_BOOT_ERROR] Hata oluştu: $e\n$st');
    }
  }

  Future<void> _precacheImages(Map<String, dynamic>? user, List<dynamic>? listings) async {
    final urlsToPrecache = <String>[];

    if (user != null) {
      final thumbUrl = user['profile_image_thumb_url'] as String?;
      final imageUrl = thumbUrl ?? user['profile_image_url'] as String?;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        urlsToPrecache.add(imgUrl(imageUrl));
      }
    }

    if (listings != null) {
      for (final l in listings.take(5)) {
        final m = l as Map<String, dynamic>;
        final thumbUrl = m['thumbnail_url'] as String?;
        final imageUrl = thumbUrl ?? m['image_url'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          urlsToPrecache.add(imgUrl(imageUrl));
        }
      }
    }

    await Future.wait(
      urlsToPrecache.map((url) => _precache(url)),
      eagerError: false,
    );
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
