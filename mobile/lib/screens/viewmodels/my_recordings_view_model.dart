import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/recording.dart';
import '../../services/localization_service.dart';
import '../../services/recordings/recording_repository.dart';
import '../../utils/error_helper.dart';

class MyRecordingsNotifier extends AutoDisposeAsyncNotifier<List<RecordingItem>> {
  @override
  FutureOr<List<RecordingItem>> build() => _load();

  Future<List<RecordingItem>> _load({bool bypassCache = false}) async {
    final result = await ref
        .read(recordingRepositoryProvider)
        .getMyRecordings(bypassCache: bypassCache);

    switch (result) {
      case Ok(:final value):
        return value;
      case Err(:final error):
        handleError(error, ref.read(localizationProvider));
        return state.valueOrNull ?? [];
    }
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _load(bypassCache: true));
  }
}

final myRecordingsProvider =
    AsyncNotifierProvider.autoDispose<MyRecordingsNotifier, List<RecordingItem>>(
  MyRecordingsNotifier.new,
);
