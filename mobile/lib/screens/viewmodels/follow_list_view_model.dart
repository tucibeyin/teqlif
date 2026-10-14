import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/user_repository.dart';

export '../../repositories/user_repository.dart' show FollowListType;

class FollowListArgs {
  final int userId;
  final FollowListType type;

  const FollowListArgs({required this.userId, required this.type});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowListArgs &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          type == other.type;

  @override
  int get hashCode => userId.hashCode ^ type.hashCode;
}

class FollowListState {
  final List<dynamic> users;
  const FollowListState({this.users = const []});
}

class FollowListViewModel
    extends AutoDisposeFamilyAsyncNotifier<FollowListState, FollowListArgs> {
  StreamSubscription<List<dynamic>>? _sub;

  @override
  FutureOr<FollowListState> build(FollowListArgs arg) {
    final repo = ref.read(userRepositoryProvider);
    final cachedRaw = repo.getCachedFollowList(arg.userId, arg.type);

    _sub?.cancel();
    _sub = repo.getFollowList(arg.userId, arg.type).listen(
      (users) {
        if (state.hasValue) {
          state = AsyncValue.data(FollowListState(users: users));
        }
      },
      onError: (_) {},
    );
    ref.onDispose(() => _sub?.cancel());

    return FollowListState(
      users: cachedRaw != null ? (cachedRaw as List) : const [],
    );
  }

  Future<void> toggleFollow(int index) async {
    final currentState = state.value;
    if (currentState == null) return;

    final users = List<Map<String, dynamic>>.from(
        currentState.users.map((u) => Map<String, dynamic>.from(u as Map)));
    final user = users[index];
    final isFollowing = user['is_following'] as bool;
    final userId = user['id'] as int;

    // Optimistic update
    users[index]['is_following'] = !isFollowing;
    state = AsyncValue.data(FollowListState(users: users));

    try {
      await ref
          .read(userRepositoryProvider)
          .toggleFollow(userId, isFollowing: isFollowing);
    } catch (_) {
      users[index]['is_following'] = isFollowing;
      state = AsyncValue.data(FollowListState(users: users));
    }
  }
}

final followListProvider = AsyncNotifierProvider.autoDispose
    .family<FollowListViewModel, FollowListState, FollowListArgs>(
  () => FollowListViewModel(),
);
