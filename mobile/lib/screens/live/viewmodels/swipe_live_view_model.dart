import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/stream_service.dart';
import '../../../models/stream.dart';

// SwipeLiveViewModel (Ana Feed Yönetimi) ---------------------------
class SwipeLiveState {
  final bool isLoading;
  const SwipeLiveState({this.isLoading = false});
}

class SwipeLiveViewModel extends AsyncNotifier<SwipeLiveState> {
  @override
  FutureOr<SwipeLiveState> build() {
    return const SwipeLiveState();
  }

  Future<void> sendSwipeLiveEvents(List<Map<String, dynamic>> events) async {
    try {
      await StreamService.sendSwipeLiveEvents(events);
    } catch (_) {}
  }

  Future<List<StreamOut>> getActiveStreams() async {
    try {
      return await StreamService.getActiveStreams();
    } catch (_) {
      return [];
    }
  }

  Future<dynamic> getSwipeLiveConfig() async {
    try {
      return await StreamService.getSwipeLiveConfig();
    } catch (_) {
      return null;
    }
  }
}

final swipeLiveViewModelProvider = AsyncNotifierProvider<SwipeLiveViewModel, SwipeLiveState>(() {
  return SwipeLiveViewModel();
});

// SwipeLivePageViewModel (Sayfa Bazlı İşlemler) ----------------------
class SwipeLivePageState {
  final bool isLoading;
  const SwipeLivePageState({this.isLoading = false});
}

class SwipeLivePageViewModel extends AutoDisposeFamilyAsyncNotifier<SwipeLivePageState, int> {
  @override
  FutureOr<SwipeLivePageState> build(int arg) {
    return const SwipeLivePageState();
  }

  Future<void> likeStream() async {
    try {
      await StreamService.likeStream(arg);
    } catch (_) {}
  }

  Future<StreamTokenOut> acceptCoHostInvite() async {
    return await StreamService.acceptCoHostInvite(arg);
  }

  Future<bool> leaveCoHost() async {
    try {
      await StreamService.leaveCoHost(arg);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final swipeLivePageViewModelProvider = AutoDisposeAsyncNotifierProviderFamily<SwipeLivePageViewModel, SwipeLivePageState, int>(() {
  return SwipeLivePageViewModel();
});
