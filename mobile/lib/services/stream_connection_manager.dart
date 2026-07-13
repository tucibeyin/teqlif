import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../models/stream.dart';
import 'stream_service.dart';
import 'background_audio_handler.dart';

enum SessionState {
  none,
  connected,    // Sadece handshake (video/audio yok)
  prefetched,   // Video var, Audio yok (±1)
  active        // Video ve Audio var (0)
}

class LiveSession extends ChangeNotifier {
  final int streamId;
  Room? room;
  JoinTokenOut? token;
  EventsListener<RoomEvent>? listener;
  
  VideoTrack? hostVideoTrack;
  VideoTrack? coHostVideoTrack;
  String? hostParticipantSid;
  
  LocalVideoTrack? localVideoTrack;
  
  SessionState state = SessionState.none;
  bool isConnecting = false;
  bool isConnected = false;
  bool streamEnded = false;
  bool isDisposed = false;
  
  LiveSession(this.streamId);
  
  void update() {
    if (!isDisposed) {
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    isDisposed = true;
    listener?.dispose();
    room?.disconnect();
    super.dispose();
  }
}

/// TikTok tarzı dikey kaydırmada ±2 mesafesindeki canlı yayınların
/// WebRTC bağlantılarını akıllıca yöneten merkezi servis.
class StreamConnectionManager with WidgetsBindingObserver {
  static final StreamConnectionManager instance = StreamConnectionManager._internal();
  
  StreamConnectionManager._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  final Map<int, LiveSession> _sessions = {};
  
  // Her stream için bağımsız bir lock
  final Set<int> _connectionLocks = {};
  
  bool _isCallActive = false;
  
  void setCallActive(bool active) {
    if (_isCallActive == active) return;
    _isCallActive = active;
    debugPrint('[LIVE_SCREEN_CALL] StreamConnectionManager setCallActive: $_isCallActive');
    for (final session in _sessions.values) {
      _applyTrackSubscriptions(session);
    }
  }

