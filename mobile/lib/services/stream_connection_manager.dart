import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import '../models/stream.dart';
import 'stream_service.dart';

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
class StreamConnectionManager {
  static final StreamConnectionManager instance = StreamConnectionManager._internal();
  
  StreamConnectionManager._internal();

  final Map<int, LiveSession> _sessions = {};
  
  // Her stream için bağımsız bir lock
  final Set<int> _connectionLocks = {};

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
    final toKeep = {activeStreamId, ...nextStreamIds, ...farStreamIds};
    toKeep.remove(-1); // -1 geçerli değil

    // 1. Görüş alanından çıkan yayınları temizle
    final toRemove = _sessions.keys.where((id) => !toKeep.contains(id)).toList();
    for (final id in toRemove) {
      _disconnect(id);
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
    if (session.state == targetState) return;
    
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
      session.update();
    });
  }

  void _applyTrackSubscriptions(LiveSession session) {
    if (!session.isConnected || session.room == null) return;
    
    final wantVideo = session.state == SessionState.prefetched || session.state == SessionState.active;
    final wantAudio = session.state == SessionState.active;
    
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

  void _disconnect(int id) {
    final session = _sessions.remove(id);
    if (session != null) {
      session.state = SessionState.none;
      if (session.isConnected) {
        StreamService.leaveStream(id).catchError((_) {});
      }
      session.dispose();
    }
  }

  
  void clearViewport() {
    for (final id in _sessions.keys.toList()) {
      _disconnect(id);
    }
  }

  void dispose() {
    clearViewport();
  }
}
