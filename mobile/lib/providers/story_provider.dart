import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_exception.dart';
import '../core/network/api_client.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

// ── Takip edilen kullanıcıların hikayeleri ────────────────────────────────────

/// SWR akışı: Hive'dan anlık cache → arka planda HTTP → sessiz güncelleme.
class StoryGroupsNotifier
    extends AutoDisposeAsyncNotifier<List<UserStoryGroup>> {
  bool _disposed = false;

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
    debugPrint('[StoryGroups] build start | _disposed=$_disposed');
    ref.onDispose(() { _disposed = true; debugPrint('[StoryGroups] disposed'); });
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);

    // Failsafe: WiFi→mobile geçişinde iOS zaman zaman HTTP timeout'unu tetiklemez.
    // 25s sonra hâlâ AsyncLoading ise error state'e geçip shimmer döngüsünü kır.
    final failsafe = Timer(const Duration(seconds: 25), () {
      if (!_disposed && state.isLoading && !state.hasValue) {
        debugPrint('[StoryGroups] failsafe — 25s geçti, hâlâ yükleniyor');
        state = AsyncError(const NetworkException(), StackTrace.empty);
      }
    });
    ref.onDispose(failsafe.cancel);

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
        if (!_disposed) state = AsyncData(groups);
      }
    } catch (e) {
      debugPrint('[StoryGroups] build error: $e');
      rethrow;
    }
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

  String get _url => '${ref.read(apiClientProvider).config.baseUrl}/stories/mine';

  static List<StoryItem> _parse(dynamic raw) {
    // Backend {items:[...], total:N} veya düz liste döndürebilir
    final list = raw is Map ? (raw['items'] as List? ?? []) : (raw as List);
    return list.cast<Map<String, dynamic>>().map(StoryItem.fromJson).toList();
  }

  @override
  Future<List<StoryItem>> build() async {
    debugPrint('[MyStories] build start | _disposed=$_disposed');
    ref.onDispose(() { _disposed = true; debugPrint('[MyStories] disposed'); });
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);

    final failsafe = Timer(const Duration(seconds: 25), () {
      if (!_disposed && state.isLoading && !state.hasValue) {
        debugPrint('[MyStories] failsafe — 25s geçti, hâlâ yükleniyor');
        state = AsyncError(const NetworkException(), StackTrace.empty);
      }
    });
    ref.onDispose(failsafe.cancel);

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
        if (!_disposed) state = AsyncData(items);
      }
    } catch (e) {
      debugPrint('[MyStories] build error: $e');
      rethrow;
    }
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
