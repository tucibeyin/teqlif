import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/storage_service.dart';
import '../../services/version_service.dart';

enum SplashResult {
  pending,
  forceUpdate,
  softUpdate,
  unauthenticated,
  authenticated
}

class SplashState {
  final SplashResult result;
  final String? locale;
  final String? localeUpdatedAt;
  final Map<String, dynamic>? user;
  final List<dynamic>? listings;

  SplashState({
    this.result = SplashResult.pending,
    this.locale,
    this.localeUpdatedAt,
    this.user,
    this.listings,
  });

  SplashState copyWith({
    SplashResult? result,
    String? locale,
    String? localeUpdatedAt,
    Map<String, dynamic>? user,
    List<dynamic>? listings,
  }) {
    return SplashState(
      result: result ?? this.result,
      locale: locale ?? this.locale,
      localeUpdatedAt: localeUpdatedAt ?? this.localeUpdatedAt,
      user: user ?? this.user,
      listings: listings ?? this.listings,
    );
  }
}

class SplashViewModel extends AutoDisposeAsyncNotifier<SplashState> {
  @override
  FutureOr<SplashState> build() {
    return SplashState();
  }

  Future<SplashState> boot(Future<void> localizationReadyFuture) async {
    state = const AsyncValue.loading();
    try {
      final token = await StorageService.getToken();

      await localizationReadyFuture.timeout(const Duration(seconds: 5), onTimeout: () {});
      FlutterNativeSplash.remove();

      final updateStatus = await VersionService.checkVersion();
      if (updateStatus == VersionStatus.forceUpdate) {
        final st = state.value?.copyWith(result: SplashResult.forceUpdate) ?? SplashState(result: SplashResult.forceUpdate);
        state = AsyncValue.data(st);
        return st;
      } else if (updateStatus == VersionStatus.softUpdate) {
        // Will show soft update but continue to boot
        state = AsyncValue.data(SplashState(result: SplashResult.softUpdate));
      }

      await AnalyticsService.setConsent(true);
      await AnalyticsService.init();

      AnalyticsService.trackEvent('session_start', {
        'platform': Platform.isIOS ? 'ios' : 'android',
      });

      await DeepLinkService.captureInitialLink();

      if (token == null) {
        final st = state.value?.copyWith(result: SplashResult.unauthenticated) ?? SplashState(result: SplashResult.unauthenticated);
        state = AsyncValue.data(st);
        return st;
      }

      // Face ID / Biometrics
      final biometricEnabled = await StorageService.isBiometricEnabled();
      if (biometricEnabled) {
        bool ok = false;
        while (!ok) {
          ok = await BiometricService.authenticate(
            reason: 'teqlif hesabınıza giriş yapmak için doğrulayın',
          );
          if (!ok) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }

      // Prefetch user and listings
      final results = await _prefetch(token).timeout(
        const Duration(seconds: 4),
        onTimeout: () => [null, null],
      );

      final user = results[0] as Map<String, dynamic>?;
      final listings = results[1] as List<dynamic>?;
      String? locale;
      String? localeUpdatedAt;

      if (user != null) {
        locale = user['locale'] as String?;
        localeUpdatedAt = user['localeUpdatedAt'] as String?;
      }

      await PushNotificationService.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint('[FCM] initialize timeout — devam ediliyor'),
      );

      final st = state.value?.copyWith(
        result: SplashResult.authenticated,
        locale: locale,
        localeUpdatedAt: localeUpdatedAt,
        user: user,
        listings: listings,
      ) ?? SplashState(
        result: SplashResult.authenticated,
        locale: locale,
        localeUpdatedAt: localeUpdatedAt,
        user: user,
        listings: listings,
      );
      state = AsyncValue.data(st);
      return st;

    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<List<dynamic>> _prefetch(String token) async {
    final futures = <Future>[
      _fetchUser(token),
      _fetchListings(),
    ];

    return await Future.wait(futures, eagerError: false);
  }

  Future<Map<String, dynamic>?> _fetchUser(String token) async {
    try {
      final user = await AuthService.me();
      
      await StorageService.saveUserInfo(
        id: user.id,
        email: user.email,
        username: user.username,
        fullName: user.fullName,
        isPremium: user.isPremium,
        onboardingCompleted: user.onboardingCompleted,
        isVerified: user.isVerified,
        phoneVerified: user.phoneVerified,
      );
      
      return {
        'profile_image_url': user.profileImageUrl,
        'profile_image_thumb_url': user.profileImageThumbUrl,
        'locale': user.locale,
        'localeUpdatedAt': user.localeUpdatedAt,
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
}

final splashViewModelProvider =
    AsyncNotifierProvider.autoDispose<SplashViewModel, SplashState>(() {
  return SplashViewModel();
});
