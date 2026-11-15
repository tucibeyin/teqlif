import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_exception.dart';
import '../core/network/api_client.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/storage_service.dart';

// ── Takip edilen kullanıcıların hikayeleri ────────────────────────────────────

/// SWR akışı: Hive'dan anlık cache → arka planda HTTP → sessiz güncelleme.
class StoryGroupsNotifier
    extends AutoDisposeAsyncNotifier<List<UserStoryGroup>> {
  bool _disposed = false;
  // iOS geçişte rapid event'ler: her yeni build yeni listener → sonsuz döngü.
  // Bu flag build'ler arası kalıcıdır (AutoDisposeAsyncNotifier instance'ı
  // watcher varsa yeniden kullanılır). Data/error gelince sıfırlanır.
  bool _connectivityRetrying = false;
  // Failsafe'den sonra tek otomatik yeniden deneme. Dispose edilince iptal edilir.
  Timer? _retryTimer;

  String get _url => '${ref.read(apiClientProvider).config.baseUrl}/stories/following';

  static List<UserStoryGroup> _parse(dynamic raw) {
    final result = <UserStoryGroup>[];
    for (final e in (raw as List)) {
      try {
        result.add(UserStoryGroup.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('[StoryGroups] parse hatası: $err | veri: $e');
      }
    }
    return result;
  }

  @override
  Future<List<UserStoryGroup>> build() async {
    _disposed = false; // AutoDisposeAsyncNotifier instance'ı yeniden kullanır — reset zorunlu
    debugPrint('[StoryGroups] build start | _disposed=$_disposed');
    ref.onDispose(() { _disposed = true; _retryTimer?.cancel(); debugPrint('[StoryGroups] disposed'); });
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);

    // Failsafe: WiFi→mobile geçişinde iOS zaman zaman HTTP timeout'unu tetiklemez.
    // 25s sonra hâlâ AsyncLoading ise error state'e geçip shimmer döngüsünü kır.
    // Ardından 10s bekleyip tek otomatik deneme yapar — iOS bağlantı geçişi
    // bu sürede tamamlanır ve yeni istek mobile üzerinden çıkar.
    final failsafe = Timer(const Duration(seconds: 25), () {
      if (!_disposed && state.isLoading && !state.hasValue) {
        debugPrint('[StoryGroups] failsafe — 25s geçti, hâlâ yükleniyor');
        _connectivityRetrying = false;
        state = AsyncError(const NetworkException(), StackTrace.empty);
        _retryTimer = Timer(const Duration(seconds: 10), () {
          if (!_disposed && state.hasError && !_connectivityRetrying) {
            debugPrint('[StoryGroups] failsafe sonrası otomatik yeniden deneme');
            _connectivityRetrying = true;
            ApiService.clearInFlight('/stories/');
            ref.invalidateSelf();
          }
        });
      }
    });
    ref.onDispose(failsafe.cancel);

    // Network geçişi (WiFi→mobile) tamamlanınca zombie _inFlight'ı temizle ve
    // provider'ı yenile — yeni build mobile üzerinde taze istek yapar.
    // _connectivityRetrying: build'ler arası cascadeyi önler — iOS'un rapid
    // event'leri nedeniyle her yeni build tekrar invalidateSelf yapmasın.
    // hasError durumu: failsafe ateşlenmiş ama bağlantı geri geldi → retry.
    StreamSubscription<bool>? connectSub;
    connectSub = ConnectivityService().onConnectivityChanged.listen((online) {
      if (!online || _disposed || _connectivityRetrying) return;
      final shouldRetry = (state.isLoading && !state.hasValue) || state.hasError;
      if (shouldRetry) {
        _connectivityRetrying = true;
        debugPrint('[StoryGroups] network online — provider yenileniyor (state: ${state.runtimeType})');
        ApiService.clearInFlight('/stories/');
        connectSub?.cancel();
        ref.invalidateSelf();
      }
    });
    ref.onDispose(() => connectSub?.cancel());

    List<UserStoryGroup>? last;
    try {
      await for (final groups in ref.read(apiServiceProvider).get<List<UserStoryGroup>>(
        url: _url,
        cacheKey: StorageService.cacheStories,
        cacheTtl: const Duration(minutes: 5),
        fromJson: _parse,
      )) {
        debugPrint('[StoryGroups] data: ${groups.length} groups | disposed=$_disposed');
        last = groups;
        if (!_disposed) {
          _connectivityRetrying = false; // başarı → sonraki geçiş için sıfırla
          _retryTimer?.cancel();
          state = AsyncData(groups);
        }
      }
    } catch (e) {
      debugPrint('[StoryGroups] build error: $e');
      _connectivityRetrying = false;
      rethrow;
    }
    _connectivityRetrying = false;
    debugPrint('[StoryGroups] build done | last=${last?.length}');
    return last ?? [];
  }

  Future<void> refresh() async {
    debugPrint('[StoryGroups] refresh | isLoading=${state.isLoading} hasValue=${state.hasValue}');
    // build() hâlâ çalışıyorsa (pure AsyncLoading) refresh gereksiz — atla.
    if (state.isLoading && !state.hasValue) return;
    // Mevcut veri varsa shimmer gösterme — sadece sessizce güncelle.
    if (!state.hasValue) state = const AsyncLoading();
    try {
      await for (final groups in ref.read(apiServiceProvider).get<List<UserStoryGroup>>(
        url: _url,
        cacheKey: StorageService.cacheStories,
        cacheTtl: const Duration(minutes: 5),
        bypassCache: true,
        fromJson: _parse,
      )) {
        if (!_disposed) state = AsyncData(groups);
      }
    } catch (e) {
      debugPrint('[StoryGroups] refresh hatası: $e');
      if (!_disposed && state is AsyncLoading) {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }
}

final storyGroupsProvider = AsyncNotifierProvider.autoDispose<
    StoryGroupsNotifier, List<UserStoryGroup>>(
  StoryGroupsNotifier.new,
);

// ── Kullanıcının kendi hikayeleri ─────────────────────────────────────────────

class MyStoriesNotifier extends AutoDisposeAsyncNotifier<List<StoryItem>> {
  bool _disposed = false;
  bool _connectivityRetrying = false;
  Timer? _retryTimer;

  String get _url => '${ref.read(apiClientProvider).config.baseUrl}/stories/mine';

  static List<StoryItem> _parse(dynamic raw) {
    // Backend {items:[...], total:N} veya düz liste döndürebilir
    final list = raw is Map ? (raw['items'] as List? ?? []) : (raw as List);
    return list.cast<Map<String, dynamic>>().map(StoryItem.fromJson).toList();
  }

  @override
  Future<List<StoryItem>> build() async {
    _disposed = false; // AutoDisposeAsyncNotifier instance'ı yeniden kullanır — reset zorunlu
    debugPrint('[MyStories] build start | _disposed=$_disposed');
    ref.onDispose(() { _disposed = true; _retryTimer?.cancel(); debugPrint('[MyStories] disposed'); });
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);

    final failsafe = Timer(const Duration(seconds: 25), () {
      if (!_disposed && state.isLoading && !state.hasValue) {
        debugPrint('[MyStories] failsafe — 25s geçti, hâlâ yükleniyor');
        _connectivityRetrying = false;
        state = AsyncError(const NetworkException(), StackTrace.empty);
        _retryTimer = Timer(const Duration(seconds: 10), () {
          if (!_disposed && state.hasError && !_connectivityRetrying) {
            debugPrint('[MyStories] failsafe sonrası otomatik yeniden deneme');
            _connectivityRetrying = true;
            ApiService.clearInFlight('/stories/');
            ref.invalidateSelf();
          }
        });
      }
    });
    ref.onDispose(failsafe.cancel);

    StreamSubscription<bool>? connectSub;
    connectSub = ConnectivityService().onConnectivityChanged.listen((online) {
      if (!online || _disposed || _connectivityRetrying) return;
      final shouldRetry = (state.isLoading && !state.hasValue) || state.hasError;
      if (shouldRetry) {
        _connectivityRetrying = true;
        debugPrint('[MyStories] network online — provider yenileniyor (state: ${state.runtimeType})');
        ApiService.clearInFlight('/stories/');
        connectSub?.cancel();
        ref.invalidateSelf();
      }
    });
    ref.onDispose(() => connectSub?.cancel());

    List<StoryItem>? last;
    try {
      await for (final items in ref.read(apiServiceProvider).get<List<StoryItem>>(
        url: _url,
        cacheKey: StorageService.cacheMyStories,
        cacheTtl: const Duration(minutes: 5),
        fromJson: _parse,
      )) {
        debugPrint('[MyStories] data: ${items.length} items | disposed=$_disposed');
        last = items;
        if (!_disposed) {
          _connectivityRetrying = false;
          _retryTimer?.cancel();
          state = AsyncData(items);
        }
      }
    } catch (e) {
      debugPrint('[MyStories] build error: $e');
      _connectivityRetrying = false;
      rethrow;
    }
    _connectivityRetrying = false;
    debugPrint('[MyStories] build done | last=${last?.length}');
    return last ?? [];
  }

  Future<void> refresh() async {
    debugPrint('[MyStories] refresh | isLoading=${state.isLoading} hasValue=${state.hasValue}');
    if (state.isLoading && !state.hasValue) return;
    if (!state.hasValue) state = const AsyncLoading();
    try {
      await for (final items in ref.read(apiServiceProvider).get<List<StoryItem>>(
        url: _url,
        cacheKey: StorageService.cacheMyStories,
        cacheTtl: const Duration(minutes: 5),
        bypassCache: true,
        fromJson: _parse,
      )) {
        if (!_disposed) state = AsyncData(items);
      }
    } catch (e) {
      debugPrint('[MyStories] refresh hatası: $e');
      if (!_disposed && state is AsyncLoading) {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }
}

final myStoriesProvider =
    AsyncNotifierProvider.autoDispose<MyStoriesNotifier, List<StoryItem>>(
  MyStoriesNotifier.new,
);
