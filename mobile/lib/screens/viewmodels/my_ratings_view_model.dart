import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/ratings_repository.dart';

class MyRatingsState {
  final List<dynamic> receivedRatings;
  final List<dynamic> givenRatings;

  const MyRatingsState({
    this.receivedRatings = const [],
    this.givenRatings = const [],
  });
}

class MyRatingsViewModel extends AutoDisposeAsyncNotifier<MyRatingsState> {
  StreamSubscription<List<dynamic>>? _receivedSub;
  StreamSubscription<List<dynamic>>? _givenSub;

  @override
  FutureOr<MyRatingsState> build() {
    final repo = ref.read(ratingsRepositoryProvider);
    final cachedReceived = repo.getCachedReceived();
    final cachedGiven = repo.getCachedGiven();

    _receivedSub?.cancel();
    _givenSub?.cancel();

    _receivedSub = repo.getReceivedRatings().listen(
      (received) {
        if (state.hasValue) {
          state = AsyncValue.data(state.value!.copyWith(receivedRatings: received));
        }
      },
      onError: (_) {},
    );

    _givenSub = repo.getGivenRatings().listen(
      (given) {
        if (state.hasValue) {
          state = AsyncValue.data(state.value!.copyWith(givenRatings: given));
        }
      },
      onError: (_) {},
    );

    ref.onDispose(() {
      _receivedSub?.cancel();
      _givenSub?.cancel();
    });

    // Mark-as-read fire-and-forget — hata durumunda sessiz geç
    Future.microtask(() async {
      try {
        await ref.read(ratingsRepositoryProvider).markAsRead();
      } catch (_) {}
    });

    return MyRatingsState(
      receivedRatings: cachedReceived != null ? (cachedReceived as List) : const [],
      givenRatings: cachedGiven != null ? (cachedGiven as List) : const [],
    );
  }

  Future<bool> submitReply(int ratingId, String text) async {
    try {
      return await ref.read(ratingsRepositoryProvider).submitReply(ratingId, text);
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveRating(int userId, int score, String? comment) async {
    try {
      return await ref.read(ratingsRepositoryProvider).saveRating(userId, score, comment);
    } catch (_) {
      return false;
    }
  }
}

// MyRatingsState copyWith helper (private — dosya içinde)
extension _MyRatingsStateCopyWith on MyRatingsState {
  MyRatingsState copyWith({
    List<dynamic>? receivedRatings,
    List<dynamic>? givenRatings,
  }) =>
      MyRatingsState(
        receivedRatings: receivedRatings ?? this.receivedRatings,
        givenRatings: givenRatings ?? this.givenRatings,
      );
}

final myRatingsProvider = AsyncNotifierProvider.autoDispose<MyRatingsViewModel, MyRatingsState>(
  MyRatingsViewModel.new,
);
