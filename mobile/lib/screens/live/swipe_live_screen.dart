import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/api.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../core/app_exception.dart';
import '../../core/logger_service.dart';
import '../../services/storage_service.dart';
import '../../services/stream_service.dart';
import '../../utils/error_helper.dart';
import '../../widgets/auction_panel.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/chat_panel.dart';
import '../../widgets/live/cohost_mod_sheet.dart';
import '../../widgets/live/floating_hearts.dart';
import '../../widgets/live/viewer_top_bar.dart';
import '../public_profile_screen.dart';

class SwipeLiveScreen extends StatefulWidget {
  final List<StreamOut> streams;
  final int initialIndex;

  const SwipeLiveScreen({
    super.key,
    required this.streams,
    required this.initialIndex,
  });

  /// Tek bir yayına doğrudan streamId ile katılmak için kullanılır.
  /// SwipeLiveScreen iç yapısı lazy token çekeceğinden önceden joinStream
  /// çağırmaya gerek yoktur.
  factory SwipeLiveScreen.single({required int streamId}) {
    return SwipeLiveScreen(
      streams: [
        StreamOut(
          id: streamId,
          roomName: '',
          title: '',
          category: '',
          viewerCount: 0,
          host: StreamHost(id: 0, username: ''),
        ),
      ],
      initialIndex: 0,
    );
  }

  @override
  State<SwipeLiveScreen> createState() => _SwipeLiveScreenState();
}

class _SwipeLiveScreenState extends State<SwipeLiveScreen> {
  late final PageController _pageCtrl;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _currentPage = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: PageView.builder(
        controller: _pageCtrl,
        scrollDirection: Axis.vertical,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemCount: widget.streams.length,
        itemBuilder: (_, i) => _SwipeLivePage(
          key: ValueKey(widget.streams[i].id),
          stream: widget.streams[i],
          isActive: i == _currentPage,
          isLast: i == widget.streams.length - 1,
        ),
      ),
    );
  }
}

// ── Tek yayın sayfası ────────────────────────────────────────────────────────

class _SwipeLivePage extends StatefulWidget {
  final StreamOut stream;
  final bool isActive;
  final bool isLast;

  const _SwipeLivePage({
    super.key,
    required this.stream,
    required this.isActive,
    required this.isLast,
  });

  @override
  State<_SwipeLivePage> createState() => _SwipeLivePageState();
}

