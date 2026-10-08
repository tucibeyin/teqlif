import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../core/result.dart';
import '../../models/recording.dart';
import '../../services/localization_service.dart';
import '../../services/recordings/recording_repository.dart';
import '../../utils/error_helper.dart';

class RecordingDetailState {
  final RecordingUrlData? urlData;
  final RecordingDetail? summary;
  final bool summaryLoading;
  final String? urlError;

  const RecordingDetailState({
    this.urlData,
    this.summary,
    this.summaryLoading = false,
    this.urlError,
  });

  RecordingDetailState copyWith({
    RecordingUrlData? urlData,
    RecordingDetail? summary,
    bool? summaryLoading,
    String? urlError,
    bool clearUrlError = false,
  }) {
    return RecordingDetailState(
      urlData: urlData ?? this.urlData,
      summary: summary ?? this.summary,
      summaryLoading: summaryLoading ?? this.summaryLoading,
      urlError: clearUrlError ? null : (urlError ?? this.urlError),
    );
  }
}

class RecordingDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<RecordingDetailState, int> {
  late int _streamId;

  @override
  FutureOr<RecordingDetailState> build(int streamId) async {
    _streamId = streamId;
    return _loadAll();
  }

  Future<RecordingDetailState> _loadAll() async {
    final urlResult = await ref
        .read(recordingRepositoryProvider)
        .getRecordingUrl(_streamId);

    RecordingUrlData? urlData;
    String? urlError;

    switch (urlResult) {
      case Ok(:final value):
        urlData = value;
      case Err(:final error):
        urlError = _errorMessage(error);
    }

    return RecordingDetailState(urlData: urlData, urlError: urlError);
  }

  /// 403 sonrası presigned URL'yi yeniden çeker (cache bypass).
  Future<void> recoverUrl() async {
    final current = state.valueOrNull ?? const RecordingDetailState();
    state = AsyncValue.data(current.copyWith(clearUrlError: true));

    final result = await ref
        .read(recordingRepositoryProvider)
        .getRecordingUrl(_streamId, bypassCache: true);

    switch (result) {
      case Ok(:final value):
        state = AsyncValue.data(
          (state.valueOrNull ?? const RecordingDetailState())
              .copyWith(urlData: value, clearUrlError: true),
        );
      case Err(:final error):
        final msg = _errorMessage(error);
        handleError(error, ref.read(localizationProvider));
        state = AsyncValue.data(
          (state.valueOrNull ?? const RecordingDetailState())
              .copyWith(urlError: msg),
        );
    }
  }

  /// Commerce özet verisi — talep üzerine yüklenir.
  Future<void> fetchSummary() async {
    final current = state.valueOrNull ?? const RecordingDetailState();
    if (current.summary != null) return;

    state = AsyncValue.data(current.copyWith(summaryLoading: true));

    final result = await ref
        .read(recordingRepositoryProvider)
        .getRecordingSummary(_streamId);

    switch (result) {
      case Ok(:final value):
        state = AsyncValue.data(
          (state.valueOrNull ?? const RecordingDetailState())
              .copyWith(summary: value, summaryLoading: false),
        );
      case Err(:final error):
        handleError(error, ref.read(localizationProvider));
        state = AsyncValue.data(
          (state.valueOrNull ?? const RecordingDetailState())
              .copyWith(summaryLoading: false),
        );
    }
  }

  String _errorMessage(Object error) {
    if (error is AppException) return error.code;
    return error.toString();
  }
}

final recordingDetailProvider = AsyncNotifierProvider.autoDispose
    .family<RecordingDetailNotifier, RecordingDetailState, int>(
  RecordingDetailNotifier.new,
);