  int _currentActiveStreamId = -1;
  bool _isBackground = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      if (!_isBackground) {
        _isBackground = true;
        _handleBackgroundTransition();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isBackground) {
        _isBackground = false;
        _handleForegroundTransition();
      }
    }
  }

  void _handleBackgroundTransition() {
    if (_currentActiveStreamId != -1) {
      final session = _sessions[_currentActiveStreamId];
      if (session != null && session.isConnected) {
        bgAudioHandler.startService(
          session.streamId, 
          session.token?.title ?? 'Canlı Yayın', 
          session.token?.hostUsername ?? 'Yayıncı'
        );
        _applyTrackSubscriptions(session);
      }
    }
  }

  void _handleForegroundTransition() {
    bgAudioHandler.stopService();
    if (_currentActiveStreamId != -1) {
      final session = _sessions[_currentActiveStreamId];
      if (session != null && session.isConnected) {
        _applyTrackSubscriptions(session);
      }
    }
  }

  LiveSession getSession(int streamId) {
    return _sessions.putIfAbsent(streamId, () => LiveSession(streamId));
  }

  /// Ekran açılmadan hemen önce erken bağlantı başlatır
  void prefetchForImmediateJoin(int streamId) {
    updateViewport(activeStreamId: streamId, nextStreamIds: {}, farStreamIds: {});
  }

  /// PageView kaydırıldıkça (veya feed yenilendikçe) çağrılır.
  /// activeStreamId: Ekranda olan yayın (-1 ise hiçbir yayın ekranda değil)
  /// nextStreamIds: Yukarı ve aşağı yönde ±1 mesafedeki yayınlar
  /// farStreamIds: Yukarı ve aşağı yönde ±2 mesafedeki yayınlar
  Future<void> updateViewport({
    required int activeStreamId,
    required Set<int> nextStreamIds,
    required Set<int> farStreamIds,
  }) async {
    _currentActiveStreamId = activeStreamId;

    final toKeep = {activeStreamId, ...nextStreamIds, ...farStreamIds};
    toKeep.remove(-1); // -1 geçerli değil

    // 1. Görüş alanından çıkan yayınları temizle (Dispose etme, sadece bağlantıyı kopar)
    final toRemove = _sessions.keys.where((id) => !toKeep.contains(id)).toList();
    for (final id in toRemove) {
      _deactivateSession(id);
    }

    // 2. ±2 (Uzak) yayınlar -> Sadece handshake (bağlan ama track indirme)
    for (final id in farStreamIds) {
      if (id == activeStreamId || nextStreamIds.contains(id) || id == -1) continue;
      _setSessionState(id, SessionState.connected);
    }

    // 3. ±1 (Yakın) yayınlar -> Prefetch (Video indir, Audio kapalı)
    for (final id in nextStreamIds) {
      if (id == activeStreamId || id == -1) continue;
      _setSessionState(id, SessionState.prefetched);
    }

    // 4. Ekranda olan (Aktif) yayın -> Active (Video ve Audio indir)
    if (activeStreamId != -1) {
      _setSessionState(activeStreamId, SessionState.active);
    }
  }

  Future<void> _setSessionState(int id, SessionState targetState) async {
    final session = getSession(id);
    if (session.state == targetState) {
      // Eğer durum aynı ama bağlantı kopuksa ve state > none ise tekrar bağlanmayı dene
      if (targetState != SessionState.none && !session.isConnected && !_connectionLocks.contains(id)) {
        _connectRoom(session);
      }
      return;
    }
    
    session.state = targetState;

    if (!session.isConnected && !_connectionLocks.contains(id)) {
      // Arka planda bağlanmaya başla
      _connectRoom(session);
    } else if (session.isConnected) {
      // Zaten bağlıysa abonelikleri güncelle
      _applyTrackSubscriptions(session);
    }
  }

  Future<void> _connectRoom(LiveSession session) async {
    if (_connectionLocks.contains(session.streamId)) return;
    _connectionLocks.add(session.streamId);
    session.isConnecting = true;
    session.update();

    try {
      final token = await StreamService.joinStream(session.streamId);
      final room = Room();
      session.listener = room.createListener();
      
      _setupListeners(session);
      
      // autoSubscribe: false ile sadece handshake yapıyoruz
      await room.connect(
        token.livekitUrl,
        token.token,
        connectOptions: const ConnectOptions(autoSubscribe: false),
      );
      
      session.room = room;
      session.token = token;
      session.isConnected = true;
      session.isConnecting = false;
      
      // Bağlandıktan sonra mevcut state'e göre track'leri yönet
      _applyTrackSubscriptions(session);
      session.update();
      
    } catch (e) {
      session.isConnecting = false;
      session.update();
      debugPrint('[StreamConnectionManager] Connect failed for ${session.streamId}: $e');
    } finally {
      _connectionLocks.remove(session.streamId);
    }
  }

  void _setupListeners(LiveSession session) {
    session.listener!.on<TrackPublishedEvent>((e) {
       _applyTrackSubscriptions(session);
    });
    session.listener!.on<TrackSubscribedEvent>((e) {
      if (e.track is VideoTrack) {
        final isHost = e.participant.identity == session.token?.hostLivekitIdentity;
        if (isHost) {
          session.hostVideoTrack = e.track as VideoTrack;
          session.hostParticipantSid = e.participant.sid;
        } else {
          session.coHostVideoTrack = e.track as VideoTrack;
        }
        session.update();
      }
    });
    session.listener!.on<TrackUnsubscribedEvent>((e) {
      if (e.track == session.hostVideoTrack) session.hostVideoTrack = null;
      if (e.track == session.coHostVideoTrack) session.coHostVideoTrack = null;
      session.update();
    });
    session.listener!.on<RoomDisconnectedEvent>((e) {
      if (e.reason == DisconnectReason.roomDeleted) {
        session.streamEnded = true;
      }
      session.hostVideoTrack = null;
      session.isConnected = false;
      session.state = SessionState.none;
      session.update();
    });
  }

  void _applyTrackSubscriptions(LiveSession session) {
    if (!session.isConnected || session.room == null) return;
    
    // Arka planda (Background) video indirme (Veri tasarrufu)
    final wantVideo = (!_isBackground) && (session.state == SessionState.prefetched || session.state == SessionState.active);
    final wantAudio = session.state == SessionState.active && !_isCallActive;
    
    debugPrint('[LIVE_SCREEN_CALL] _applyTrackSubscriptions for stream: ${session.streamId} | wantVideo: $wantVideo | wantAudio: $wantAudio | isCallActive: $_isCallActive');
    
    for (final p in session.room!.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        if (wantVideo && !pub.subscribed) pub.subscribe();
        if (!wantVideo && pub.subscribed) pub.unsubscribe();
      }
      for (final pub in p.audioTrackPublications) {
        if (wantAudio && !pub.subscribed) pub.subscribe();
        if (!wantAudio && pub.subscribed) pub.unsubscribe();
      }
    }
  }

  void _deactivateSession(int id) {
    final session = _sessions[id];
    if (session != null) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: PIP_DEBUG] Deactivating stream: $id');
      
      // state kontrolü (session.state != SessionState.none) YAPMIYORUZ!
      // Çünkü LiveKit RoomDisconnectedEvent zaten none yapmış olabilir,
      // yine de room'u null yapıp UI'ın Loading veya Overlay'a düşmesini sağlamalıyız.
      session.state = SessionState.none;
      if (session.isConnected) {
        StreamService.leaveStream(id).catchError((_) {});
      }
      session.isConnected = false;
      session.isConnecting = false;
      session.listener?.dispose();
      session.listener = null;
      session.room?.disconnect();
      session.room = null;
      session.hostVideoTrack = null;
      session.coHostVideoTrack = null;
      session.hostParticipantSid = null;
      session.update();
    }
  }

  void _disconnect(int id) {
    final session = _sessions.remove(id);
    if (session != null) {
      debugPrint('[${DateTime.now().toString()}] [EVENT: PIP_DEBUG] Disconnecting stream: $id');
      session.state = SessionState.none;
      if (session.isConnected) {
        StreamService.leaveStream(id).catchError((_) {});
      }
      session.dispose();
    }
  }

  Future<void> upgradeToCoHost(int streamId, StreamTokenOut newToken) async {
    final session = getSession(streamId);
    if (session.room == null) return;
    
    // Bağlantı çakışmalarını önlemek için lock koyalım
    if (_connectionLocks.contains(streamId)) return;
    _connectionLocks.add(streamId);
    
    try {
      // Best Practice: Backend yetkiyi güncellediği için disconnect/connect yapmamıza gerek yok!
      // LiveKit SDK arkada yetki güncellemesini alacak, biz direkt kamerayı açabiliriz.
      await session.room!.localParticipant?.setCameraEnabled(true);
      await session.room!.localParticipant?.setMicrophoneEnabled(true);

      final pub = session.room!.localParticipant?.videoTrackPublications.firstOrNull;
      if (pub?.track is LocalVideoTrack) {
        session.localVideoTrack = pub!.track as LocalVideoTrack;
      }
      session.update();
    } catch (e) {
      debugPrint('[StreamConnectionManager] upgradeToCoHost failed: $e');
    } finally {
      _connectionLocks.remove(streamId);
    }
  }

  Future<void> downgradeFromCoHost(int streamId) async {
    final session = getSession(streamId);
    if (session.room == null) return;
    try {
      await session.room!.localParticipant?.setCameraEnabled(false);
      await session.room!.localParticipant?.setMicrophoneEnabled(false);
      session.localVideoTrack = null;
      session.update();
    } catch (e) {
      debugPrint('[StreamConnectionManager] downgradeFromCoHost failed: $e');
    }
  }


  
  void clearViewport({int? excludeStreamId}) {
    debugPrint('[${DateTime.now().toString()}] [EVENT: PIP_DEBUG] clearViewport called. excludeStreamId: $excludeStreamId');
    for (final id in _sessions.keys.toList()) {
      if (id == excludeStreamId) {
        debugPrint('[${DateTime.now().toString()}] [EVENT: PIP_DEBUG] clearViewport skipping excluded stream: $id');
        continue;
      }
      _disconnect(id);
    }
    _currentActiveStreamId = excludeStreamId ?? -1;
    if (_currentActiveStreamId == -1 && _isBackground) {
      bgAudioHandler.stopService();
    }
  }

  void dispose() {
    clearViewport();
  }
}
