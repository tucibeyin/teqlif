import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/stream.dart';
import '../../../services/stream_service.dart';
import '../../../services/ws_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/storage_service.dart';

class LiveListState {
  final List<StreamOut> streams;
  final List<StreamOut> recommended;
  final List<Map<String, dynamic>> suggestedStreamers;
  final bool isLoggedIn;
  final bool isOffline;

  const LiveListState({
    this.streams = const [],
    this.recommended = const [],
    this.suggestedStreamers = const [],
    this.isLoggedIn = false,
    this.isOffline = false,
  });

  LiveListState copyWith({
    List<StreamOut>? streams,
    List<StreamOut>? recommended,
    List<Map<String, dynamic>>? suggestedStreamers,
    bool? isLoggedIn,
    bool? isOffline,
  }) {
    return LiveListState(
      streams: streams ?? this.streams,
      recommended: recommended ?? this.recommended,
      suggestedStreamers: suggestedStreamers ?? this.suggestedStreamers,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

class LiveListViewModel extends AsyncNotifier<LiveListState> {
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  StreamSubscription<bool>? _connectSub;
  StreamSubscription<List<StreamOut>>? _swrSub;
  final _connectSvc = ConnectivityService();

  @override
  FutureOr<LiveListState> build() async {
    // WebSocket dinleyicisi
    _wsSub ??= WsService.messageStream.stream.listen(_onWsMessage);
    
    // Connectivity dinleyicisi
    _connectSub ??= _connectSvc.onConnectivityChanged.listen((online) {
      if (state.value == null) return;
      final wasOffline = state.value!.isOffline;
      state = AsyncValue.data(state.value!.copyWith(isOffline: !online));
      if (online && wasOffline) {
        refresh(bypassCache: true);
      }
    });
    
    ref.onDispose(() {
      _wsSub?.cancel();
      _connectSub?.cancel();
      _swrSub?.cancel();
    });

    return _loadInitial(bypassCache: false);
  }

  Future<LiveListState> _loadInitial({required bool bypassCache}) async {
    final token = await StorageService.getToken();
    final isLoggedIn = token != null;
    final isOnline = await _connectSvc.isConnected;

    List<StreamOut> rec = [];
    List<Map<String, dynamic>> sugg = [];

    if (isLoggedIn) {
      // Arka planda başlasın ama beklesin ki state'i düzgün kurabilelim
      try {
        rec = await StreamService.getRecommendedStreams();
      } catch (_) {}

      try {
        sugg = await StreamService.getSuggestedStreamers();
      } catch (_) {}
    }

    final completer = Completer<List<StreamOut>>();
    
    _swrSub?.cancel();
    _swrSub = StreamService.getActiveStreamsStream(bypassCache: bypassCache).listen(
      (streams) {
        if (!completer.isCompleted) {
          completer.complete(streams);
        } else if (state.value != null) {
          state = AsyncValue.data(state.value!.copyWith(streams: streams));
        }
      },
      onError: (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        } else if (state.value == null || state.value!.streams.isEmpty) {
          state = AsyncValue.error(e, st);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete([]);
        }
      }
    );

    final activeStreams = await completer.future;

    return LiveListState(
      streams: activeStreams,
      recommended: rec,
      suggestedStreamers: sugg,
      isLoggedIn: isLoggedIn,
      isOffline: !isOnline,
    );
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final current = state.value;
    if (current == null) return;

    if (msg['type'] == 'stream_ended') {
      final streamId = msg['stream_id'];
      if (streamId is int) {
        state = AsyncValue.data(current.copyWith(
          streams: current.streams.where((s) => s.id != streamId).toList(),
          recommended: current.recommended.where((s) => s.id != streamId).toList(),
        ));
      }
    } else if (msg['type'] == 'stream_thumbnail_updated') {
      final streamId = msg['stream_id'];
      final thumbUrl = msg['thumbnail_url'] as String?;
      if (streamId is int && thumbUrl != null) {
        state = AsyncValue.data(current.copyWith(
          streams: current.streams.map((s) =>
            s.id == streamId ? s.copyWith(thumbnailUrl: thumbUrl) : s
          ).toList(),
          recommended: current.recommended.map((s) =>
            s.id == streamId ? s.copyWith(thumbnailUrl: thumbUrl) : s
          ).toList(),
        ));
      }
    }
  }

  Future<void> refresh({bool bypassCache = true}) async {
    state = const AsyncValue.loading();
    try {
      final newState = await _loadInitial(bypassCache: bypassCache);
      state = AsyncValue.data(newState);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final liveListViewModelProvider = AsyncNotifierProvider<LiveListViewModel, LiveListState>(() {
  return LiveListViewModel();
});
