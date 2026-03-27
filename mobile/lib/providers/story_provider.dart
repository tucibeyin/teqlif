import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/story.dart';
import '../services/story_service.dart';

/// Takip edilen kullanıcıların hybrid (video + canlı yayın) gruplanmış
/// hikayelerini yönetir.
///
/// Kullanım:
///   - `ref.watch(storyGroupsProvider)` → `AsyncValue<List<UserStoryGroup>>`
///   - Yenileme: `ref.invalidate(storyGroupsProvider)`
///
/// autoDispose: Ekran dispose olunca veri bellekten temizlenir;
/// tekrar açıldığında yeni istek atılır.
class StoryGroupsNotifier
    extends AutoDisposeAsyncNotifier<List<UserStoryGroup>> {
  @override
  Future<List<UserStoryGroup>> build() =>
      StoryService.getFollowingStories();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(StoryService.getFollowingStories);
  }
}

final storyGroupsProvider = AsyncNotifierProvider.autoDispose<
    StoryGroupsNotifier, List<UserStoryGroup>>(
  StoryGroupsNotifier.new,
);
