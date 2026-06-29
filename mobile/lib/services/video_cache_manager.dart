import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/api.dart';

class VideoCacheManager {
  static final VideoCacheManager instance = VideoCacheManager._internal();
  VideoCacheManager._internal();

  Directory? _tempDir;
  final Map<int, String> _cachedFiles = {};
  final Set<int> _downloading = {};
  final Map<int, String> _urls = {};
  final Map<int, http.Client> _activeClients = {};
  
  // Download Queue (Concurrent max: 2)
  final List<int> _queue = [];
  int _activeDownloads = 0;
  final int _maxConcurrent = 2;

  // Controller notification callback
  final Map<int, List<VoidCallback>> _listeners = {};

  void addListener(int id, VoidCallback callback) {
    _listeners.putIfAbsent(id, () => []).add(callback);
    if (_cachedFiles.containsKey(id)) {
      callback(); // Zaten inmişse hemen çağır
    }
  }

  void removeListener(int id, VoidCallback callback) {
    _listeners[id]?.remove(callback);
  }

  Future<void> init() async {
    if (_tempDir == null) {
      _tempDir = await getTemporaryDirectory();
    }
  }

  String? getCachedPath(int id) {
    return _cachedFiles[id];
  }

  void updateCache(Set<int> cacheIds, Map<int, String> urls) {
    // 1. Fazlalıkları sil
    final toDelete = _cachedFiles.keys.where((id) => !cacheIds.contains(id)).toList();
    for (final id in toDelete) {
      final path = _cachedFiles.remove(id);
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) {
          file.delete().catchError((e) => debugPrint('[VideoCacheManager] Silme hatası: $e'));
        }
      }
    }
    
    // Ayrıca sıradan da çıkar
    _queue.removeWhere((id) => !cacheIds.contains(id));
    
    // Aktif inenlerden viewport dışına çıkanları iptal et (bant genişliğini rahatlat)
    final toCancel = _activeClients.keys.where((id) => !cacheIds.contains(id)).toList();
    for (final id in toCancel) {
      cancelDownload(id);
    }

    // 2. Eksikleri kuyruğa ekle
    for (final id in cacheIds) {
      if (id <= 0) continue;
      if (_cachedFiles.containsKey(id) || _downloading.contains(id) || _queue.contains(id)) {
        continue;
      }
      final rawUrl = urls[id];
      if (rawUrl != null && rawUrl.isNotEmpty) {
        _queue.add(id);
        _urls[id] = imgUrl(rawUrl);
      }
    }
    
    _processQueue();
  }

  Future<void> _processQueue() async {
    while (_activeDownloads < _maxConcurrent && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      final url = _urls.remove(id);
      if (url == null) continue;
      
      _activeDownloads++;
      _downloading.add(id);
      
      _downloadVideo(id, url).whenComplete(() {
        _activeDownloads--;
        _downloading.remove(id);
        _processQueue();
      });
    }
  }

  void cancelDownload(int id) {
    if (_activeClients.containsKey(id)) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: CACHE_DOWNLOAD_CANCELLED] Bandwidth saving triggered for id: $id');
      _activeClients[id]?.close();
      _activeClients.remove(id);
      _downloading.remove(id);
    }
  }

  Future<void> _downloadVideo(int id, String url) async {
    try {
      await init();
      final dir = _tempDir!;
      final filename = 'teqlif_video_$id.mp4';
      final file = File('${dir.path}/$filename');
      
      if (file.existsSync()) {
        if (file.lengthSync() > 0) {
          _markAsDone(id, file.path);
          return;
        } else {
          file.deleteSync();
        }
      }

      debugPrint('[${DateTime.now().toString()}] [EVENT: CACHE_DOWNLOAD_STARTED] url: $filename');
      final client = http.Client();
      _activeClients[id] = client;
      
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      
      if (response.statusCode == 200) {
        final tmpFile = File('${dir.path}/$filename.tmp');
        final sink = tmpFile.openWrite();
        await response.stream.pipe(sink);
        await sink.close();
        
        // Eğer indirirken iptal edildiyse rename etme
        if (!_activeClients.containsKey(id)) {
          if (tmpFile.existsSync()) tmpFile.deleteSync();
          return;
        }
        
        await tmpFile.rename(file.path);
        
        debugPrint('[${DateTime.now().toString()}] [EVENT: CACHE_DOWNLOAD_SUCCESS] finished: $filename');
        _markAsDone(id, file.path);
      } else {
        debugPrint('[${DateTime.now().toString()}] [EVENT: CACHE_DOWNLOAD_FAILED] HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: CACHE_DOWNLOAD_ERROR_OR_CANCELLED] id: $id | err: $e');
    } finally {
      _activeClients.remove(id);
    }
  }

  void _markAsDone(int id, String path) {
    _cachedFiles[id] = path;
    final callbacks = _listeners[id]?.toList();
    if (callbacks != null) {
      for (final cb in callbacks) {
        cb();
      }
    }
  }
}
