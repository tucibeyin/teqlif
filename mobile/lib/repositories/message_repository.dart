import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/network/api_client.dart';
import '../models/direct_message.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/offline_queue_service.dart';
import '../services/storage_service.dart';

class MessageRepository {
  final ApiClient _client;
  final ApiService _api;
  final CacheService _cache;

  MessageRepository(this._client, this._api, this._cache);

  // ── Okuma ────────────────────────────────────────────────────────────────

  /// Hive cache + OfflineQueue → DirectMessage listesi, senkron.
  List<DirectMessage>? getCachedThread(int otherUserId, int myUserId) {
    final raw = _cache.getWithStaleness(StorageService.cacheThreadKey(otherUserId))?.data;
    final cached = raw != null ? (raw as List).cast<Map<String, dynamic>>() : null;
    return _mergePending(cached, otherUserId, myUserId)
        ?.map(DirectMessage.fromJson)
        .toList();
  }

  /// SWR stream — son 50 mesaj + OfflineQueue, DirectMessage döner.
  Stream<List<DirectMessage>> getThread(int otherUserId, int myUserId) =>
      _api.get<List<Map<String, dynamic>>>(
        url: '${_client.config.baseUrl}/messages/$otherUserId',
        cacheKey: StorageService.cacheThreadKey(otherUserId),
        fromJson: (raw) => (raw as List).cast<Map<String, dynamic>>(),
        cacheTtl: const Duration(minutes: 30),
      ).map((maps) =>
          (_mergePending(maps, otherUserId, myUserId) ?? maps)
              .map(DirectMessage.fromJson)
              .toList());

  /// Önceki sayfa — cache'siz, DirectMessage döner.
  Future<List<DirectMessage>> getPage(int otherUserId, int beforeId) async {
    final body = await _client.callList(
      () async => http.get(
        Uri.parse(
          '${_client.config.baseUrl}/messages/$otherUserId?before_id=$beforeId&limit=50',
        ),
        headers: await _buildHeaders(),
      ),
    );
    return body
        .cast<Map<String, dynamic>>()
        .map(DirectMessage.fromJson)
        .toList();
  }

  // ── WS cache güncellemeleri ──────────────────────────────────────────────

  /// Yeni mesaj: cache'e ekle, sliding window 50 koru.
  Future<void> appendToCache(int otherUserId, Map<String, dynamic> msg) async {
    await _patchCache(otherUserId, (msgs) {
      final updated = [...msgs, msg];
      return updated.length > 50 ? updated.sublist(updated.length - 50) : updated;
    });
  }

  /// Mesaj silindi: cache'ten kaldır.
  Future<void> removeFromCache(int otherUserId, int messageId) async {
    await _patchCache(
      otherUserId,
      (msgs) => msgs..removeWhere((m) => m['id'] == messageId),
    );
  }

  /// Karşı taraf okudu: benim gönderdiğim mesajlarda is_read=true yap.
  Future<void> markReadInCache(int otherUserId, int myUserId) async {
    await _patchCache(otherUserId, (msgs) => msgs
        .map((m) =>
            (m['sender_id'] as int?) == myUserId ? {...m, 'is_read': true} : m)
        .toList());
  }

  // ── Mutasyonlar ──────────────────────────────────────────────────────────

  /// Mesaj sil — scope: 'everyone' | 'me'.
  Future<bool> deleteMessage(
    int messageId,
    int otherUserId, {
    String scope = 'everyone',
  }) async {
    try {
      await _client.call(
        () async => http.delete(
          Uri.parse(
            '${_client.config.baseUrl}/messages/$messageId?scope=$scope',
          ),
          headers: await _buildHeaders(),
        ),
      );
      await removeFromCache(otherUserId, messageId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Yardımcılar ──────────────────────────────────────────────────────────

  /// OfflineQueue bekleyen mesajları ham Map listesine ekler.
  /// Map seviyesinde çalışır — Hive serileştirme sınırı burada kalır.
  List<Map<String, dynamic>>? _mergePending(
    List<Map<String, dynamic>>? base,
    int otherUserId,
    int myUserId,
  ) {
    if (base == null) return null;
    final pending = OfflineQueueService.getPendingForReceiver(otherUserId);
    if (pending.isEmpty) return base;
    final merged = List<Map<String, dynamic>>.from(base);
    for (final p in pending) {
      final alreadyDelivered = base.any(
        (m) =>
            m['content'] == p['content'] &&
            (m['sender_id'] as int?) == myUserId,
      );
      if (!alreadyDelivered) {
        merged.add({
          'id': -(p['queued_at'] as int),
          'sender_id': myUserId,
          'receiver_id': otherUserId,
          'content': p['content'] as String,
          'is_read': false,
          'created_at': DateTime.fromMillisecondsSinceEpoch(p['queued_at'] as int)
              .toUtc()
              .toIso8601String(),
          '_pending': true,
          '_local_id': p['local_id'] as String?,
        });
      }
    }
    return merged;
  }

  /// oku → değiştir → kaydet.
  Future<void> _patchCache(
    int otherUserId,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) fn,
  ) async {
    final raw = _cache.getWithStaleness(StorageService.cacheThreadKey(otherUserId))?.data;
    if (raw == null) return;
    final current = (raw as List).cast<Map<String, dynamic>>();
    await _cache.saveData(
      StorageService.cacheThreadKey(otherUserId),
      fn(List.from(current)),
      ttl: const Duration(minutes: 30),
    );
  }

  Future<Map<String, String>> _buildHeaders() async {
    final token = await StorageService.getToken();
    return _client.buildApiHeaders(token, json: true);
  }
}

final messageRepositoryProvider = Provider<MessageRepository>((ref) =>
    MessageRepository(
      ref.watch(apiClientProvider),
      ref.watch(apiServiceProvider),
      ref.watch(cacheServiceProvider),
    ));
