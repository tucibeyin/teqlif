import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/story.dart';
import '../services/storage_service.dart';
import '../services/story_service.dart';

/// Takip edilen kullanıcıların hikayelerini yönetir.
///
/// Stale-While-Revalidate: kasa varsa anında göster, arka planda API'den güncelle.
class StoryGroupsNotifier
    extends AutoDisposeAsyncNotifier<List<UserStoryGroup>> {
  bool _disposed = false;

  @override
  Future<List<UserStoryGroup>> build() async {
    ref.onDispose(() => _disposed = true);

    final cached =
        await StorageService.getCachedData(StorageService.cacheStories);
    if (cached != null) {
      final cachedList = (cached as List)
          .map((e) => UserStoryGroup.fromJson(e as Map<String, dynamic>))
          .toList();
      Future.microtask(_revalidate);
      return cachedList;
    }

    return _revalidate();
  }

  Future<List<UserStoryGroup>> _revalidate() async {
    try {
      final fresh = await StoryService.getFollowingStories();
      await StorageService.cacheData(
        StorageService.cacheStories,
        fresh.map((e) => e.toJson()).toList(),
      );
      if (!_disposed) state = AsyncData(fresh);
      return fresh;
    } catch (e, st) {
      if (state is AsyncData) {
        debugPrint('[StoryGroups] API hatası (cache korunuyor): $e');
        return (state as AsyncData<List<UserStoryGroup>>).value;
      }
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    await _revalidate();
  }
}

final storyGroupsProvider = AsyncNotifierProvider.autoDispose<
    StoryGroupsNotifier, List<UserStoryGroup>>(
  StoryGroupsNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────

/// Giriş yapan kullanıcının kendi aktif hikayelerini yönetir.
class MyStoriesNotifier extends AutoDisposeAsyncNotifier<List<StoryItem>> {
  bool _disposed = false;

  @override
  Future<List<StoryItem>> build() async {
    ref.onDispose(() => _disposed = true);

    final cached =
        await StorageService.getCachedData(StorageService.cacheMyStories);
    if (cached != null) {
      final cachedList = (cached as List)
          .map((e) => StoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      Future.microtask(_revalidate);
      return cachedList;
    }

    return _revalidate();
  }

  Future<List<StoryItem>> _revalidate() async {
    try {
      final fresh = await StoryService.getMyStories();
      await StorageService.cacheData(
        StorageService.cacheMyStories,
        fresh.map((e) => e.toJson()).toList(),
      );
      if (!_disposed) state = AsyncData(fresh);
      return fresh;
    } catch (e, st) {
      if (state is AsyncData) {
        debugPrint('[MyStories] API hatası (cache korunuyor): $e');
        return (state as AsyncData<List<StoryItem>>).value;
      }
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    await _revalidate();
  }
}

final myStoriesProvider =
    AsyncNotifierProvider.autoDispose<MyStoriesNotifier, List<StoryItem>>(
  MyStoriesNotifier.new,
);
