import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/api.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/auth_service.dart';
import '../../services/stream_service.dart';
import '../../widgets/auction_panel.dart';
import '../../widgets/chat_panel.dart';

class SwipeLiveScreen extends StatefulWidget {
  final List<StreamOut> streams;
  final int initialIndex;

  const SwipeLiveScreen({
    super.key,
    required this.streams,
    required this.initialIndex,
  });

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
    setState(() {
      _loading = true;
      _remoteVideoTrack = null;
      _streamEnded = false;
    });
    try {
      final token = await StreamService.joinStream(widget.stream.id);
      if (!mounted) return;

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
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() => _streamEnded = true);
      }
    } catch (_) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔊 Susturma kaldırıldı'),
        backgroundColor: Color(0xFF16A34A),
        duration: Duration(seconds: 3),
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

  Future<void> _deactivate() async {
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    _token = null;
    try {
      await StreamService.leaveStream(widget.stream.id);
    } catch (_) {}
    await room?.disconnect();
    if (mounted) setState(() => _remoteVideoTrack = null);
  }

  // dispose'da await kullanamayız, senkron temizlik
  void _deactivateSync() {
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    _token = null;
    room?.disconnect();
    try {
      StreamService.leaveStream(widget.stream.id);
    } catch (_) {}
  }

  Future<void> _leave() async {
    await _deactivate();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    const Text('Yayın Sona Erdi',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text('Kaydırarak başka yayınları keşfet',
                        style: TextStyle(color: Colors.white60, fontSize: 13)),
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
          child: Container(
            padding: EdgeInsets.only(
                top: topPad + 14, left: 16, right: 16, bottom: 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xBB000000), Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                // Geri
                GestureDetector(
                  key: const Key('swipe_live_btn_geri'),
                  onTap: _leave,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                // CANLI badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: _streamEnded ? Colors.grey : Colors.red,
                      borderRadius: BorderRadius.circular(5)),
                  child: Text(
                    _streamEnded ? 'BİTTİ' : 'CANLI',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(width: 6),
                // İzleyici sayısı
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('👁 $_viewerCount',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 11)),
                ),
                const SizedBox(width: 10),
                // Başlık + host
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.stream.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@${widget.stream.host.username}',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Ayrıl
                GestureDetector(
                  key: const Key('swipe_live_btn_ayril'),
                  onTap: _leave,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text('Ayrıl',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Swipe ipucu (son sayfa değilse) ─────────────────────────────
        if (!widget.isLast && !_streamEnded)
          Positioned(
            bottom: botPad + 104,
            left: 0,
            right: 0,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_arrow_up_rounded,
                      color: Colors.white30, size: 24),
                  Text('Sonraki yayın',
                      style: TextStyle(color: Colors.white30, fontSize: 11)),
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
                  ),
                  AuctionPanel(
                    streamId: widget.stream.id,
                    isHost: false,
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
