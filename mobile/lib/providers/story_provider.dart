import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/story.dart';
import '../services/story_service.dart';

/// Takip edilen kullanıcıların kullanıcı bazlı gruplanmış hikayelerini yönetir.
///
/// Kullanım:
///   - `ref.watch(groupedStoriesProvider)` → `AsyncValue<List<UserStoryGroup>>`
///   - Yenileme: `ref.invalidate(groupedStoriesProvider)`
///
/// autoDispose: Ekran dispose olunca veri bellekten temizlenir;
/// tekrar açıldığında yeni istek atılır.
class GroupedStoriesNotifier
    extends AutoDisposeAsyncNotifier<List<UserStoryGroup>> {
  @override
  Future<List<UserStoryGroup>> build() => StoryService.getGroupedStories();

  /// Listeyi yeniden çeker (yükleme sonrası veya pull-to-refresh için).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(StoryService.getGroupedStories);
  }
}

final groupedStoriesProvider = AsyncNotifierProvider.autoDispose<
    GroupedStoriesNotifier, List<UserStoryGroup>>(
  GroupedStoriesNotifier.new,
);
