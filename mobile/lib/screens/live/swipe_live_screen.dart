import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/api.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../core/app_exception.dart';
import '../../core/logger_service.dart';
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
  VideoTrack? _remoteVideoTrack;
  bool _loading = false;
  bool _streamEnded = false;
  int _viewerCount = 0;
  bool _selfMuted = false;
  bool _kicked = false;
  bool _isCoHost = false;
  final Set<String> _coHostMutedUsers = {};
  final _heartsKey = GlobalKey<FloatingHeartsState>();
  Timer? _likeThrottleTimer;
  bool _likeThrottlePending = false;
  // single() modunda token geldikten sonra doldurulur
  String? _resolvedTitle;
  String? _resolvedHostUsername;
  // leaveStream'in çift çağrılmasını önler
  bool _leftStream = false;

  @override
  void initState() {
    super.initState();
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
    _deactivateSync();
    super.dispose();
  }

  Future<void> _activate() async {
    if (!mounted) return;
    _leftStream = false;
    setState(() {
      _loading = true;
      _remoteVideoTrack = null;
      _streamEnded = false;
    });
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
          setState(() => _remoteVideoTrack = e.track as VideoTrack);
        }
      });
      _listener!.on<TrackUnsubscribedEvent>((e) {
        if (e.track is VideoTrack && mounted) {
          setState(() => _remoteVideoTrack = null);
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
        for (final pub in p.videoTrackPublications) {
          if (pub.track != null) {
            _remoteVideoTrack = pub.track as VideoTrack;
            break;
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
    if (mounted) setState(() => _remoteVideoTrack = null);
  }

  // dispose'da await kullanamayız, senkron temizlik
  void _deactivateSync() {
    _likeThrottleTimer?.cancel();
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    _token = null;
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
          ),
        ),

        // ── Uçuşan kalpler ───────────────────────────────────────────────
        FloatingHearts(key: _heartsKey),

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
                  ),
                  const SizedBox(height: 4),
                ],
              ),
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

