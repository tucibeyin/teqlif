import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../core/event_bus.dart';
import '../../core/user_tier.dart';

class ProHubState {
  final Map<String, dynamic>? blastCredits;
  final Map<String, dynamic>? boostCredits;
  final Map<String, dynamic>? aiDescCredits;
  final Map<String, dynamic>? reactivationCredits;
  final bool isLoading;
  final String userType;
  final String? planType;
  final String? proExpiresAt;
  final int monthlyStreamSecondsUsed;

  const ProHubState({
    this.blastCredits,
    this.boostCredits,
    this.aiDescCredits,
    this.reactivationCredits,
    this.isLoading = true,
    this.userType = UserTier.standard,
    this.planType,
    this.proExpiresAt,
    this.monthlyStreamSecondsUsed = 0,
  });

  bool get isPaidTier => userType != UserTier.standard;

  ProHubState copyWith({
    Map<String, dynamic>? blastCredits,
    Map<String, dynamic>? boostCredits,
    Map<String, dynamic>? aiDescCredits,
    Map<String, dynamic>? reactivationCredits,
    bool? isLoading,
    String? userType,
    String? planType,
    String? proExpiresAt,
    int? monthlyStreamSecondsUsed,
  }) {
    return ProHubState(
      blastCredits: blastCredits ?? this.blastCredits,
      boostCredits: boostCredits ?? this.boostCredits,
      aiDescCredits: aiDescCredits ?? this.aiDescCredits,
      reactivationCredits: reactivationCredits ?? this.reactivationCredits,
      isLoading: isLoading ?? this.isLoading,
      userType: userType ?? this.userType,
      planType: planType ?? this.planType,
      proExpiresAt: proExpiresAt ?? this.proExpiresAt,
      monthlyStreamSecondsUsed: monthlyStreamSecondsUsed ?? this.monthlyStreamSecondsUsed,
    );
  }
}

class ProHubViewModel extends AutoDisposeFamilyNotifier<ProHubState, String> {
  StreamSubscription<CreditsChangedEvent>? _creditsSub;

  @override
  ProHubState build(String arg) {
    _creditsSub = eventBus.on<CreditsChangedEvent>().listen((_) => loadCredits());
    Future.microtask(() {
      loadLocalPlanType();
      verifyPremium();
      loadCredits();
      ref.read(analyticsServiceProvider).trackEvent('pro_hub_view', {'user_type': arg});
    });
    return ProHubState(userType: arg);
  }

  Future<void> loadLocalPlanType() async {
    final info = await StorageService.getUserInfo();
    if (info != null) {
      state = state.copyWith(planType: info['plan_type'] as String?);
    }
  }

  Future<void> verifyPremium() async {
    try {
      final user = await ref.read(authServiceProvider).me();
      if (user.userType != state.userType || user.planType != state.planType) {
        state = state.copyWith(userType: user.userType, planType: user.planType);
      }
      await StorageService.saveUserInfo(
        id: user.id,
        email: user.email,
        username: user.username,
        fullName: user.fullName,
        userType: user.userType,
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
      ref.read(analyticsServiceProvider).getBlastCredits(),
      ref.read(analyticsServiceProvider).getBoostCredits(),
      ref.read(analyticsServiceProvider).getAiDescCredits(),
      ref.read(analyticsServiceProvider).getReactivationCredits(),
    ]);

    final blast = results[0];
    state = state.copyWith(
      blastCredits: blast,
      boostCredits: results[1],
      aiDescCredits: results[2],
      reactivationCredits: results[3],
      proExpiresAt: blast?['pro_expires_at'] as String?,
      monthlyStreamSecondsUsed: (blast?['monthly_stream_seconds_used'] as num?)?.toInt() ?? 0,
      isLoading: false,
    );
  }

  void cleanup() {
    _creditsSub?.cancel();
  }
}

final proHubProvider = NotifierProvider.autoDispose.family<ProHubViewModel, ProHubState, String>(
  () => ProHubViewModel(),
);
