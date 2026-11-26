import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// ─── DM SQLite Erişim Katmanı ────────────────────────────────────────────────
//
// Tek sorumluluk: SQLite okuma/yazma. İş mantığı veya ViewModel içermez.
// thread_id = other_user_id.  Logout'ta clearAll() çağrılmalı.

class DmDatabase {
  static Database? _db;

  static const _kDbName    = 'dm_messages.db';
  static const _kDbVersion = 1;

  static const _kCreateTable = '''
    CREATE TABLE IF NOT EXISTS dm_messages (
      id              INTEGER PRIMARY KEY,
      thread_id       INTEGER NOT NULL,
      sender_id       INTEGER NOT NULL,
      receiver_id     INTEGER NOT NULL,
      content         TEXT,
      content_type    TEXT NOT NULL DEFAULT 'text',
      media_url       TEXT,
      thumbnail_url   TEXT,
      file_name       TEXT,
      file_size_bytes INTEGER,
      duration_secs   INTEGER,
      is_read         INTEGER NOT NULL DEFAULT 0,
      created_at      TEXT NOT NULL,
      is_pending      INTEGER NOT NULL DEFAULT 0,
      is_failed       INTEGER NOT NULL DEFAULT 0,
      local_id        TEXT
    )
  ''';

  static const _kCreateIndex = '''
    CREATE INDEX IF NOT EXISTS idx_dm_thread_time
      ON dm_messages(thread_id, created_at ASC)
  ''';

  /// Uygulama başlangıcında main.dart'ta çağrılır.
  static Future<void> init() async {
    final dbPath = p.join(await getDatabasesPath(), _kDbName);
    _db = await openDatabase(
      dbPath,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute(_kCreateTable);
    await db.execute(_kCreateIndex);
  }

  // ignore: unused_element
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2'de yeni kolon eklenirse: ALTER TABLE dm_messages ADD COLUMN ...
  }

  Database get _database {
    assert(_db != null, 'DmDatabase.init() henüz çağrılmadı');
    return _db!;
  }

  // ── Okuma ────────────────────────────────────────────────────────────────

  /// thread_id'ye ait tüm mesajları created_at ASC sıralamasıyla döner.
  /// SQLite int (0/1) → bool + is_pending/is_failed → _pending/_failed dönüşümü yapılır.
  Future<List<Map<String, dynamic>>> getThread(int threadId) async {
    final rows = await _database.query(
      'dm_messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  // ── Yazma ────────────────────────────────────────────────────────────────

  /// Mesaj listesini INSERT OR REPLACE ile toplu yazar (transaction).
  Future<void> upsertMessages(int threadId, List<Map<String, dynamic>> msgs) async {
    if (msgs.isEmpty) return;
    await _database.transaction((txn) async {
      final batch = txn.batch();
      for (final msg in msgs) {
        batch.insert(
          'dm_messages',
          _toRow(threadId, msg),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Tek mesaj ekler (WS yeni mesaj olayı).
  Future<void> appendMessage(int threadId, Map<String, dynamic> msg) async {
    await _database.insert(
      'dm_messages',
      _toRow(threadId, msg),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Mesajı ID ile siler (WS silme olayı veya kullanıcı silme).
  Future<void> deleteMessage(int messageId) async {
    await _database.delete(
      'dm_messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// thread_id içinde myId'nin gönderdiği mesajları okundu işaretler.
  Future<void> markReadByThread(int threadId, int myId) async {
    await _database.update(
      'dm_messages',
      {'is_read': 1},
      where: 'thread_id = ? AND sender_id = ?',
      whereArgs: [threadId, myId],
    );
  }

  /// Konuşmanın tüm mesajlarını siler (konuşma silme).
  Future<void> deleteThread(int threadId) async {
    await _database.delete(
      'dm_messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
    );
  }

  /// Logout'ta tüm mesajları temizler.
  Future<void> clearAll() async {
    await _database.delete('dm_messages');
  }

  // ── Yardımcı ─────────────────────────────────────────────────────────────

  /// SQLite satırını DirectMessage.fromJson uyumlu Map'e dönüştürür.
  /// SQLite boolean'ları int (0/1) olarak saklar; is_pending/is_failed → _pending/_failed.
  Map<String, dynamic> _fromRow(Map<String, dynamic> row) {
    final map = Map<String, dynamic>.from(row);
    map['is_read']   = (map['is_read']   as int?) == 1;
    map['_pending']  = (map.remove('is_pending') as int?) == 1;
    map['_failed']   = (map.remove('is_failed')  as int?) == 1;
    if (map['_pending'] == false) map.remove('_pending');
    if (map['_failed']  == false) map.remove('_failed');
    map.remove('thread_id');
    return map;
  }

  Map<String, dynamic> _toRow(int threadId, Map<String, dynamic> msg) {
    return {
      'id':              msg['id'],
      'thread_id':       threadId,
      'sender_id':       msg['sender_id'],
      'receiver_id':     msg['receiver_id'],
      'content':         msg['content'],
      'content_type':    msg['content_type'] ?? 'text',
      'media_url':       msg['media_url'],
      'thumbnail_url':   msg['thumbnail_url'],
      'file_name':       msg['file_name'],
      'file_size_bytes': msg['file_size_bytes'],
      'duration_secs':   msg['duration_secs'],
      'is_read':         (msg['is_read'] == true || msg['is_read'] == 1) ? 1 : 0,
      'created_at':      msg['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
      'is_pending':      (msg['_pending'] == true) ? 1 : 0,
      'is_failed':       (msg['_failed'] == true) ? 1 : 0,
      'local_id':        msg['_local_id'],
    };
  }
}

final dmDatabaseProvider = Provider<DmDatabase>((_) => DmDatabase());
