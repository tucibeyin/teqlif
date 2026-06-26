import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api.dart';
import '../models/stream.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Kullanıcının takip ettiği kişilerin aktif canlı yayınlarını yönetir.
///
/// Stale-While-Revalidate (SWR) akışı [ApiService.get] aracılığıyla:
///   1. Hive'dan **senkron** eski veri → UI anında render edilir.
///   2. Arka planda HTTP isteği → cache güncellenir, UI sessizce yenilenir.
///   3. Ağ hatası + geçerli cache → hata yutulur, eski veri korunur.
class FollowedStreamsNotifier
    extends AutoDisposeAsyncNotifier<List<StreamOut>> {
  bool _disposed = false;

  static const _url = '$kBaseUrl/streams/following/live';

  static List<StreamOut> _parse(dynamic raw) =>
      (raw as List)
          .cast<Map<String, dynamic>>()
          .map(StreamOut.fromJson)
          .toList();

  @override
  Future<List<StreamOut>> build() async {
    ref.onDispose(() => _disposed = true);

    List<StreamOut>? last;
    await for (final batch in ApiService.get<List<StreamOut>>(
      url: _url,
      cacheKey: StorageService.cacheStreams,
      cacheTtl: const Duration(minutes: 3),
      fromJson: _parse,
    )) {
      last = batch;
      if (!_disposed) state = AsyncData(batch);
    }
    return last ?? [];
  }

  /// Pull-to-refresh veya manuel tetikleme: cache READ atlanır,
  /// ağdan doğrudan çeker ve başarılıysa cache'i günceller.
  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      await for (final batch in ApiService.get<List<StreamOut>>(
        url: _url,
        cacheKey: StorageService.cacheStreams,
        cacheTtl: const Duration(minutes: 3),
        bypassCache: true,
        fromJson: _parse,
      )) {
        if (!_disposed) state = AsyncData(batch);
      }
    } catch (e) {
      debugPrint('[FollowedStreams] refresh hatası: $e');
      if (!_disposed && state is AsyncLoading) {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }
}

final followedStreamsProvider =
    AsyncNotifierProvider.autoDispose<FollowedStreamsNotifier, List<StreamOut>>(
  FollowedStreamsNotifier.new,
);
