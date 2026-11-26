import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/network/api_client.dart';
import '../models/direct_message.dart';
import '../services/api_service.dart';
import '../services/dm_database.dart';
import '../services/offline_queue_service.dart';
import '../services/storage_service.dart';

class MessageRepository {
  final ApiClient _client;
  final ApiService _api;
  final DmDatabase _db;

  MessageRepository(this._client, this._api, this._db);

  // ── Okuma ────────────────────────────────────────────────────────────────

  /// SQLite'tan senkron değil — async okuma. null → thread hiç açılmamış.
  Future<List<DirectMessage>?> getCachedThread(int otherUserId, int myUserId) async {
    final rows = await _db.getThread(otherUserId);
    if (rows.isEmpty) return null;
    return _buildList(rows, otherUserId, myUserId);
  }

  /// async* stream: DB'den anında emit, ardından ağdan upsert + emit.
  Stream<List<DirectMessage>> getThread(int otherUserId, int myUserId) async* {
    final dbRows = await _db.getThread(otherUserId);
    yield _buildList(dbRows, otherUserId, myUserId);

    try {
      await for (final maps in _api.get<List<Map<String, dynamic>>>(
        url: '${_client.config.baseUrl}/messages/$otherUserId',
        cacheKey: null,
        fromJson: (raw) => (raw as List).cast<Map<String, dynamic>>(),
      )) {
        await _db.upsertMessages(otherUserId, maps);
        yield _buildList(maps, otherUserId, myUserId);
      }
    } catch (_) {
      if (dbRows.isEmpty) rethrow;
      // DB zaten emit edildi — ağ hatası sessizce geçer
    }
  }

  /// Önceki sayfa — SQLite'a da yazar (offline scroll için).
  Future<List<DirectMessage>> getPage(int otherUserId, int beforeId) async {
    final body = await _client.callList(
      () async => http.get(
        Uri.parse(
          '${_client.config.baseUrl}/messages/$otherUserId?before_id=$beforeId&limit=50',
        ),
        headers: await _buildHeaders(),
      ),
    );
    final maps = body.cast<Map<String, dynamic>>();
    await _db.upsertMessages(otherUserId, maps);
    return maps.map(DirectMessage.fromJson).toList();
  }

  // ── WS cache güncellemeleri ──────────────────────────────────────────────

  /// Yeni mesaj: SQLite'a ekle.
  Future<void> appendToCache(int otherUserId, Map<String, dynamic> msg) =>
      _db.appendMessage(otherUserId, msg);

  /// Mesaj silindi: SQLite'tan kaldır.
  Future<void> removeFromCache(int otherUserId, int messageId) =>
      _db.deleteMessage(messageId);

  /// Karşı taraf okudu: benim gönderdiğim mesajlarda is_read=true yap.
  Future<void> markReadInCache(int otherUserId, int myUserId) =>
      _db.markReadByThread(otherUserId, myUserId);

  // ── Mutasyonlar ──────────────────────────────────────────────────────────

  /// Mesajları okundu işaretle — istemci mesajları ekranda gösterdiğinde çağrılır.
  Future<void> markMessagesRead(int otherUserId) async {
    try {
      await _client.call(
        () async => http.post(
          Uri.parse('${_client.config.baseUrl}/messages/$otherUserId/read'),
          headers: await _buildHeaders(),
        ),
      );
    } catch (_) {}
  }

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
      await _db.deleteMessage(messageId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Ön Isıtma ────────────────────────────────────────────────────────────

  /// SQLite boşsa thread'i arka planda sessizce fetch edip ısıtır.
  Future<void> preWarmThread(int otherUserId, int myUserId) async {
    final existing = await _db.getThread(otherUserId);
    if (existing.isNotEmpty) return;
    try {
      await getThread(otherUserId, myUserId).drain<void>();
    } catch (_) {}
  }

  // ── Yardımcılar ──────────────────────────────────────────────────────────

  List<DirectMessage> _buildList(
    List<Map<String, dynamic>> rows,
    int otherUserId,
    int myUserId,
  ) {
    final merged = _mergePending(rows, otherUserId, myUserId) ?? rows;
    return merged.map(DirectMessage.fromJson).toList();
  }

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

  Future<Map<String, String>> _buildHeaders() async {
    final token = await StorageService.getToken();
    return _client.buildApiHeaders(token, json: true);
  }
}

final messageRepositoryProvider = Provider<MessageRepository>((ref) =>
    MessageRepository(
      ref.watch(apiClientProvider),
      ref.watch(apiServiceProvider),
      ref.watch(dmDatabaseProvider),
    ));
