import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stream.dart';
import '../services/stream_service.dart';

/// Kullanıcının takip ettiği kişilerin aktif canlı yayınlarını yönetir.
///
/// Kullanım:
///   - `ref.watch(followedStreamsProvider)` → `AsyncValue<List<StreamOut>>`
///   - Yenileme: `ref.refresh(followedStreamsProvider.future)`
///
/// Ekran dispose olduğunda (autoDispose) veri bellekten temizlenir;
/// tekrar açıldığında yeni istek atılır.
class FollowedStreamsNotifier extends AsyncNotifier<List<StreamOut>> {
  @override
  Future<List<StreamOut>> build() => StreamService.getFollowedLiveStreams();

  /// Listeyi yeniden çeker (pull-to-refresh veya manuel tetikleme için).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(StreamService.getFollowedLiveStreams);
  }
}

final followedStreamsProvider =
    AsyncNotifierProvider.autoDispose<FollowedStreamsNotifier, List<StreamOut>>(
  FollowedStreamsNotifier.new,
);
