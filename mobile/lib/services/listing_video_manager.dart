import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../config/api.dart';
import 'video_cache_manager.dart';

class ListingVideoManager {
  static final ListingVideoManager instance = ListingVideoManager._internal();
  ListingVideoManager._internal();

  final Map<int, VideoPlayerController> _controllers = {};
  int _activeId = -1;

  /// Belirtilen [urls] (id -> video_url) listesi için controller'ları önbelleğe alır.
  void updateViewport({
    required int activeId,
    required Set<int> nextIds,
    required Set<int> cacheIds,
    required Map<int, String> urls,
  }) {
    _activeId = activeId;
    
    debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_VIDEO_VIEWPORT] activeId: $activeId | nextIds: $nextIds | cacheIds: $cacheIds');

    // 1. VideoCacheManager'a önbelleğe alınacakları bildir
    VideoCacheManager.instance.updateCache(cacheIds, urls);

    // 2. Controller'ı RAM'de tutulacak olanlar (active + nextIds)
    final keepIds = {activeId, ...nextIds};

    // 3. Artık viewport'ta olmayanları temizle ama CacheManager diskte tutabilir
    final toRemove = _controllers.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in toRemove) {
      final ctrl = _controllers.remove(id);
      ctrl?.dispose();
    }

    // 4. Viewport'ta olup henüz controller'ı olmayanları oluştur
    for (final id in keepIds) {
      if (id <= 0) continue;
      final url = urls[id];
      if (url == null || url.isEmpty) continue;

      if (!_controllers.containsKey(id)) {
        _initController(id, url);
      }
    }
  }

  Future<void> _initController(int id, String rawUrl) async {
    debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_VIDEO_INIT] started for id: $id');
    final cachedPath = VideoCacheManager.instance.getCachedPath(id);
    VideoPlayerController ctrl;
    
    if (cachedPath != null && File(cachedPath).existsSync()) {
      ctrl = VideoPlayerController.file(File(cachedPath));
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_VIDEO_LOAD] CACHE üzerinden başlatılıyor: $id');
    } else {
      // Ağ bant genişliğini (bandwidth) korumak için, eğer arka planda hala iniyorsa onu iptal et.
      // Çünkü zaten AVPlayer kendi ağ tamponlamasını başlatacak ve ikisi aynı anda ağı sömürür!
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_VIDEO_LOAD] CACHE BULUNAMADI, NETWORK üzerinden başlatılacak: $id (canceling bg download if any)');
      VideoCacheManager.instance.cancelDownload(id);
      
      final fullUrl = imgUrl(rawUrl);
      ctrl = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_VIDEO_LOAD] NETWORK başlatıldı: $id');
    }
    
    _controllers[id] = ctrl;
    
    try {
      await ctrl.initialize();
      ctrl.setLooping(true);
      
      // Eğer bu video şuan izleniyorsa (hızlı swipe edildiyse), buffering hack'ini atla!
      if (_activeId == id) {
        return; // Aktif video, müdahale etme, _ListingVideoPage oynatacak.
      }
      
      // MP4 moov atom gecikmesini yenmek için arkaplanda sessizce oynatıp hemen durduruyoruz
      // Böylece AVPlayer ağ üzerinden tamponlamaya (buffering) zorlanıyor
      await ctrl.setVolume(0.0);
      await ctrl.play();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_controllers.containsKey(id) && _activeId != id) {
          ctrl.pause();
        }
      });
    } catch (e) {
      debugPrint('[ListingVideoManager] Video başlatılamadı ($id): $e');
    }
  }

  VideoPlayerController? getController(int id) {
    return _controllers[id];
  }

  VideoPlayerController getOrCreateController(int id, String rawUrl) {
    debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_VIDEO_GET] requested for id: $id');
    if (!_controllers.containsKey(id)) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_VIDEO_GET] Controller NOT found in RAM, initializing now: $id');
      _initController(id, rawUrl);
    } else {
      debugPrint('[${DateTime.now().toString()}] [EVENT: LISTING_VIDEO_GET] Controller FOUND in RAM: $id');
    }
    return _controllers[id]!;
  }

  void disposeAll() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    _controllers.clear();
  }
}
