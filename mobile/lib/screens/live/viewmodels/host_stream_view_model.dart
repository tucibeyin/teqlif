import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/app_exception.dart';
import '../../../core/logger_service.dart';
import '../../../models/stream.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auction_service.dart';
import '../../../services/client_logger.dart';
import '../../../services/localization_service.dart';
import '../../../services/moderation_service.dart';
import '../../../services/stream_service.dart';
import '../../../ui_library/components/overlays/teq_toast.dart';

const int _kMaxInitialConnectAttempts = 3;
const int _kMaxReconnectAttempts = 7;
const int _kTrackPollIntervalMs = 100;
const int _kTrackPollMaxAttempts = 50;

RoomOptions _roomOptionsForProfile(String profile) {
  // PRO:      main=720p (1700k) + simulcast 540p(800k)/360p(450k)           — PiP=360p
  // standard: main=540p  (800k) + simulcast 360p(450k)/240p(140k)          — PiP=240p
  final isPro = profile == 'pro';
  return RoomOptions(
    adaptiveStream: true,
    dynacast: true,
    defaultVideoPublishOptions: VideoPublishOptions(
      simulcast: true,
      backupVideoCodec: const BackupVideoCodec(codec: 'vp9'),
      videoSimulcastLayers: isPro
          ? const [VideoParametersPresets.h360_169, VideoParametersPresets.h540_169]
          : const [VideoParametersPresets.h240_43, VideoParametersPresets.h360_169],
      videoEncoding: VideoEncoding(
        maxBitrate: isPro ? 1700000 : 800000,
        maxFramerate: 30,
      ),
      // flutter_webrtc Android toUpperCase() Türkçe locale bug: i→İ. balanced güvenli.
      degradationPreference: DegradationPreference.balanced,
    ),
    defaultAudioPublishOptions: const AudioPublishOptions(audioBitrate: 64000),
  );
}

CameraCaptureOptions _cameraOptionsForProfile(String profile) {
  return CameraCaptureOptions(
    params: profile == 'pro'
        ? VideoParametersPresets.h720_169
        : VideoParametersPresets.h540_169,
  );
}

/// Bağlantı fail olduğunda retry edilmemesi gereken dahili istisna.
class _ConfirmLiveFailure implements Exception {
  final Object cause;
  _ConfirmLiveFailure(this.cause);
}

class HostStreamViewModel extends ChangeNotifier {
  final AnalyticsService _analytics;
  final AuctionService _auction;
  final ModerationService _moderation;
  final StreamService _stream;
  static final _log = LoggerService.instance;

  // ── Bağlantı state'i (View tarafından izlenir) ────────────────────────────────
  Room? room;
  LocalVideoTrack? localVideoTrack;
  VideoTrack? coHostTrack;
  String? error;
  bool micEnabled = true;
  bool cameraEnabled = true;
  bool isFrontCamera = true;
  ConnectionQuality? connectionQuality;

  // ── Dahili bağlantı state'i ────────────────────────────────────────────────────
  EventsListener<RoomEvent>? _listener;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  StreamTokenOut? _token;
  String _streamTitle = '';
  bool _disposed = false;

  // ── Navigasyon callback'leri (View tarafından initState'de set edilir) ─────────
  void Function(int streamId, String title)? onNavigateToReport;
  VoidCallback? onNavigateHome;

  // ── Pin (granüler UI güncellemesi için ValueNotifier) ─────────────────────────
  final ValueNotifier<bool> hasPinned = ValueNotifier(false);

  HostStreamViewModel(this._analytics, this._auction, this._moderation, this._stream);

  bool get isLive => room != null && error == null;

  void setPinned(bool value) => hasPinned.value = value;

