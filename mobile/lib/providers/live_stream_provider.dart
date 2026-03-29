import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stream.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';

/// Kullanıcının takip ettiği kişilerin aktif canlı yayınlarını yönetir.
///
/// Stale-While-Revalidate mimarisi:
///   1. Kasa'da veri varsa anında UI'a basılır (sıfır spinner).
///   2. Arka planda API isteği atılır; gelince kasa güncellenir, UI sessizce yenilenir.
///   3. API hatası olursa: kasa varsa hata yutulur; kasa yoksa hata fırlatılır.
class FollowedStreamsNotifier
    extends AutoDisposeAsyncNotifier<List<StreamOut>> {
  bool _disposed = false;

  @override
  Future<List<StreamOut>> build() async {
    ref.onDispose(() => _disposed = true);

    // ── 1. Kasa kontrolü ────────────────────────────────────────────────────
    final cached =
        await StorageService.getCachedData(StorageService.cacheStreams);
    if (cached != null) {
      final cachedList = (cached as List)
          .map((e) => StreamOut.fromJson(e as Map<String, dynamic>))
          .toList();
      // Cache veriyi anında döndür; arka planda revalidate başlat.
      Future.microtask(_revalidate);
      return cachedList;
    }

    // ── 2. Kasa boş → direkt API ─────────────────────────────────────────
    return _revalidate();
  }

  /// API'den taze veri çeker, kasayı günceller, state'i yeniler.
  Future<List<StreamOut>> _revalidate() async {
    try {
      final fresh = await StreamService.getFollowedLiveStreams();
      await StorageService.cacheData(
        StorageService.cacheStreams,
        fresh.map((e) => e.toJson()).toList(),
      );
      if (!_disposed) state = AsyncData(fresh);
      return fresh;
    } catch (e, st) {
      // Kasa'dan basılmış veri varsa hatayı yut; kullanıcı eski veriyi görür.
      if (state is AsyncData) {
        debugPrint('[FollowedStreams] API hatası (cache korunuyor): $e');
        return (state as AsyncData<List<StreamOut>>).value;
      }
      // Kasa da boşsa hatayı yukarı ilet.
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Pull-to-refresh veya manuel tetikleme için.
  Future<void> refresh() async {
    state = const AsyncLoading();
    await _revalidate();
  }
}

final followedStreamsProvider =
    AsyncNotifierProvider.autoDispose<FollowedStreamsNotifier, List<StreamOut>>(
  FollowedStreamsNotifier.new,
);
