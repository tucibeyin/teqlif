import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/storage_service.dart';
import '../../../services/story_service.dart';
import '../../../services/stream_service.dart';
import '../../../models/stream.dart';
import '../../../models/story.dart';

class StoryViewerState {
  final int? currentUserId;

  const StoryViewerState({
    this.currentUserId,
  });

  StoryViewerState copyWith({
    int? currentUserId,
  }) {
    return StoryViewerState(
      currentUserId: currentUserId ?? this.currentUserId,
    );
  }
}

class StoryViewerViewModel extends AsyncNotifier<StoryViewerState> {
  @override
  FutureOr<StoryViewerState> build() async {
    final info = await StorageService.getUserInfo();
    return StoryViewerState(
      currentUserId: info?['id'] as int?,
    );
  }

  Future<Map<String, dynamic>?> toggleLike(int storyId) async {
    try {
      final result = await StoryService.toggleLike(storyId);
      return result;
    } catch (e) {
      return null;
    }
  }

  Future<bool> deleteStory(int storyId) async {
    try {
      await StoryService.deleteStory(storyId);
      return true;
    } catch (e) {
      return false;
    }
  }

  void recordView(int storyId) {
    StoryService.recordStoryView(storyId).catchError((_) {});
  }

  Future<StreamOut?> getActiveStreamForUser(int userId) async {
    try {
      final streams = await StreamService.getActiveStreams();
      final idx = streams.indexWhere((s) => s.userId == userId);
      if (idx != -1) return streams[idx];
    } catch (e) {
      // Ignore
    }
    return null;
  }
}

final storyViewerViewModelProvider = AsyncNotifierProvider<StoryViewerViewModel, StoryViewerState>(() {
  return StoryViewerViewModel();
});

// ── Viewers Sheet ViewModel ───────────────────────────────────────────────────

class StoryViewersViewModel extends AutoDisposeFamilyAsyncNotifier<List<StoryViewer>, int> {
  @override
  FutureOr<List<StoryViewer>> build(int arg) async {
    return StoryService.getStoryViewers(arg);
  }
}

final storyViewersViewModelProvider = AutoDisposeAsyncNotifierProviderFamily<StoryViewersViewModel, List<StoryViewer>, int>(() {
  return StoryViewersViewModel();
});
