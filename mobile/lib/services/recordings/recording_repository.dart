import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/result.dart';
import '../../models/recording.dart';
import '../storage_service.dart';
import 'recordings_cache_service.dart';

class RecordingRepository {
  final ApiClient _api;
  final RecordingsCacheService _cache;

  RecordingRepository(this._api, this._cache);

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return _api.buildApiHeaders(token, json: false);
  }

  /// GET /recordings/my — son 30 günün kayıtları (liste).
  /// Cache: 3 dakika LIFECYCLE.
  Future<Result<List<RecordingItem>>> getMyRecordings({bool bypassCache = false}) async {
    if (!bypassCache) {
      final cached = _cache.getMyRecordings();
      if (cached != null) return Ok(cached);
    }
    final result = await _api.callListResult(
      () async => http.get(
        Uri.parse('${_api.config.baseUrl}/recordings/my'),
        headers: await _headers(),
      ),
    );
    switch (result) {
      case Ok(:final value):
        final items = value
            .cast<Map<String, dynamic>>()
            .map(RecordingItem.fromJson)
            .toList();
        await _cache.saveMyRecordings(items);
        return Ok(items);
      case Err(:final error):
        return Err(error);
    }
  }

  /// GET /streams/{streamId}/recording — presigned URL.
  /// Cache: 55 dakika EPHEMERAL.
  Future<Result<RecordingUrlData>> getRecordingUrl(int streamId, {bool bypassCache = false}) async {
    if (!bypassCache) {
      final cached = _cache.getRecordingUrl(streamId);
      if (cached != null) return Ok(cached);
    }
    final result = await _api.callResult(
      () async => http.get(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/recording'),
        headers: await _headers(),
      ),
    );
    switch (result) {
      case Ok(:final value):
        final data = RecordingUrlData.fromJson(value);
        await _cache.saveRecordingUrl(streamId, data);
        return Ok(data);
      case Err(:final error):
        return Err(error);
    }
  }

  /// GET /streams/{streamId}/recording-summary — ticaret özeti.
  /// Cache: 10 dakika LIFECYCLE.
  Future<Result<RecordingDetail>> getRecordingSummary(int streamId, {bool bypassCache = false}) async {
    if (!bypassCache) {
      final cached = _cache.getRecordingSummary(streamId);
      if (cached != null) return Ok(cached);
    }
    final result = await _api.callResult(
      () async => http.get(
        Uri.parse('${_api.config.baseUrl}/streams/$streamId/recording-summary'),
        headers: await _headers(),
      ),
    );
    switch (result) {
      case Ok(:final value):
        final detail = RecordingDetail.fromJson(value);
        await _cache.saveRecordingSummary(streamId, detail);
        return Ok(detail);
      case Err(:final error):
        return Err(error);
    }
  }
}

final recordingRepositoryProvider = Provider<RecordingRepository>((ref) =>
    RecordingRepository(
      ref.watch(apiClientProvider),
      ref.watch(recordingsCacheServiceProvider),
    ));
