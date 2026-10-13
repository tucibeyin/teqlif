import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/recording.dart';
import '../cache_service.dart';

class RecordingsCacheService {
  final CacheService _cache;
  RecordingsCacheService(this._cache);

  static const _keyMyRecordings = 'recordings:my';
  static const _ttlMyRecordings = Duration(minutes: 3);

  static const _ttlRecordingUrlFallback     = Duration(minutes: 55);
  static const _ttlRecordingSummaryFallback = Duration(minutes: 10);
  static const _ttlSafetyMargin             = Duration(minutes: 5);

  String _keyUrl(int streamId) => 'recording_url:$streamId';
  String _keySummary(int streamId) => 'recording_summary:$streamId';

  Duration _ttlUntil(DateTime? expiresAt, Duration fallback) {
    if (expiresAt == null) return fallback;
    final remaining = expiresAt.difference(DateTime.now()) - _ttlSafetyMargin;
    return remaining > fallback ? remaining : fallback;
  }

  // ── My Recordings (LIFECYCLE, 3 min) ──────────────────────────────────────

  List<RecordingItem>? getMyRecordings() {
    final raw = _cache.getData(_keyMyRecordings);
    if (raw == null) return null;
    try {
      return (raw as List)
          .cast<Map<String, dynamic>>()
          .map(RecordingItem.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMyRecordings(List<RecordingItem> items) async {
    await _cache.saveData(
      _keyMyRecordings,
      items.map((e) => e.toJson()).toList(),
      ttl: _ttlMyRecordings,
    );
  }

  Future<void> clearMyRecordings() => _cache.clearData(_keyMyRecordings);

  // ── Recording URL (EPHEMERAL, 55 min) ─────────────────────────────────────

  RecordingUrlData? getRecordingUrl(int streamId) {
    final raw = _cache.getData(_keyUrl(streamId));
    if (raw == null) return null;
    try {
      return RecordingUrlData.fromJson(raw as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRecordingUrl(int streamId, RecordingUrlData data) async {
    await _cache.saveData(
      _keyUrl(streamId),
      data.toJson(),
      ttl: _ttlUntil(data.expiresAt, _ttlRecordingUrlFallback),
    );
  }

  Future<void> clearRecordingUrl(int streamId) =>
      _cache.clearData(_keyUrl(streamId));

  // ── Recording Summary (LIFECYCLE, 10 min) ─────────────────────────────────

  RecordingDetail? getRecordingSummary(int streamId) {
    final raw = _cache.getData(_keySummary(streamId));
    if (raw == null) return null;
    try {
      return RecordingDetail.fromJson(raw as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRecordingSummary(int streamId, RecordingDetail detail) async {
    await _cache.saveData(
      _keySummary(streamId),
      detail.toJson(),
      ttl: _ttlUntil(detail.recordingExpiresAt, _ttlRecordingSummaryFallback),
    );
  }

  Future<void> clearRecordingSummary(int streamId) =>
      _cache.clearData(_keySummary(streamId));
}

final recordingsCacheServiceProvider = Provider<RecordingsCacheService>(
    (ref) => RecordingsCacheService(ref.watch(cacheServiceProvider)));
