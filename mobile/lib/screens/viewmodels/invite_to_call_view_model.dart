import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/call_service.dart';
import '../../services/follows_service.dart';

class InviteToCallState {
  final List<dynamic> following;
  final bool loading;
  final Map<int, String> inviteState;

  const InviteToCallState({
    this.following = const [],
    this.loading = true,
    this.inviteState = const {},
  });

  InviteToCallState copyWith({
    List<dynamic>? following,
    bool? loading,
    Map<int, String>? inviteState,
  }) {
    return InviteToCallState(
      following: following ?? this.following,
      loading: loading ?? this.loading,
      inviteState: inviteState ?? this.inviteState,
    );
  }
}

class InviteToCallViewModel extends AutoDisposeAsyncNotifier<InviteToCallState> {
  @override
  FutureOr<InviteToCallState> build() async {
    try {
      final following = await FollowsService.fetchFollowingForInvite();
      return InviteToCallState(following: following, loading: false);
    } catch (_) {
      return const InviteToCallState(loading: false);
    }
  }

  Future<void> sendInvite(int callId, int userId) async {
    final current = state.value;
    if (current == null) return;

    state = AsyncValue.data(current.copyWith(
      inviteState: {...current.inviteState, userId: 'pending'},
    ));

    try {
      await CallService.instance.inviteToCall(userId);
      final st = state.value;
      if (st != null) {
        state = AsyncValue.data(st.copyWith(
          inviteState: {...st.inviteState, userId: 'sent'},
        ));
      }
    } catch (e) {
      final st = state.value;
      if (st != null) {
        final newMap = Map<int, String>.from(st.inviteState)..remove(userId);
        state = AsyncValue.data(st.copyWith(inviteState: newMap));
      }
    }
  }
}

final inviteToCallProvider = AsyncNotifierProvider.autoDispose<InviteToCallViewModel, InviteToCallState>(
  () => InviteToCallViewModel(),
);
