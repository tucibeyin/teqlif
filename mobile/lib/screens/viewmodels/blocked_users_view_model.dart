import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/user_repository.dart';

class BlockedUsersState {
  final List<dynamic> blockedUsers;
  const BlockedUsersState({this.blockedUsers = const []});
}

class BlockedUsersViewModel extends AutoDisposeAsyncNotifier<BlockedUsersState> {
  StreamSubscription<List<dynamic>>? _sub;

  @override
  FutureOr<BlockedUsersState> build() {
    final repo = ref.read(userRepositoryProvider);
    final cachedRaw = repo.getCachedBlockedUsers();

    _sub?.cancel();
    _sub = repo.getBlockedUsers().listen(
      (users) {
        if (state.hasValue) {
          state = AsyncValue.data(BlockedUsersState(blockedUsers: users));
        }
      },
      onError: (_) {},
    );
    ref.onDispose(() => _sub?.cancel());

    return BlockedUsersState(
      blockedUsers: cachedRaw != null ? (cachedRaw as List) : const [],
    );
  }

  Future<void> unblock(String username, int userId) async {
    final current = state.value;
    if (current == null) return;

    // Optimistic update
    final updated = List.from(current.blockedUsers)
      ..removeWhere((u) => u['id'] == userId);
    state = AsyncValue.data(BlockedUsersState(blockedUsers: updated));

    try {
      await ref.read(userRepositoryProvider).unblockUser(username);
      // Repository clearData yaptı — stream yeniden fire etmez; optimistic yeterli
    } catch (_) {
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}

final blockedUsersProvider = AsyncNotifierProvider.autoDispose<BlockedUsersViewModel, BlockedUsersState>(
  () => BlockedUsersViewModel(),
);
