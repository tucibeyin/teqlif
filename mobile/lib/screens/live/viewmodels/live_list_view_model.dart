import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/stream.dart';
import '../../../services/api_service.dart';
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
  StreamSubscription<List<StreamOut>>? _swrSub;
  Completer<List<StreamOut>>? _pendingCompleter;
  final _connectSvc = ConnectivityService();
  // fire-and-forget callback'lerin eski nesil state'i kirletmesini önler
  int _gen = 0;
  // Post-load connectivity debounce: iOS geçiş sırasında 10+ event atar,
  // debounce bunları tek bir refresh'e indirger.
  Timer? _refreshDebounce;
  // Eş zamanlı refresh() çağrılarını engeller.
  bool _refreshing = false;

  @override
  FutureOr<LiveListState> build() async {
    // WS bağlantısı: her build'de yenile (invalidateSelf sonrası onDispose null'ladı).
    _wsSub?.cancel();
    _wsSub = ref.read(wsServiceProvider).messageStream.stream.listen(_onWsMessage);

    // Connectivity listener: her build'de taze lokal subscription (story provider'larla aynı pattern).
    // ??= KULLANILMAZ — onDispose cancel eder ama null yapmaz; bir sonraki build
    // cancel edilmiş subscription'ı görür ve yeni listener oluşturmaz (sessiz ölür).
    StreamSubscription<bool>? connectSub;
    connectSub = _connectSvc.onConnectivityChanged.listen((online) {
      if (online && state.isLoading && !state.hasValue) {
        // Initial load takılmış (iOS WiFi→mobile): zombie temizle, yeniden yükle.
        // cancel() önce: bu build'in listener'ı bitti, invalidateSelf yeni build'de taze listener açar.
        debugPrint('[LiveList] network online during load — zombie temizleniyor, yenileniyor');
        ApiService.clearInFlight('/streams/');
        if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
          _pendingCompleter!.complete([]);
        }
        connectSub?.cancel();
        ref.invalidateSelf();
      } else if (state.value != null) {
        final wasOffline = state.value!.isOffline;
        state = AsyncValue.data(state.value!.copyWith(isOffline: !online));
        if (online && wasOffline) {
          // iOS geçişte 10+ event atar; debounce bunları tek refresh'e indirir.
          // Her event (online veya offline) zamanlayıcıyı sıfırlar; sadece
          // online+wasOffline durumunda yeniden başlatır.
          _refreshDebounce?.cancel();
          _refreshDebounce = Timer(
            const Duration(milliseconds: 500),
            () => refresh(bypassCache: true),
          );
        } else {
          _refreshDebounce?.cancel();
        }
      }
    });

    ref.onDispose(() {
      _wsSub?.cancel();
      _wsSub = null;
      connectSub?.cancel();
      _refreshDebounce?.cancel();
      _swrSub?.cancel();
      if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
        _pendingCompleter!.complete([]);
      }
    });

    return _loadInitial(bypassCache: false);
  }

  Future<LiveListState> _loadInitial({required bool bypassCache}) async {
    final gen = ++_gen;
    debugPrint('[LiveList] _loadInitial start | gen=$gen bypassCache=$bypassCache');

    final token = await StorageService.getToken();
    final isLoggedIn = token != null;
    final isOnline = await _connectSvc.isConnected;
    debugPrint('[LiveList] token+conn done | isLoggedIn=$isLoggedIn isOnline=$isOnline gen=$gen');

    // ── Active streams: hemen başlat — SWR cache varsa ilk yield anlık olur ──
    _swrSub?.cancel();
    _swrSub = null;
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete([]);
    }
    _pendingCompleter = null;

    final completer = Completer<List<StreamOut>>();
    _pendingCompleter = completer;
    debugPrint('[LiveList] getActiveStreamsStream starting | gen=$gen');

    _swrSub = ref.read(streamServiceProvider)
        .getActiveStreamsStream(bypassCache: bypassCache)
        .listen(
      (streams) {
        debugPrint('[LiveList] activeStreams yield: ${streams.length} | gen=$gen done=${completer.isCompleted}');
        _pendingCompleter = null;
        if (!completer.isCompleted) {
          completer.complete(streams);
        } else if (state.value != null) {
          state = AsyncValue.data(state.value!.copyWith(streams: streams));
        }
      },
      onError: (e, st) {
        debugPrint('[LiveList] activeStreams error: $e | gen=$gen');
        _pendingCompleter = null;
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        } else if (state.value == null || state.value!.streams.isEmpty) {
          state = AsyncValue.error(e, st);
        }
      },
      onDone: () {
        debugPrint('[LiveList] activeStreams done | gen=$gen');
        _pendingCompleter = null;
        if (!completer.isCompleted) completer.complete([]);
      },
    );

    // ── Recommended + suggested: paralel + fire-and-forget ──────────────────
    // Active streams'i BEKLETMİYOR. Tamamlanınca state'i sessizce günceller.
    // _gen == gen guard: eski neslin callback'leri yeni state'i kirletmez.
    if (isLoggedIn) {
      debugPrint('[LiveList] rec+sugg starting (paralel, fire-and-forget) | gen=$gen');

      ref.read(streamServiceProvider)
          .getRecommendedStreams()
          .timeout(const Duration(seconds: 20))
          .then(
            (rec) {
              debugPrint('[LiveList] rec done: ${rec.length} | gen=$gen cur=$_gen');
              if (_gen == gen && state.value != null) {
                state = AsyncValue.data(state.value!.copyWith(recommended: rec));
              }
            },
            onError: (e) => debugPrint('[LiveList] rec error: $e | gen=$gen'),
          );

      ref.read(streamServiceProvider)
          .getSuggestedStreamers()
          .timeout(const Duration(seconds: 20))
          .then(
            (sugg) {
              debugPrint('[LiveList] sugg done: ${sugg.length} | gen=$gen cur=$_gen');
              if (_gen == gen && state.value != null) {
                state = AsyncValue.data(state.value!.copyWith(
                  suggestedStreamers: sugg.cast<Map<String, dynamic>>(),
                ));
              }
            },
            onError: (e) => debugPrint('[LiveList] sugg error: $e | gen=$gen'),
          );
    }

    // ── Active streams tamamlanmasını bekle ──────────────────────────────────
    // SWR mantığı: 3s içinde yanıt gelmezse boş liste döndür, UI hızlı açılır.
    // _swrSub hâlâ aktif — HTTP yanıtı gelince listener state.copyWith ile günceller.
    // Birincil retry mekanizması: connectivity event (clearInFlight + invalidateSelf).
    debugPrint('[LiveList] waiting for activeStreams | gen=$gen');
    final activeStreams = await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint('[LiveList] activeStreams timeout 3s — UI hızlı açılıyor | gen=$gen');
        if (!completer.isCompleted) completer.complete([]);
        return <StreamOut>[];
      },
    );
    debugPrint('[LiveList] _loadInitial done: ${activeStreams.length} streams | gen=$gen');

    return LiveListState(
      streams: activeStreams,
      recommended: const [],   // fire-and-forget yukarıda state.copyWith ile günceller
      suggestedStreamers: const [],
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
    // Eş zamanlı refresh çağrılarını engelle (iOS geçişte debounce sonrası bile
    // iki çağrı gelebilir; guard bunu önler).
    if (_refreshing) return;
    _refreshing = true;
    final hadData = state.value != null;
    if (!hadData) {
      state = const AsyncValue.loading();
    }
    try {
      final prev = state.value;
      final newState = await _loadInitial(bypassCache: bypassCache);
      // rec/sugg fire-and-forget henüz tamamlanmadıysa eski veriyi koru.
      state = AsyncValue.data(newState.copyWith(
        recommended: prev?.recommended ?? const [],
        suggestedStreamers: prev?.suggestedStreamers ?? const [],
      ));
    } catch (e, st) {
      if (!hadData) {
        state = AsyncValue.error(e, st);
      }
    } finally {
      _refreshing = false;
    }
  }
}

final liveListViewModelProvider = AsyncNotifierProvider<LiveListViewModel, LiveListState>(() {
  return LiveListViewModel();
});
