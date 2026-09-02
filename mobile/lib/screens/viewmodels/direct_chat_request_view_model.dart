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

  const DirectChatRequestState({
    this.status,
    this.isInitiator = false,
    this.isLoading = true,
    this.isActioning = false,
  });

  DirectChatRequestState copyWith({
    String? status,
    bool clearStatus = false,
    bool? isInitiator,
    bool? isLoading,
    bool? isActioning,
  }) {
    return DirectChatRequestState(
      status: clearStatus ? null : (status ?? this.status),
      isInitiator: isInitiator ?? this.isInitiator,
      isLoading: isLoading ?? this.isLoading,
      isActioning: isActioning ?? this.isActioning,
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
}

final directChatRequestProvider = AutoDisposeFamilyAsyncNotifierProvider<
    DirectChatRequestNotifier, DirectChatRequestState, int>(
  () => DirectChatRequestNotifier(),
);
