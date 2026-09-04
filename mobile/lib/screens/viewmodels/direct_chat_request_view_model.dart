import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/notification_service.dart';
import '../../services/localization_service.dart';
import '../../utils/error_helper.dart';

class DirectChatRequestState {
  final String? status; // 'pending' | 'accepted' | 'declined' | null (no thread)
  final bool isInitiator;
  final bool isLoading;
  final bool isActioning;
  final bool canCall;
  final bool callAllowed; // acceptor'ün verdiği arama izni

  const DirectChatRequestState({
    this.status,
    this.isInitiator = false,
    this.isLoading = true,
    this.isActioning = false,
    this.canCall = false,
    this.callAllowed = false,
  });

  DirectChatRequestState copyWith({
    String? status,
    bool clearStatus = false,
    bool? isInitiator,
    bool? isLoading,
    bool? isActioning,
    bool? canCall,
    bool? callAllowed,
  }) {
    return DirectChatRequestState(
      status: clearStatus ? null : (status ?? this.status),
      isInitiator: isInitiator ?? this.isInitiator,
      isLoading: isLoading ?? this.isLoading,
      isActioning: isActioning ?? this.isActioning,
      canCall: canCall ?? this.canCall,
      callAllowed: callAllowed ?? this.callAllowed,
    );
  }
}

class DirectChatRequestNotifier
    extends AutoDisposeFamilyAsyncNotifier<DirectChatRequestState, int> {
  @override
  FutureOr<DirectChatRequestState> build(int arg) => _fetch();

  Future<DirectChatRequestState> _fetch() async {
    try {
      final data = await NotificationService.getThreadStatus(arg);
      return DirectChatRequestState(
        status: data['status'] as String?,
        isInitiator: (data['is_initiator'] as bool?) ?? false,
        canCall: (data['can_call'] as bool?) ?? false,
        callAllowed: (data['call_allowed'] as bool?) ?? false,
        isLoading: false,
      );
    } catch (_) {
      return const DirectChatRequestState(isLoading: false);
    }
  }

  Future<void> accept() async {
    final current = state.value;
    if (current == null || current.isActioning) return;
    state = AsyncValue.data(current.copyWith(isActioning: true));
    try {
      await NotificationService.acceptMessageRequest(arg);
      state = AsyncValue.data(current.copyWith(status: 'accepted', isActioning: false));
    } catch (e) {
      handleError(e, ref.read(localizationProvider));
      state = AsyncValue.data(current.copyWith(isActioning: false));
    }
  }

  Future<void> decline() async {
    final current = state.value;
    if (current == null || current.isActioning) return;
    state = AsyncValue.data(current.copyWith(isActioning: true));
    try {
      await NotificationService.declineMessageRequest(arg);
      state = AsyncValue.data(current.copyWith(status: 'declined', isActioning: false));
    } catch (e) {
      handleError(e, ref.read(localizationProvider));
      state = AsyncValue.data(current.copyWith(isActioning: false));
    }
  }

  Future<void> setCallAllowed(bool allowed) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(callAllowed: allowed));
    try {
      await NotificationService.updateCallPermission(arg, allowed);
    } catch (e) {
      handleError(e, ref.read(localizationProvider));
      state = AsyncValue.data(current.copyWith(callAllowed: current.callAllowed));
    }
  }

  void updateCanCall(bool canCall) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(canCall: canCall));
  }
}

final directChatRequestProvider = AsyncNotifierProvider.autoDispose
    .family<DirectChatRequestNotifier, DirectChatRequestState, int>(
  DirectChatRequestNotifier.new,
);
