import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/moderation_service.dart';
import '../../services/storage_service.dart';
import '../../services/stream_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/auction_panel.dart';
import '../../widgets/chat_panel.dart';
import '../../widgets/live/floating_hearts.dart';
import '../../widgets/live/live_video_player.dart';
import '../../widgets/live/viewer_top_bar.dart';
import '../public_profile_screen.dart';

class ViewerStreamScreen extends StatefulWidget {
  final JoinTokenOut joinToken;

  const ViewerStreamScreen({super.key, required this.joinToken});

  @override
  State<ViewerStreamScreen> createState() => _ViewerStreamScreenState();
}

class _ViewerStreamScreenState extends State<ViewerStreamScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _remoteVideoTrack;
  bool _connecting = true;
  String? _error;
  int _viewerCount = 0;
  bool _selfMuted = false;
  bool _kicked = false; // kick işlemi sırasında RoomDisconnectedEvent'i baskıla
  bool _isCoHost = false;
  final Set<String> _coHostMutedUsers = {};

  // ── Uçuşan kalpler ──────────────────────────────────────────────────────
  final _heartsKey = GlobalKey<FloatingHeartsState>();

  // ── Throttle: en fazla 1 API isteği / 1.5 saniye ──────────────────────
  // Kullanıcı hızlı tıklarsa animasyonu anında göster, API'yi geri tut.
  Timer? _likeThrottleTimer;
  bool _likeThrottlePending = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _connect();
  }

  @override
  void dispose() {
    _likeThrottleTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _listener?.dispose();
    _room?.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final room = Room();
      _listener = room.createListener();

      _listener!.on<TrackSubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          setState(() {
            _remoteVideoTrack = event.track as VideoTrack;
            _connecting = false;
          });
        }
      });

      _listener!.on<TrackUnsubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          setState(() => _remoteVideoTrack = null);
        }
      });

      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted && !_kicked) {
          final l = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.liveEnded)),
          );
          Navigator.pushNamedAndRemoveUntil(
              context, '/home', (route) => false);
        }
      });

      await room.connect(
        widget.joinToken.livekitUrl,
        widget.joinToken.token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );

      for (final participant in room.remoteParticipants.values) {
        for (final pub in participant.videoTrackPublications) {
          if (pub.track != null) {
            _remoteVideoTrack = pub.track as VideoTrack;
            break;
          }
        }
      }

      setState(() {
        _room = room;
        if (_remoteVideoTrack != null) _connecting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Bağlantı hatası: ${e.toString()}';
        _connecting = false;
      });
    }
  }

  Future<void> _handleMuted() async {
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

  Future<void> _handleUnmuted() async {
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
    debugPrint('[VIEWER] _handleKicked çağrıldı | mounted=$mounted _kicked=$_kicked');
    if (!mounted || _kicked) return;
    _kicked = true;
    debugPrint('[VIEWER] kick işleniyor — room disconnect + navigate home');
    _room?.disconnect(); // fire-and-forget
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚫 Bu yayından atıldınız'),
        backgroundColor: Color(0xFFEF4444),
        duration: Duration(seconds: 4),
      ),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  // Hedefli event: username eşleşmesine gerek yok — ben atandım
  void _handleModPromotedSelf(String promotedBy) {
    debugPrint('[VIEWER] _handleModPromotedSelf ÇAĞRILDI — mounted:$mounted _isCoHost:$_isCoHost promotedBy:$promotedBy');
    if (!mounted || _isCoHost) {
      debugPrint('[VIEWER] _handleModPromotedSelf GUARD BLOK ETTİ — mounted:$mounted _isCoHost:$_isCoHost');
      return;
    }
    debugPrint('[VIEWER] _handleModPromotedSelf → setState _isCoHost=true');
    setState(() => _isCoHost = true);
    debugPrint('[VIEWER] _handleModPromotedSelf → SnackBar gösteriliyor');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⭐ @$promotedBy sizi moderatör yaptı! Artık izleyicileri yönetebilirsiniz.'),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 5),
      ),
    );
    debugPrint('[VIEWER] _handleModPromotedSelf → TAMAMLANDI');
  }

  // Hedefli event: username eşleşmesine gerek yok — benim moderatörlüğüm kaldırıldı
  void _handleModDemotedSelf(String demotedBy) {
    if (!mounted) return;
    setState(() => _isCoHost = false);
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.liveModDemotedSelf(demotedBy)),
        backgroundColor: const Color(0xFF475569),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Co-Host için moderasyon bottom sheet'i — Moderatör Yap butonu YOK.
  void _showCoHostModSheet(String targetUsername) {
    final isMuted = _coHostMutedUsers.contains(targetUsername);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CoHostModSheet(
        streamId: widget.joinToken.streamId,
        username: targetUsername,
        isMuted: isMuted,
        onMuted:   () => setState(() => _coHostMutedUsers.add(targetUsername)),
        onUnmuted: () => setState(() => _coHostMutedUsers.remove(targetUsername)),
      ),
    );
  }

  Future<void> _handleStreamEnded() async {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(l.liveStreamEndedTitle,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(l.liveStreamEndedDesc,
            style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child:
                Text(l.btnOk, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  /// Kalp butonuna veya çift tıklamaya basıldığında çağrılır.
  ///
  /// Throttle mantığı:
  /// - Animasyon ANINDA tetiklenir (UI hiç beklemez).
  /// - API isteği, _likeThrottleTimer süresi dolduğunda TEK BİR KEZ atılır.
  ///   Bu sayede 1.5 sn içindeki seri tıklamalar tek bir HTTP isteğine indirgenir.
  void _onHeartTap() {
    HapticFeedback.lightImpact();
    // Yerel kalbi anında uçur
    _heartsKey.currentState?.addHeart(isLocal: true);

    if (_likeThrottleTimer?.isActive ?? false) {
      // Timer çalışıyor → sadece "beklemede" bayrağını işaretle
      _likeThrottlePending = true;
    } else {
      // İlk tıklama ya da timer dolmuş → isteği hemen at, yeni timer başlat
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
    StreamService.likeStream(widget.joinToken.streamId).catchError((_) {});
  }

  Future<void> _leave() async {
    try {
      await StreamService.leaveStream(widget.joinToken.streamId);
    } catch (_) {}
    await _room?.disconnect();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final connected = !_connecting && _error == null;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Video katmanı (tam ekran) — host track'i + bekleme durumu ───
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _onHeartTap,
              child: Builder(
                builder: (ctx) => LiveVideoPlayer(
                  track: _remoteVideoTrack,
                  cameraEnabled: true,
                  waitingLabel: AppLocalizations.of(ctx)!.liveWaitingVideo,
                ),
              ),
            ),
          ),

          // ── Bağlanıyor ─────────────────────────────────────────────────
          if (_connecting && _error == null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: kPrimary),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (ctx) => Text(AppLocalizations.of(ctx)!.liveConnectingViewer,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Hata ───────────────────────────────────────────────────────
          if (_error != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 52),
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        Builder(
                          builder: (ctx) => ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(AppLocalizations.of(ctx)!.liveGoBack),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Uçuşan kalpler katmanı ────────────────────────────────────
          FloatingHearts(key: _heartsKey),

          // ── Üst bar: geri + CANLI + izleyici + başlık + MOD + Ayrıl ────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ViewerTopBar(
              topPad: topPad,
              viewerCount: _viewerCount,
              title: widget.joinToken.title,
              hostUsername: widget.joinToken.hostUsername,
              isCoHost: _isCoHost,
              onLeave: _leave,
            ),
          ),

          // ── Alt panel: sohbet + açık artırma + kalp butonu ────────────
          if (connected)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Gradient arka plan + içerik
                  Container(
                    padding: EdgeInsets.only(
                        bottom: botPad + 8, right: 58),
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
                          streamId: widget.joinToken.streamId,
                          onStreamEnded: _handleStreamEnded,
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
                              _heartsKey.currentState
                                  ?.addHeart(isLocal: false),
                          onUsernameTap: (username) {
                            debugPrint(
                                '[VIEWER] onUsernameTap — username:$username _isCoHost:$_isCoHost');
                            if (_isCoHost) {
                              _showCoHostModSheet(username);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PublicProfileScreen(
                                      username: username),
                                ),
                              );
                            }
                          },
                          pinAtBottom: true,
                        ),
                        AuctionPanel(
                          streamId: widget.joinToken.streamId,
                          isHost: false,
                          isCoHost: _isCoHost,
                          enabled: !_selfMuted,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  // Kalp butonu — sağ alta sabit, ChatPanel input hizasında
                  Positioned(
                    right: 8,
                    bottom: botPad + 12,
                    child: GestureDetector(
                      onTap: _onHeartTap,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white30, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.favorite,
                          color: Color(0xFFFF4081),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Co-Host Moderasyon Bottom Sheet ──────────────────────────────────────────
// Sadece Sustur / Susturmayı Kaldır / Yayından At — "Moderatör Yap" KESİNLİKLE YOK.

class _CoHostModSheet extends StatefulWidget {
  final int streamId;
  final String username;
  final bool isMuted;
  final VoidCallback onMuted;
  final VoidCallback onUnmuted;

  const _CoHostModSheet({
    required this.streamId,
    required this.username,
    required this.isMuted,
    required this.onMuted,
    required this.onUnmuted,
  });

  @override
  State<_CoHostModSheet> createState() => _CoHostModSheetState();
}

class _CoHostModSheetState extends State<_CoHostModSheet> {
  bool _loading = false;
  String? _msg;
  bool _isError = false;
  late bool _isMuted;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.isMuted;
  }

  Future<void> _act(Future<void> Function() fn, {
    required String successMsg,
    VoidCallback? onSuccess,
  }) async {
    setState(() { _loading = true; _msg = null; });
    try {
      await fn();
      onSuccess?.call();
      if (mounted) setState(() { _loading = false; _msg = successMsg; _isError = false; });
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) setState(() { _loading = false; _msg = e.toString(); _isError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('🛡 ${l.modTitle}',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('@${widget.username}',
                  style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 14),

          // Sustur / Susturmayı Kaldır
          if (!_isMuted)
            _CoHostModBtn(
              icon: '🔇', label: l.modMute,
              color: const Color(0xFFD97706), loading: _loading,
              onTap: () => _act(
                () => ModerationService.mute(widget.streamId, widget.username),
                successMsg: '@${widget.username} susturuldu',
                onSuccess: () { widget.onMuted(); setState(() => _isMuted = true); },
              ),
            )
          else
            _CoHostModBtn(
              icon: '🔊', label: l.modUnmute,
              color: const Color(0xFF16A34A), loading: _loading,
              onTap: () => _act(
                () => ModerationService.unmute(widget.streamId, widget.username),
                successMsg: l.modUnmutedMsg,
                onSuccess: () { widget.onUnmuted(); setState(() => _isMuted = false); },
              ),
            ),
          const SizedBox(height: 10),

          // Yayından At
          _CoHostModBtn(
            icon: '🚫', label: l.modKick,
            color: const Color(0xFFEF4444), loading: _loading,
            onTap: () => _act(
              () => ModerationService.kick(widget.streamId, widget.username),
              successMsg: '@${widget.username} yayından atıldı',
            ),
          ),
          const SizedBox(height: 10),

          // İptal
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _loading ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.white12),
                ),
              ),
              child: Text(l.btnCancel,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
            ),
          ),

          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Text(
                  _msg!,
                  style: TextStyle(
                    color: _isError ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoHostModBtn extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _CoHostModBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onTap,
        icon: Text(icon, style: const TextStyle(fontSize: 16)),
        label: Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withOpacity(0.45),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    );
  }
}
