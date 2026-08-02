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

    // Aktif yayınları çek - SWR Stream'in ilk değerini bekleyeceğiz
    final streamIt = StreamService.getActiveStreamsStream(bypassCache: bypassCache).iterator;
    List<StreamOut> activeStreams = [];
    if (await streamIt.moveNext()) {
      activeStreams = streamIt.current;
    }
    
    // Arkadan gelen stream güncellemelerini de dinlemeliyiz (SWR gereği ağdan taze veri geldiğinde güncellemek için)
    _listenToSwrStream(bypassCache);

    return LiveListState(
      streams: activeStreams,
      recommended: rec,
      suggestedStreamers: sugg,
      isLoggedIn: isLoggedIn,
      isOffline: !isOnline,
    );
  }
  
  void _listenToSwrStream(bool bypassCache) async {
    try {
      await for (final streams in StreamService.getActiveStreamsStream(bypassCache: bypassCache)) {
        if (state.value != null) {
          state = AsyncValue.data(state.value!.copyWith(streams: streams));
        }
      }
    } catch (e, st) {
      // Stream error shouldn't crash the whole screen if we have cached data, but for now we just pass it
      // if it's a completely new load, otherwise we might ignore it.
      if (state.value == null || state.value!.streams.isEmpty) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'stream_ended') {
      final streamId = msg['stream_id'];
      if (streamId is int && state.value != null) {
        final current = state.value!;
        final newStreams = current.streams.where((s) => s.id != streamId).toList();
        final newRec = current.recommended.where((s) => s.id != streamId).toList();
        state = AsyncValue.data(current.copyWith(
          streams: newStreams,
          recommended: newRec,
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
