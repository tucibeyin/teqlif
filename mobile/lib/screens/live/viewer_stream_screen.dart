import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/moderation_service.dart';
import '../../services/storage_service.dart';
import '../../services/stream_service.dart';
import '../../widgets/auction_panel.dart';
import '../../widgets/chat_panel.dart';

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
  String? _currentUsername;
  final Set<String> _coHostMutedUsers = {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _connect();
    _loadCurrentUsername();
  }

  Future<void> _loadCurrentUsername() async {
    try {
      final info = await StorageService.getUserInfo();
      if (mounted) setState(() => _currentUsername = info?['username'] as String?);
    } catch (e) {
      debugPrint('[VIEWER] Kullanıcı adı yüklenemedi: $e');
    }
  }

  @override
  void dispose() {
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yayın sona erdi')),
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

  void _handleModPromoted(String targetUsername, String promotedBy) {
    if (!mounted) return;
    if (_currentUsername == null || _currentUsername != targetUsername) return;
    setState(() => _isCoHost = true);
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⭐', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              const Text(
                'Moderatör oldunuz!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '@$promotedBy sizi moderatör yaptı.\nArtık izleyicileri susturabilir ve yayından atabilirsiniz.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(_),
                  child: const Text('Anladım', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleModDemoted(String targetUsername, String demotedBy) {
    if (!mounted) return;
    if (_currentUsername == null || _currentUsername != targetUsername) return;
    setState(() => _isCoHost = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moderatörlüğünüz @$demotedBy tarafından kaldırıldı.'),
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
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Yayın Sona Erdi',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: const Text('Bu yayın yayıncı tarafından sonlandırıldı.',
            style: TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Tamam', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
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
          // ── Video (tam ekran) ───────────────────────────────────────────
          if (_remoteVideoTrack != null)
            Positioned.fill(
              child: VideoTrackRenderer(
                _remoteVideoTrack!,
                fit: VideoViewFit.contain,
              ),
            ),

          // ── Bağlanıyor ─────────────────────────────────────────────────
          if (_connecting && _error == null)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: kPrimary),
                      SizedBox(height: 16),
                      Text('Yayına bağlanıyor...',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Video bekleniyor ───────────────────────────────────────────
          if (connected && _remoteVideoTrack == null)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined,
                          color: Colors.white24, size: 52),
                      SizedBox(height: 12),
                      Text('Video bekleniyor...',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 14)),
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
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Geri Dön'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Üst gradient bar ────────────────────────────────────────────
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
                    key: const Key('viewer_btn_geri'),
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
                  // LIVE badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(5)),
                    child: const Text('CANLI',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                  ),
                  const SizedBox(width: 6),
                  // İzleyici sayısı
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '👁 $_viewerCount',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Başlık + host
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.joinToken.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black)
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '@${widget.joinToken.hostUsername}',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  // Ayrıl
                  GestureDetector(
                    key: const Key('viewer_btn_ayril'),
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

          // ── Alt panel: sohbet + açık artırma ───────────────────────────
          if (connected)
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
                    // Sohbet (mesajlar üstte yüzer)
                    ChatPanel(
                      streamId: widget.joinToken.streamId,
                      onStreamEnded: _handleStreamEnded,
                      onViewerCountChanged: (n) =>
                          setState(() => _viewerCount = n),
                      onMuted: _handleMuted,
                      onUnmuted: _handleUnmuted,
                      onKicked: _handleKicked,
                      onModPromoted: _handleModPromoted,
                      onModDemoted: _handleModDemoted,
                      // Co-Host ise kullanıcı adına tıklanınca mod sheet açılır
                      onUsernameTap: _isCoHost ? _showCoHostModSheet : null,
                    ),
                    // Açık artırma (co-host ise host kontrol UI'ı gösterilir)
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
              const Text('🛡 Moderasyon',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
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
              icon: '🔇', label: 'Sustur',
              color: const Color(0xFFD97706), loading: _loading,
              onTap: () => _act(
                () => ModerationService.mute(widget.streamId, widget.username),
                successMsg: '@${widget.username} susturuldu',
                onSuccess: () { widget.onMuted(); setState(() => _isMuted = true); },
              ),
            )
          else
            _CoHostModBtn(
              icon: '🔊', label: 'Susturmayı Kaldır',
              color: const Color(0xFF16A34A), loading: _loading,
              onTap: () => _act(
                () => ModerationService.unmute(widget.streamId, widget.username),
                successMsg: 'Susturma kaldırıldı',
                onSuccess: () { widget.onUnmuted(); setState(() => _isMuted = false); },
              ),
            ),
          const SizedBox(height: 10),

          // Yayından At
          _CoHostModBtn(
            icon: '🚫', label: 'Yayından At',
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
              child: const Text('İptal',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
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
