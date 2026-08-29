import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../core/event_bus.dart';

class ProHubState {
  final Map<String, dynamic>? blastCredits;
  final Map<String, dynamic>? boostCredits;
  final Map<String, dynamic>? aiDescCredits;
  final Map<String, dynamic>? reactivationCredits;
  final bool isLoading;
  final bool isPremium;
  final String? planType;

  const ProHubState({
    this.blastCredits,
    this.boostCredits,
    this.aiDescCredits,
    this.reactivationCredits,
    this.isLoading = true,
    this.isPremium = false,
    this.planType,
  });

  ProHubState copyWith({
    Map<String, dynamic>? blastCredits,
    Map<String, dynamic>? boostCredits,
    Map<String, dynamic>? aiDescCredits,
    Map<String, dynamic>? reactivationCredits,
    bool? isLoading,
    bool? isPremium,
    String? planType,
  }) {
    return ProHubState(
      blastCredits: blastCredits ?? this.blastCredits,
      boostCredits: boostCredits ?? this.boostCredits,
      aiDescCredits: aiDescCredits ?? this.aiDescCredits,
      reactivationCredits: reactivationCredits ?? this.reactivationCredits,
      isLoading: isLoading ?? this.isLoading,
      isPremium: isPremium ?? this.isPremium,
      planType: planType ?? this.planType,
    );
  }
}

class ProHubViewModel extends AutoDisposeFamilyNotifier<ProHubState, bool> {
  StreamSubscription<CreditsChangedEvent>? _creditsSub;

  @override
  ProHubState build(bool arg) {
    _creditsSub = eventBus.on<CreditsChangedEvent>().listen((_) => loadCredits());
    Future.microtask(() {
      loadLocalPlanType();
      verifyPremium();
      loadCredits();
      AnalyticsService.trackEvent('pro_hub_view', {'is_premium': arg});
    });
    return ProHubState(isPremium: arg);
  }

  Future<void> loadLocalPlanType() async {
    final info = await StorageService.getUserInfo();
    if (info != null) {
      state = state.copyWith(planType: info['plan_type'] as String?);
    }
  }

  Future<void> verifyPremium() async {
    try {
      final user = await AuthService.me();
      if (user.isPremium != state.isPremium || user.planType != state.planType) {
        state = state.copyWith(isPremium: user.isPremium, planType: user.planType);
      }
      await StorageService.saveUserInfo(
        id: user.id,
        email: user.email,
        username: user.username,
        fullName: user.fullName,
        isPremium: user.isPremium,
        planType: user.planType,
        onboardingCompleted: user.onboardingCompleted,
        isVerified: user.isVerified,
        phoneVerified: user.phoneVerified,
      );
    } catch (_) {}
  }

  Future<void> loadCredits() async {
    state = state.copyWith(isLoading: true);
    final results = await Future.wait([
      AnalyticsService.getBlastCredits(),
      AnalyticsService.getBoostCredits(),
      AnalyticsService.getAiDescCredits(),
      AnalyticsService.getReactivationCredits(),
    ]);

    state = state.copyWith(
      blastCredits: results[0],
      boostCredits: results[1],
      aiDescCredits: results[2],
      reactivationCredits: results[3],
      isLoading: false,
    );
  }

  void cleanup() {
    _creditsSub?.cancel();
  }
}

final proHubProvider = NotifierProvider.autoDispose.family<ProHubViewModel, ProHubState, bool>(
  () => ProHubViewModel(),
);
