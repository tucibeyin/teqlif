import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

// ── Takip edilen kullanıcıların hikayeleri ────────────────────────────────────

/// SWR akışı: Hive'dan anlık cache → arka planda HTTP → sessiz güncelleme.
class StoryGroupsNotifier
    extends AutoDisposeAsyncNotifier<List<UserStoryGroup>> {
  bool _disposed = false;

  static const _url = '$kBaseUrl/stories/following';

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
    ref.onDispose(() => _disposed = true);

    List<UserStoryGroup>? last;
    await for (final groups in ApiService.get<List<UserStoryGroup>>(
      url: _url,
      cacheKey: StorageService.cacheStories,
      cacheTtl: const Duration(minutes: 2),
      fromJson: _parse,
    )) {
      last = groups;
      if (!_disposed) state = AsyncData(groups);
    }
    return last ?? [];
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      await for (final groups in ApiService.get<List<UserStoryGroup>>(
        url: _url,
        cacheKey: StorageService.cacheStories,
        cacheTtl: const Duration(minutes: 2),
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

  static const _url = '$kBaseUrl/stories/mine';

  static List<StoryItem> _parse(dynamic raw) {
    // Backend {items:[...], total:N} veya düz liste döndürebilir
    final list = raw is Map ? (raw['items'] as List? ?? []) : (raw as List);
    return list.cast<Map<String, dynamic>>().map(StoryItem.fromJson).toList();
  }

  @override
  Future<List<StoryItem>> build() async {
    ref.onDispose(() => _disposed = true);

    List<StoryItem>? last;
    await for (final items in ApiService.get<List<StoryItem>>(
      url: _url,
      cacheKey: StorageService.cacheMyStories,
      cacheTtl: const Duration(minutes: 2),
      fromJson: _parse,
    )) {
      last = items;
      if (!_disposed) state = AsyncData(items);
    }
    return last ?? [];
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      await for (final items in ApiService.get<List<StoryItem>>(
        url: _url,
        cacheKey: StorageService.cacheMyStories,
        cacheTtl: const Duration(minutes: 2),
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