  // ── İlk bağlantı — ICE hatalarına karşı 3 deneme ─────────────────────────────
  Future<void> connect(
    StreamTokenOut token, {
    required String title,
    required String category,
    required TranslationPack loc,
    bool blastApproved = false,
    double blastCost = 0,
    required void Function() onConnected,
  }) async {
    _token = token;
    _streamTitle = title;

    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (!camStatus.isGranted || !micStatus.isGranted) {
      final permanent = camStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied;
      _stream.cancelStream(token.streamId).ignore();
      error = permanent
          ? loc.tOr('permPermanentlyDenied', 'Bu özellik için izin gerekli. Ayarlardan etkinleştir.')
          : loc.t('livePermissionRequired');
      _notify();
      return;
    }

    for (var attempt = 0; attempt < _kMaxInitialConnectAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: attempt));
        if (_disposed) return;
      }
      try {
        await _attemptConnect(token, title, category, blastApproved, blastCost, loc);
        if (_disposed) return;
        onConnected();
        return;
      } on _ConfirmLiveFailure catch (e) {
        // confirmLive başarısız — retry etme, direkt iptal
        ClientLogger.report(
          tag: 'HostConnect.confirmLive',
          message: 'confirmLive başarısız',
          error: e.cause,
          stackTrace: StackTrace.current,
          details: {'stream_id': token.streamId},
        );
        _stream.cancelStream(token.streamId).ignore();
        error = loc.tOr('streamConfirmFailed', 'Yayın başlatılamadı');
        _notify();
        return;
      } catch (e, st) {
        ClientLogger.report(
          tag: 'HostConnect.attempt${attempt + 1}',
          message: 'LiveKit bağlantısı kurulamadı',
          error: e,
          stackTrace: st,
          details: {'livekit_url': token.livekitUrl, 'stream_id': token.streamId},
        );
      }
    }

    if (_disposed) return;
    _stream.cancelStream(token.streamId).ignore();
    error = loc.tOr('streamConnectFailed', 'Yayına bağlanılamadı. Lütfen tekrar deneyin.');
    _notify();
  }

  Future<void> _attemptConnect(
    StreamTokenOut token,
    String title,
    String category,
    bool blastApproved,
    double blastCost,
    TranslationPack loc,
  ) async {
    final newRoom = Room(
      roomOptions: _roomOptionsForProfile(token.videoQualityProfile),
    );
    _setupRoomListeners(newRoom, token.streamId);

    try {
      await newRoom.connect(token.livekitUrl, token.token);
    } catch (e) {
      _listener?.dispose();
      _listener = null;
      try { await newRoom.disconnect(); } catch (_) {}
      rethrow;
    }

    // Kamera / mikrofon — non-fatal, hata olursa toast göster
    try {
      await newRoom.localParticipant?.setCameraEnabled(
        true,
        cameraCaptureOptions: _cameraOptionsForProfile(token.videoQualityProfile),
      );
      await newRoom.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: const AudioCaptureOptions(
          noiseSuppression: true,
          echoCancellation: true,
          autoGainControl: true,
        ),
      );
    } catch (e) {
      if (e is! TrackCreateException) {
        _log.captureException(e, tag: 'HostConnect.trackEnable');
      }
      TeqToast.warning(loc.tOr('cameraToggleFailed', 'Kamera başlatılamadı, yayın devam ediyor'));
    }

    LocalVideoTrack? foundTrack;
    for (final pub in newRoom.localParticipant!.videoTrackPublications) {
      if (pub.track != null) {
        foundTrack = pub.track as LocalVideoTrack;
        break;
      }
    }

    try {
      await _stream.confirmLive(token.streamId);
    } catch (e) {
      _listener?.dispose();
      _listener = null;
      try { await newRoom.disconnect(); } catch (_) {}
      throw _ConfirmLiveFailure(e);
    }

    if (blastApproved) {
      _analytics.sendLeadBlast(
        title: title,
        category: category,
        estimatedCost: blastCost.toInt(),
        streamId: token.streamId,
      ).ignore();
    }

    room = newRoom;
    localVideoTrack = foundTrack;
    _notify();
    if (foundTrack == null) _schedulePollForTrack(0);
  }

  void _schedulePollForTrack(int attempt) {
    if (attempt >= _kTrackPollMaxAttempts || room == null || _disposed) return;
    Future<void>.delayed(const Duration(milliseconds: _kTrackPollIntervalMs)).then((_) {
      if (_disposed || room == null || localVideoTrack != null) return;
      for (final pub in room!.localParticipant?.videoTrackPublications ?? []) {
        if (pub.track != null) {
          localVideoTrack = pub.track as LocalVideoTrack;
          _notify();
          return;
        }
      }
      _schedulePollForTrack(attempt + 1);
    });
  }

  void _setupRoomListeners(Room r, int streamId) {
    _listener?.dispose();
    _listener = r.createListener();

    _listener!.on<TrackSubscribedEvent>((e) {
      if (e.track is VideoTrack) {
        coHostTrack = e.track as VideoTrack;
        _notify();
      }
    });
    _listener!.on<TrackUnsubscribedEvent>((e) {
      if (e.track is VideoTrack && e.track == coHostTrack) {
        coHostTrack = null;
        _notify();
      }
    });
    _listener!.on<ParticipantConnectionQualityUpdatedEvent>((e) {
      if (e.participant is LocalParticipant) {
        connectionQuality = e.connectionQuality;
        _notify();
      }
    });
    _listener!.on<RoomDisconnectedEvent>((e) {
      final reason = e.reason;
      if (reason == DisconnectReason.clientInitiated) return;
      if (reason == DisconnectReason.roomDeleted) {
        _handleRoomTerminated(streamId);
        return;
      }
      scheduleReconnect();
    });
  }

  Future<void> _handleRoomTerminated(int streamId) async {
    _listener?.dispose();
    _listener = null;
    try { await _stream.endStream(streamId); } catch (_) {}
    try {
      await room?.localParticipant?.setCameraEnabled(false);
      await room?.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    await room?.disconnect();
    room = null;
    localVideoTrack = null;
    _notify();
    onNavigateToReport?.call(streamId, _streamTitle);
  }

  // ── Reconnect ──────────────────────────────────────────────────────────────────
  void scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectAttempts >= _kMaxReconnectAttempts) {
      onNavigateHome?.call();
      return;
    }
    // Üstel backoff, 30s'de tavan: 2,4,8,16,30,30,30 → toplam ~120s
    final raw = 2 << _reconnectAttempts;
    final delay = Duration(seconds: raw.clamp(2, 30));
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _reconnect);
  }

  Future<void> _reconnect() async {
    if (_disposed || room == null || _token == null) return;
    try {
      final freshToken = await _stream.refreshStreamToken(_token!.streamId);
      await room!.connect(freshToken.livekitUrl, freshToken.token);
      _reconnectAttempts = 0;
    } on AppException catch (e) {
      if (e.code == 'STREAM_ENDED') {
        onNavigateHome?.call();
        return;
      }
      if (e.code == 'NODE_UNAVAILABLE') {
        await _doFailover();
        return;
      }
      scheduleReconnect();
    } catch (_) {
      scheduleReconnect();
    }
  }

  /// Kural 3: Kaynak node çöktüğünde yeni node'a failover.
  /// Yeni room_name + livekit_url alınır; kamera/mikrofon yeniden etkinleştirilir.
  Future<void> _doFailover() async {
    if (_disposed || _token == null) return;
    try {
      final newToken = await _stream.failoverStream(_token!.streamId);
      _token = newToken;

      _listener?.dispose();
      _listener = null;
      final oldRoom = room;
      room = null;
      localVideoTrack = null;
      coHostTrack = null;
      _notify();
      try { await oldRoom?.disconnect(); } catch (_) {}

      final newRoom = Room(
        roomOptions: _roomOptionsForProfile(newToken.videoQualityProfile),
      );
      _setupRoomListeners(newRoom, newToken.streamId);
      await newRoom.connect(newToken.livekitUrl, newToken.token);
      room = newRoom;

      await newRoom.localParticipant?.setCameraEnabled(
        true,
        cameraCaptureOptions: _cameraOptionsForProfile(newToken.videoQualityProfile),
      );
      await newRoom.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: const AudioCaptureOptions(
          noiseSuppression: true,
          echoCancellation: true,
          autoGainControl: true,
        ),
      );

      LocalVideoTrack? foundTrack;
      for (final pub in newRoom.localParticipant?.videoTrackPublications ?? []) {
        if (pub.track != null) { foundTrack = pub.track as LocalVideoTrack; break; }
      }
      localVideoTrack = foundTrack;
      _reconnectAttempts = 0;
      _notify();
    } on AppException catch (e) {
      if (e.code == 'STREAM_ENDED') {
        onNavigateHome?.call();
        return;
      }
      scheduleReconnect();
    } catch (_) {
      scheduleReconnect();
    }
  }

  // ── Kamera / mikrofon kontrolleri ─────────────────────────────────────────────
  Future<void> toggleMic(TranslationPack loc) async {
    final target = !micEnabled;
    try {
      await room?.localParticipant?.setMicrophoneEnabled(target);
      micEnabled = target;
      _notify();
    } catch (e) {
      _log.captureException(e, tag: 'HostStream.toggleMic');
      TeqToast.error(loc.tOr('micToggleFailed', 'Mikrofon değiştirilemedi'));
    }
  }

  Future<void> toggleCamera(TranslationPack loc) async {
    final target = !cameraEnabled;
    try {
      await room?.localParticipant?.setCameraEnabled(
        target,
        cameraCaptureOptions: target
            ? _cameraOptionsForProfile(_token?.videoQualityProfile ?? 'standard')
            : null,
      );
      if (target) {
        LocalVideoTrack? fresh;
        for (final pub in room?.localParticipant?.videoTrackPublications ?? []) {
          if (pub.track != null) { fresh = pub.track as LocalVideoTrack; break; }
        }
        cameraEnabled = true;
        localVideoTrack = fresh;
      } else {
        cameraEnabled = false;
        localVideoTrack = null;
      }
      _notify();
    } catch (e) {
      _log.captureException(e, tag: 'HostStream.toggleCamera');
      TeqToast.error(loc.tOr('cameraToggleFailed', 'Kamera değiştirilemedi'));
    }
  }

  Future<void> switchCamera() async {
    if (localVideoTrack == null) return;
    await Helper.switchCamera(localVideoTrack!.mediaStreamTrack);
    isFrontCamera = !isFrontCamera;
    _notify();
  }

  // ── Arka plan yönetimi ─────────────────────────────────────────────────────────
  Future<void> handleBackground(TranslationPack loc) async {
    if (!cameraEnabled) return;
    try { await room?.localParticipant?.setCameraEnabled(false); } catch (_) {}
    cameraEnabled = false;
    localVideoTrack = null;
    _notify();
    TeqToast.warning(loc.tOr(
      'hostCameraDisabledBackground',
      'Uygulama arka plana geçti — kamera duraklatıldı',
    ));
  }

  /// Ön plana dönünce izin durumunu kontrol eder, gerekirse kamera track'ini yeniler.
  Future<void> recheckPermissionsAfterResume(bool wasBackgrounded, TranslationPack loc) async {
    final camStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    if (_disposed) return;

    if (!camStatus.isGranted && cameraEnabled) {
      cameraEnabled = false;
      localVideoTrack = null;
      _notify();
      try { await room?.localParticipant?.setCameraEnabled(false); } catch (_) {}
      TeqToast.warning(loc.tOr('permCameraRevoked', 'Kamera izni kaldırıldı'));
      return;
    }
    if (!micStatus.isGranted && micEnabled) {
      micEnabled = false;
      _notify();
      try { await room?.localParticipant?.setMicrophoneEnabled(false); } catch (_) {}
      TeqToast.warning(loc.tOr('permMicRevoked', 'Mikrofon izni kaldırıldı'));
    }

    // iOS kamera donmasına karşı: arka plandan döndükten sonra disable→enable cycle
    if (wasBackgrounded && cameraEnabled && camStatus.isGranted) {
      await restartCameraTrack();
    }
  }

  /// iOS kamera track donmasını çözmek için disable→enable cycle uygular.
  Future<void> restartCameraTrack() async {
    if (room == null || _disposed) return;
    try {
      await room!.localParticipant?.setCameraEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await room!.localParticipant?.setCameraEnabled(
        true,
        cameraCaptureOptions: _cameraOptionsForProfile(_token?.videoQualityProfile ?? 'standard'),
      );
      LocalVideoTrack? fresh;
      for (final pub in room?.localParticipant?.videoTrackPublications ?? []) {
        if (pub.track != null) { fresh = pub.track as LocalVideoTrack; break; }
      }
      localVideoTrack = fresh;
      _notify();
    } catch (e) {
      _log.captureException(e, tag: 'HostStream.restartCamera');
    }
  }

  // ── Yayın bitirme + oda temizleme ─────────────────────────────────────────────
  Future<void> closeRoomAndNavigate(int streamId, String title) async {
    // Listener'ı önce dispose et: disconnect sonrası RoomDisconnectedEvent
    // scheduleReconnect'i tetiklemesin (clientInitiated guard yeterli olsa da
    // defensive olarak burada da kapatıyoruz).
    _listener?.dispose();
    _listener = null;

    try {
      await _stream.endStream(streamId);
    } catch (e, st) {
      _log.captureException(e, stackTrace: st, tag: 'HostStream.endStream');
    }

    // Endüstri standardı: kamera/mikrofon önce kapat (LED hemen söner), sonra disconnect.
    try {
      await room?.localParticipant?.setCameraEnabled(false);
      await room?.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    await room?.disconnect();
    room = null;
    localVideoTrack = null;
    _notify();
    onNavigateToReport?.call(streamId, title);
  }

  // ── Analytics ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getAudienceSize(String title, String category) async {
    try { return await _analytics.getAudienceSize(title: title, category: category); }
    catch (_) { return null; }
  }

  Future<Map<String, dynamic>?> sendLeadBlast(String title, String category, int estimatedCost) async {
    try {
      return await _analytics.sendLeadBlast(title: title, category: category, estimatedCost: estimatedCost);
    } catch (e) { return {'error': e.toString()}; }
  }

  Future<Map<String, dynamic>?> fetchAudienceInsights(int streamId) async {
    try { return await _stream.fetchAudienceInsights(streamId); }
    catch (_) { return null; }
  }

  Future<List<Map<String, dynamic>>> getViewers(int streamId) async {
    try { return await _stream.getViewers(streamId); }
    catch (_) { return []; }
  }

  Future<void> inviteCoHost(int streamId, String username) =>
      _stream.inviteCoHost(streamId, username);

  Future<void> removeCoHost(int streamId, String username) =>
      _stream.removeCoHost(streamId, username);

  Future<bool> uploadThumbnail(int streamId, Uint8List imageBytes) async {
    try { await _stream.uploadThumbnail(streamId, imageBytes, 'thumb.png'); return true; }
    catch (_) { return false; }
  }

  // ── Açık artırma ───────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchBids(int streamId) async {
    try { return await _auction.fetchBids(streamId); }
    catch (_) { return []; }
  }

  // ── Moderasyon ────────────────────────────────────────────────────────────────
  Future<bool> promoteUser(int streamId, String username) async {
    try { await _moderation.promoteUser(streamId, username); return true; }
    catch (_) { return false; }
  }

  Future<bool> demoteUser(int streamId, String username) async {
    try { await _moderation.demoteUser(streamId, username); return true; }
    catch (_) { return false; }
  }

  Future<bool> muteUser(int streamId, String username) async {
    try { await _moderation.mute(streamId, username); return true; }
    catch (_) { return false; }
  }

  Future<bool> unmuteUser(int streamId, String username) async {
    try { await _moderation.unmute(streamId, username); return true; }
    catch (_) { return false; }
  }

  Future<bool> kickUser(int streamId, String username) async {
    try { await _moderation.kick(streamId, username); return true; }
    catch (_) { return false; }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _listener?.dispose();
    hasPinned.dispose();
    super.dispose();
  }
}

final hostStreamViewModelProvider = ChangeNotifierProvider.autoDispose<HostStreamViewModel>((ref) {
  return HostStreamViewModel(
    ref.watch(analyticsServiceProvider),
    ref.watch(auctionServiceProvider),
    ref.watch(moderationServiceProvider),
    ref.watch(streamServiceProvider),
  );
});