class _SwipeLivePageState extends State<_SwipeLivePage> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  JoinTokenOut? _token;
  VideoTrack? _remoteVideoTrack;       // Ana ekran — host'un video track'i
  VideoTrack? _coHostVideoTrack;       // PiP — başka birinin co-host track'i
  LocalVideoTrack? _localVideoTrack;   // PiP — kendim co-host olduğumda kamera
  String? _hostParticipantSid;         // İlk video track'i kimin olduğunu takip eder
  bool _loading = false;
  bool _streamEnded = false;
  int _viewerCount = 0;
  bool _selfMuted = false;
  bool _kicked = false;
  bool _isCoHost = false;
  bool _isSelfCoHost = false;          // Ben sahneye çıktım → local kamera açık
  double? _pipTop;                     // Sürüklenebilir PiP konumu
  double? _pipLeft;
  final Set<String> _coHostMutedUsers = {};
  final _heartsKey = GlobalKey<FloatingHeartsState>();
  Timer? _likeThrottleTimer;
  bool _likeThrottlePending = false;
  // single() modunda token geldikten sonra doldurulur
  String? _resolvedTitle;
  String? _resolvedHostUsername;
  // Sahne daveti kontrol için kendi kullanıcı adım
  String? _myUsername;
  // leaveStream'in çift çağrılmasını önler
  bool _leftStream = false;
  // Kazanan konfetisi
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    if (widget.isActive) _activate();
  }

  @override
  void didUpdateWidget(_SwipeLivePage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _activate();
    } else if (!widget.isActive && old.isActive) {
      _deactivate();
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _deactivateSync();
    super.dispose();
  }

  void _onAuctionWon() {
    _confettiController.play();
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 200), HapticFeedback.vibrate);
  }

  Future<void> _activate() async {
    if (!mounted) return;
    _leftStream = false;
    setState(() {
      _loading = true;
      _remoteVideoTrack = null;
      _coHostVideoTrack = null;
      _streamEnded = false;
    });

    // Kendi kullanıcı adını yükle (sahne daveti kontrolü için)
    if (_myUsername == null) {
      final info = await StorageService.getUserInfo();
      _myUsername = info?['username'] as String?;
    }

    try {
      final token = await StreamService.joinStream(widget.stream.id);
      if (!mounted) return;

      // single() modu: stub'daki boş title/username'i token'dan doldur
      if (_resolvedTitle == null) {
        setState(() {
          _resolvedTitle = token.title;
          _resolvedHostUsername = token.hostUsername;
        });
      }

      final room = Room();
      _listener = room.createListener();

      _listener!.on<TrackSubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          final vTrack = e.track as VideoTrack;
          final isHostTrack = e.participant.identity == token.hostLivekitIdentity;
          if (isHostTrack) {
            setState(() {
              _remoteVideoTrack = vTrack;
              _hostParticipantSid = e.participant.sid;
            });
          } else if (e.participant.sid != _hostParticipantSid) {
            // Farklı katılımcı = co-host → PiP'e
            setState(() => _coHostVideoTrack = vTrack);
          }
        }
      });
      _listener!.on<TrackUnsubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          if (e.track == _remoteVideoTrack) {
            setState(() => _remoteVideoTrack = null);
          } else if (e.track == _coHostVideoTrack) {
            setState(() => _coHostVideoTrack = null);
          }
        }
      });
      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted) setState(() => _remoteVideoTrack = null);
      });

      await room.connect(
        token.livekitUrl,
        token.token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );

      // Zaten yayında olan track'leri kontrol et
      for (final p in room.remoteParticipants.values) {
        final isHostParticipant = p.identity == token.hostLivekitIdentity;
        if (isHostParticipant) _hostParticipantSid = p.sid;
        for (final pub in p.videoTrackPublications) {
          if (pub.track != null) {
            final vTrack = pub.track as VideoTrack;
            if (isHostParticipant) {
              _remoteVideoTrack = vTrack;
            } else {
              _coHostVideoTrack = vTrack;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _token = token;
          _room = room;
          _loading = false;
        });
      }
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.statusCode == 403) {
        showErrorSnackbar(context, e);
        setState(() => _streamEnded = true);
      } else {
        showErrorSnackbar(context, e);
      }
    } catch (e, st) {
      LoggerService.instance.captureException(e, stackTrace: st, tag: 'SwipeLivePage._activate');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleMuted() {
    if (!mounted) return;
    setState(() => _selfMuted = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔇 Bu yayında susturuldunuz'),
        backgroundColor: Color(0xFFD97706),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _handleUnmuted() {
    if (!mounted) return;
    setState(() => _selfMuted = false);
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔊 ${l.modUnmutedMsg}'),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleKicked() {
    if (!mounted || _kicked) return;
    _kicked = true;
    _room?.disconnect();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚫 Bu yayından atıldınız'),
        backgroundColor: Color(0xFFEF4444),
        duration: Duration(seconds: 4),
      ),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  void _handleModPromotedSelf(String promotedBy) {
    if (!mounted || _isCoHost) return;
    setState(() => _isCoHost = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⭐ @$promotedBy sizi moderatör yaptı! Artık izleyicileri yönetebilirsiniz.'),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _handleModDemotedSelf(String demotedBy) {
    if (!mounted) return;
    setState(() => _isCoHost = false);
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.liveModDemotedSelf(demotedBy)),
        backgroundColor: const Color(0xFF475569),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showCoHostInviteDialog(String hostUsername) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Text('🎬', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'Sahneye Davet Edildiniz!',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          '@$hostUsername sizi sahneye davet etti.\nKameranız açılacak — kabul ediyor musunuz?',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Reddet', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kabul Et', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((accepted) {
      if (accepted == true) _acceptCoHostInvite();
    });
  }

  void _handleCoHostRemoved() {
    if (!mounted) return;
    // Kamerayı kapat, local track'i temizle
    _room?.localParticipant?.setCameraEnabled(false);
    _room?.localParticipant?.setMicrophoneEnabled(false);
    setState(() {
      _localVideoTrack = null;
      _isSelfCoHost = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📵 Sahneden kaldırıldınız'),
        backgroundColor: Color(0xFF475569),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _acceptCoHostInvite() async {
    // 1. Kamera ve mikrofon izni iste
    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (!mounted) return;
    if (camStatus.isDenied || micStatus.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sahneye çıkmak için kamera ve mikrofon izni gerekli'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Yeni can_publish=true token al
    late StreamTokenOut newToken;
    try {
      newToken = await StreamService.acceptCoHostInvite(widget.stream.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sahne bağlantısı kurulamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    // 3. Mevcut odadan çık (leaveStream çağırmıyoruz, yeniden join edeceğiz)
    _listener?.dispose();
    _listener = null;
    await _room?.disconnect();
    _room = null;
    _hostParticipantSid = null;
    _coHostVideoTrack = null;

    // 4. Yeni token ile odaya yayıncı olarak bağlan
    try {
      final room = Room();
      _listener = room.createListener();

      // Host'un track'ini ana ekrana bağla
      _listener!.on<TrackSubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          setState(() {
            _remoteVideoTrack = e.track as VideoTrack;
            _hostParticipantSid = e.participant.sid;
          });
        }
      });
      _listener!.on<TrackUnsubscribedEvent>((e) {
        if (e.track is VideoTrack && e.track == _remoteVideoTrack && mounted) {
          setState(() => _remoteVideoTrack = null);
        }
      });
      _listener!.on<LocalTrackPublishedEvent>((e) {
        if (e.publication.track is LocalVideoTrack && mounted) {
          setState(() => _localVideoTrack = e.publication.track as LocalVideoTrack);
        }
      });
      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted) {
          setState(() {
            _remoteVideoTrack = null;
            _localVideoTrack = null;
            _isSelfCoHost = false;
          });
        }
      });

      await room.connect(
        newToken.livekitUrl,
        newToken.token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );
      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);

      if (mounted) {
        setState(() {
          _room = room;
          _isSelfCoHost = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sahneye bağlanılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCoHostModSheet(String targetUsername) {
    final isMuted = _coHostMutedUsers.contains(targetUsername);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CoHostModSheet(
        streamId: widget.stream.id,
        username: targetUsername,
        isMuted: isMuted,
        onMuted:   () => setState(() => _coHostMutedUsers.add(targetUsername)),
        onUnmuted: () => setState(() => _coHostMutedUsers.remove(targetUsername)),
      ),
    );
  }

  Future<void> _deactivate() async {
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    _token = null;
    if (!_leftStream) {
      _leftStream = true;
      try {
        await StreamService.leaveStream(widget.stream.id);
      } catch (e) {
        LoggerService.instance.warning('SwipeLivePage._deactivate', 'leaveStream başarısız: $e');
      }
    }
    await room?.disconnect();
    if (mounted) {
      setState(() {
        _remoteVideoTrack = null;
        _coHostVideoTrack = null;
        _localVideoTrack = null;
        _hostParticipantSid = null;
        _isSelfCoHost = false;
      });
    }
  }

  // dispose'da await kullanamayız, senkron temizlik
  void _deactivateSync() {
    _likeThrottleTimer?.cancel();
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    _token = null;
    _hostParticipantSid = null;
    room?.disconnect();
    if (!_leftStream) {
      _leftStream = true;
      try {
        StreamService.leaveStream(widget.stream.id);
      } catch (e) {
        LoggerService.instance.warning('SwipeLivePage._deactivateSync', 'leaveStream başarısız: $e');
      }
    }
  }

  void _onHeartTap() {
    HapticFeedback.lightImpact();
    _heartsKey.currentState?.addHeart(isLocal: true);
    if (_likeThrottleTimer?.isActive ?? false) {
      _likeThrottlePending = true;
    } else {
      _fireLikeRequest();
      _likeThrottleTimer = Timer(const Duration(milliseconds: 1500), () {
        if (_likeThrottlePending) {
          _likeThrottlePending = false;
          _fireLikeRequest();
        }
      });
    }
  }

  void _fireLikeRequest() {
    StreamService.likeStream(widget.stream.id).catchError((_) {});
  }

  Future<void> _leave() async {
    await _deactivate();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final hasThumbnail =
        widget.stream.thumbnailUrl != null && widget.stream.thumbnailUrl!.isNotEmpty;

    return Stack(
      children: [
        // ── Arka plan: video veya thumbnail ──────────────────────────────
        if (_remoteVideoTrack != null)
          Positioned.fill(
            child: VideoTrackRenderer(
              _remoteVideoTrack!,
              fit: VideoViewFit.contain,
              mirrorMode: VideoViewMirrorMode.mirror,
            ),
          )
        else if (!widget.isActive && hasThumbnail)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: imgUrl(widget.stream.thumbnailUrl),
              fit: BoxFit.cover,
              placeholder: (_, __) => _darkBg(),
              errorWidget: (_, __, ___) => _darkBg(),
            ),
          )
        else
          Positioned.fill(child: _darkBg()),

        // ── Yükleniyor ───────────────────────────────────────────────────
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator(color: kPrimary)),
            ),
          ),

        // ── Yayın sona erdi overlay ──────────────────────────────────────
        if (_streamEnded)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded,
                        color: Colors.white38, size: 56),
                    const SizedBox(height: 12),
                    Text(l.liveStreamEndedOverlay,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(l.liveDiscoverStreams,
                        style: const TextStyle(color: Colors.white60, fontSize: 13)),
                    if (!widget.isLast) ...[
                      const SizedBox(height: 20),
                      const Icon(Icons.keyboard_arrow_up_rounded,
                          color: Colors.white38, size: 32),
                    ]
                  ],
                ),
              ),
            ),
          ),

        // ── Üst gradient bar ─────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ViewerTopBar(
            topPad: topPad,
            viewerCount: _viewerCount,
            title: _resolvedTitle ?? widget.stream.title,
            hostUsername: _resolvedHostUsername ?? widget.stream.host.username,
            isCoHost: _isCoHost,
            streamEnded: _streamEnded,
            onLeave: _leave,
            streamId: widget.stream.id,
            thumbnailUrl: widget.stream.thumbnailUrl,
          ),
        ),

        // ── Uçuşan kalpler ───────────────────────────────────────────────
        FloatingHearts(key: _heartsKey),

        // ── Co-Host PiP kutusu — sağ üst ────────────────────────────────
        // Öncelik: kendin co-host → local kamera. Değilse diğerinin track'i.
        if (_isSelfCoHost && _localVideoTrack != null)
          Positioned(
            top: _pipTop ?? (topPad + 70),
            left: _pipLeft ?? (MediaQuery.of(context).size.width - 110 - 16),
            child: GestureDetector(
              onPanUpdate: (d) {
                final s = MediaQuery.of(context).size;
                setState(() {
                  _pipTop  = ((_pipTop  ?? (topPad + 70)) + d.delta.dy).clamp(0.0, s.height - 160);
                  _pipLeft = ((_pipLeft ?? (s.width - 110 - 16)) + d.delta.dx).clamp(0.0, s.width - 110);
                });
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 110,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      VideoTrackRenderer(
                        _localVideoTrack!,
                        fit: VideoViewFit.contain,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () async {
                            final sid = _token?.streamId;
                            if (sid != null) {
                              try { await StreamService.leaveCoHost(sid); } catch (_) {}
                            }
                            _handleCoHostRemoved();
                          },
                          child: Container(
                            color: const Color(0xDDEF4444),
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            alignment: Alignment.center,
                            child: const Text(
                              '✕ Sahneden Çık',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (!_isSelfCoHost && _coHostVideoTrack != null)
          Positioned(
            top: _pipTop ?? (topPad + 70),
            left: _pipLeft ?? (MediaQuery.of(context).size.width - 110 - 16),
            child: GestureDetector(
              onPanUpdate: (d) {
                final s = MediaQuery.of(context).size;
                setState(() {
                  _pipTop  = ((_pipTop  ?? (topPad + 70)) + d.delta.dy).clamp(0.0, s.height - 160);
                  _pipLeft = ((_pipLeft ?? (s.width - 110 - 16)) + d.delta.dx).clamp(0.0, s.width - 110);
                });
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 110,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: VideoTrackRenderer(
                    _coHostVideoTrack!,
                    fit: VideoViewFit.contain,
                    mirrorMode: VideoViewMirrorMode.mirror,
                  ),
                ),
              ),
            ),
          ),

        // ── Swipe ipucu (son sayfa değilse) ─────────────────────────────
        if (!widget.isLast && !_streamEnded)
          Positioned(
            bottom: botPad + 104,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.keyboard_arrow_up_rounded,
                      color: Colors.white30, size: 24),
                  Text(l.liveNextStream,
                      style: const TextStyle(color: Colors.white30, fontSize: 11)),
                ],
              ),
            ),
          ),

        // ── Alt panel: sohbet + açık artırma ────────────────────────────
        if (widget.isActive && _token != null && !_streamEnded)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(bottom: botPad + 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                  stops: [0.0, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChatPanel(
                    streamId: widget.stream.id,
                    onStreamEnded: () =>
                        setState(() => _streamEnded = true),
                    onViewerCountChanged: (n) =>
                        setState(() => _viewerCount = n),
                    onMuted: _handleMuted,
                    onUnmuted: _handleUnmuted,
                    onKicked: _handleKicked,
                    onModPromotedSelf: _handleModPromotedSelf,
                    onModDemotedSelf: _handleModDemotedSelf,
                    onModRestored: () {
                      if (mounted && !_isCoHost)
                        setState(() => _isCoHost = true);
                    },
                    onStreamLike: (_, __) =>
                        _heartsKey.currentState?.addHeart(isLocal: false),
                    onCoHostInvite: (hostUsername, targetUsername) {
                      if (!mounted || _isSelfCoHost) return;
                      if (targetUsername == _myUsername) {
                        _showCoHostInviteDialog(hostUsername);
                      }
                    },
                    onCoHostRemoved: (targetUsername) {
                      if (!mounted || !_isSelfCoHost) return;
                      if (targetUsername == _myUsername) {
                        _handleCoHostRemoved();
                      }
                    },
                    onUsernameTap: (username) {
                      if (_isCoHost) {
                        _showCoHostModSheet(username);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PublicProfileScreen(username: username),
                          ),
                        );
                      }
                    },
                    pinAtBottom: true,
                    trailingAction: GestureDetector(
                      onTap: _onHeartTap,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.favorite,
                          color: Color(0xFFFF4081),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  AuctionPanel(
                    streamId: widget.stream.id,
                    isHost: false,
                    isCoHost: _isCoHost,
                    enabled: !_selfMuted,
                    hostUserId: int.tryParse(_token?.hostLivekitIdentity ?? ''),
                    myUsername: _myUsername,
                    onWin: _onAuctionWon,
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        // ── Kazanan konfetisi — tüm ekranı kaplar ───────────────────────
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
            gravity: 0.2,
            colors: const [
              Color(0xFFFBBF24), // amber
              Color(0xFF06B6D4), // cyan (tema rengi)
              Color(0xFF22D3EE), // cyan-light
              Color(0xFFF97316), // orange
              Colors.white,
            ],
          ),
        ),
      ],
    );
  }

  Widget _darkBg() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Center(
          child: Icon(Icons.videocam_rounded, color: Colors.white10, size: 56),
        ),
      );
}

