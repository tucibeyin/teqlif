import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/recording.dart';
import '../cache_service.dart';

class RecordingsCacheService {
  static const _keyMyRecordings = 'recordings:my';
  static const _ttlMyRecordings = Duration(minutes: 3);

  static const _ttlRecordingUrlFallback     = Duration(minutes: 55);
  static const _ttlRecordingSummaryFallback = Duration(minutes: 10);
  static const _ttlSafetyMargin             = Duration(minutes: 5);

  String _keyUrl(int streamId) => 'recording_url:$streamId';
  String _keySummary(int streamId) => 'recording_summary:$streamId';

  /// `expiresAt` verilmişse o ana kadar minus güvenlik marjını TTL olarak kullan.
  /// Kalan süre marjdan küçükse fallback TTL döner.
  Duration _ttlUntil(DateTime? expiresAt, Duration fallback) {
    if (expiresAt == null) return fallback;
    final remaining = expiresAt.difference(DateTime.now()) - _ttlSafetyMargin;
    return remaining > fallback ? remaining : fallback;
  }

  // ── My Recordings (LIFECYCLE, 3 min) ──────────────────────────────────────

  List<RecordingItem>? getMyRecordings() {
    final raw = CacheService.getData(_keyMyRecordings);
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
    await CacheService.saveData(
      _keyMyRecordings,
      items.map((e) => e.toJson()).toList(),
      ttl: _ttlMyRecordings,
    );
  }

  Future<void> clearMyRecordings() => CacheService.clearData(_keyMyRecordings);

  // ── Recording URL (EPHEMERAL, 55 min) ─────────────────────────────────────

  RecordingUrlData? getRecordingUrl(int streamId) {
    final raw = CacheService.getData(_keyUrl(streamId));
    if (raw == null) return null;
    try {
      return RecordingUrlData.fromJson(raw as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRecordingUrl(int streamId, RecordingUrlData data) async {
    await CacheService.saveData(
      _keyUrl(streamId),
      data.toJson(),
      ttl: _ttlUntil(data.expiresAt, _ttlRecordingUrlFallback),
    );
  }

  Future<void> clearRecordingUrl(int streamId) =>
      CacheService.clearData(_keyUrl(streamId));

  // ── Recording Summary (LIFECYCLE, 10 min) ─────────────────────────────────

  RecordingDetail? getRecordingSummary(int streamId) {
    final raw = CacheService.getData(_keySummary(streamId));
    if (raw == null) return null;
    try {
      return RecordingDetail.fromJson(raw as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRecordingSummary(int streamId, RecordingDetail detail) async {
    await CacheService.saveData(
      _keySummary(streamId),
      detail.toJson(),
      ttl: _ttlUntil(detail.recordingExpiresAt, _ttlRecordingSummaryFallback),
    );
  }

  Future<void> clearRecordingSummary(int streamId) =>
      CacheService.clearData(_keySummary(streamId));
}

final recordingsCacheServiceProvider = Provider<RecordingsCacheService>(
    (_) => RecordingsCacheService());
