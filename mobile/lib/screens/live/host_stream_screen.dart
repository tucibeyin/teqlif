import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/stream_service.dart';
import '../../utils/price_formatter.dart';
import '../../utils/username_color.dart';
import '../../widgets/auction_panel.dart';
import '../../widgets/chat_panel.dart';
import '../../services/moderation_service.dart';
import '../../widgets/live/host_top_bar.dart';
import '../../widgets/live/live_video_player.dart';
import '../../l10n/app_localizations.dart';

class HostStreamScreen extends StatefulWidget {
  final StreamTokenOut streamToken;
  final String title;

  const HostStreamScreen({
    super.key,
    required this.streamToken,
    required this.title,
  });

  @override
  State<HostStreamScreen> createState() => _HostStreamScreenState();
}

class _HostStreamScreenState extends State<HostStreamScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  LocalVideoTrack? _localVideoTrack;
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _connecting = true;
  String? _error;
  final _videoKey = GlobalKey();
  Timer? _thumbTimer;
  int _viewerCount = 0;
  final List<_BidGroup> _bidGroups = [];
  bool _bidsVisible = true;
  double? _bidsPanelTop;
  final Set<String> _mutedUsers = {};
  double _currentZoom = 1.0;
  static const double _maxZoom = 8.0;
  final Set<String> _modUsers   = {};
  final _chatKey = GlobalKey<ChatPanelState>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    _connect();
  }

  @override
  void dispose() {
    _thumbTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _listener?.dispose();
    _room?.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (camStatus.isDenied || micStatus.isDenied) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        setState(() {
          _error = l.livePermissionRequired;
          _connecting = false;
        });
      } else {
        setState(() {
          _error = 'Permission denied';
          _connecting = false;
        });
      }
      return;
    }

    try {
      final room = Room();
      _listener = room.createListener();

      _listener!.on<LocalTrackPublishedEvent>((event) {
        if (event.publication.track is LocalVideoTrack) {
          setState(() {
            _localVideoTrack = event.publication.track as LocalVideoTrack;
          });
        }
      });

      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      });

      await room.connect(
        widget.streamToken.livekitUrl,
        widget.streamToken.token,
      );

      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);

      for (final pub in room.localParticipant!.videoTrackPublications) {
        if (pub.track != null) {
          _localVideoTrack = pub.track as LocalVideoTrack;
          break;
        }
      }

      setState(() {
        _room = room;
        _connecting = false;
      });
      // Yayın başladıktan 5 saniye sonra otomatik kapak fotoğrafı çek
      _thumbTimer = Timer(const Duration(seconds: 5), _autoCaptureThumbnail);
    } catch (e) {
      setState(() {
        _error = 'Bağlantı hatası: ${e.toString()}';
        _connecting = false;
      });
    }
  }

  Future<void> _toggleMic() async {
    _micEnabled = !_micEnabled;
    await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
    setState(() {});
  }

  Future<void> _toggleCamera() async {
    _cameraEnabled = !_cameraEnabled;
    await _room?.localParticipant?.setCameraEnabled(_cameraEnabled);
    setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_localVideoTrack == null) return;
    await Helper.switchCamera(_localVideoTrack!.mediaStreamTrack);
    setState(() => _currentZoom = 1.0);
  }


  void _onBidAdded(String bidder, double amount, String? itemName) {
    setState(() {
      if (_bidGroups.isEmpty || _bidGroups.last.title != itemName) {
        _bidGroups.add(_BidGroup(title: itemName));
      }
      _bidGroups.last.bids.insert(0, (bidder: bidder, amount: amount));
    });
  }

  void _onAuctionReset() {
    // Grup sınırı bid gelince otomatik açılır — listeyi temizlemiyoruz
    setState(() {});
  }

  Future<void> _showViewers() async {
    List<String> viewers = [];
    try {
      viewers = await StreamService.getViewers(widget.streamToken.streamId);
    } catch (_) {}
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
            const SizedBox(height: 14),
            Text(
              '👁 İzleyiciler (${viewers.length})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            if (viewers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  l.liveNoViewers,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: viewers.length,
                  itemBuilder: (_, i) {
                    final uname = viewers[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: usernameColor(uname).withOpacity(0.25),
                            child: Text(
                              uname.isNotEmpty ? uname[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: usernameColor(uname),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '@$uname',
                            style: TextStyle(
                              color: usernameColor(uname),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Sabitleme girişi ──────────────────────────────────────────────────────

  void _showPinInput() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        // StatefulBuilder → ctrl sheet'in kendi lifecycle'ında yaşar,
        // parent rebuild'lardan etkilenmez.
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return _PinInputSheet(
              onPin: (content) {
                _chatKey.currentState?.sendHostPin(content);
                Navigator.of(ctx).pop();
              },
              onCancel: () => Navigator.of(ctx).pop(),
            );
          },
        );
      },
    );
  }

  void _showModSheet(String username) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ModerationSheet(
        streamId: widget.streamToken.streamId,
        username: username,
        isMuted: _mutedUsers.contains(username),
        isMod: _modUsers.contains(username),
        onMuted: () => setState(() => _mutedUsers.add(username)),
        onUnmuted: () => setState(() => _mutedUsers.remove(username)),
        onPromoted: () => setState(() => _modUsers.add(username)),
        onDemoted: () => setState(() => _modUsers.remove(username)),
      ),
    );
  }

  Future<void> _endStream() async {
    final l = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(l.liveEndStreamTitle,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(l.liveEndStreamConfirm,
            style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.btnCancel,
                style: const TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.liveEndStreamBtn,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await StreamService.endStream(widget.streamToken.streamId);
    } catch (_) {}

    await _room?.disconnect();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  Future<void> _autoCaptureThumbnail() async {
    if (!mounted || _localVideoTrack == null) return;
    try {
      final boundary =
          _videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 0.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      await StreamService.uploadThumbnail(
        widget.streamToken.streamId,
        byteData.buffer.asUint8List(),
        'thumb.png',
      );
      // Her 60 saniyede bir güncelle
      if (mounted) {
        _thumbTimer = Timer(const Duration(seconds: 60), _autoCaptureThumbnail);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;
    _bidsPanelTop ??= topPad + 66;
    final live = !_connecting && _error == null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
        children: [
          // ── Video katmanı (tam ekran) — Transform.scale ile anlık zoom ──
          Positioned.fill(
            child: ClipRect(
              child: Transform.scale(
                scale: _currentZoom,
                child: LiveVideoPlayer(
                  track: _localVideoTrack,
                  cameraEnabled: _cameraEnabled,
                  repaintKey: _videoKey,
                ),
              ),
            ),
          ),

          // ── Bağlanıyor ──────────────────────────────────────────────────
          if (_connecting)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: kPrimary),
                      SizedBox(height: 16),
                      Text('Yayın başlatılıyor...',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Hata ────────────────────────────────────────────────────────
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
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                              context, '/home', (route) => false),
                          child: const Text('Geri Dön'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Üst bar: CANLI rozeti + izleyici + başlık + Bitir ──────────
          if (live)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: HostTopBar(
                topPad: topPad,
                viewerCount: _viewerCount,
                title: widget.title,
                micEnabled: _micEnabled,
                cameraEnabled: _cameraEnabled,
                onViewersTap: _showViewers,
                onToggleMic: _toggleMic,
                onToggleCamera: _toggleCamera,
                onSwitchCamera: _switchCamera,
                onEndStream: _endStream,
              ),
            ),

          // ── Alt panel: sohbet + açık artırma ───────────────────────────
          if (live)
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
                      key: _chatKey,
                      streamId: widget.streamToken.streamId,
                      onViewerCountChanged: (n) =>
                          setState(() => _viewerCount = n),
                      onUsernameTap: _showModSheet,
                      pinAtBottom: true,
                      pinDismissible: true,
                    ),
                    // ── Pin butonları ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Sabitle
                          GestureDetector(
                            onTap: _showPinInput,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0x88000000),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.amber.withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.push_pin_rounded,
                                      size: 13, color: Colors.amber),
                                  SizedBox(width: 4),
                                  Text('Sabitle',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Sabiti Kaldır
                          GestureDetector(
                            onTap: () =>
                                _chatKey.currentState?.sendHostPin(''),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0x55000000),
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: Colors.white24),
                              ),
                              child: const Text(
                                '✕ Kaldır',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Açık artırma şeridi (altta sabit)
                    AuctionPanel(
                      streamId: widget.streamToken.streamId,
                      isHost: true,
                      onBidAdded: _onBidAdded,
                      onAuctionReset: _onAuctionReset,
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),

          // ── Teklif Listesi — her zaman en üstte (alt panelin üstüne gelince tıklanabilir kalsın) ──
          if (live && _bidGroups.isNotEmpty)
            Positioned(
              top: _bidsPanelTop!,
              right: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Sadece toggle sürüklenebilir — scroll'la çakışmaz
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) {
                      setState(() {
                        _bidsPanelTop = (_bidsPanelTop! + d.delta.dy).clamp(
                          topPad + 50.0,
                          screenH - botPad - 260.0,
                        );
                      });
                    },
                    child: _BidsToggleTab(
                      isOpen: _bidsVisible,
                      count: _bidGroups.fold<int>(0, (s, g) => s + g.bids.length),
                      onToggle: () =>
                          setState(() => _bidsVisible = !_bidsVisible),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _bidsVisible ? 1.0 : 0.0,
                    child: SizedBox(
                      width: _bidsVisible ? 148 : 0,
                      height: _kBidsH,
                      child: _BidsOverlay(
                        groups: _bidGroups,
                        onUsernameTap: _showModSheet,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Pinch-to-zoom overlay — Listener kullanır, gesture arena'ya
          //    katılmaz; tek parmak tıklamalar alt widget'lara geçer. ────────
          Positioned.fill(
            child: _PinchZoomListener(
              getCurrentZoom: () => _currentZoom,
              maxZoom: _maxZoom,
              onZoomChanged: (z) => setState(() => _currentZoom = z),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ── Pinch-to-zoom overlay ─────────────────────────────────────────────────
//
// GestureDetector yerine Listener kullanılır; bu sayede ScaleGestureRecognizer
// gesture arena'ya girmez ve tek parmak tıklamalar alt widget'lara geçer.
// İki parmak algılandığında parmaklar arası mesafe değişimi ile zoom hesaplanır.
class _PinchZoomListener extends StatefulWidget {
  final double Function() getCurrentZoom;
  final double maxZoom;
  final void Function(double zoom) onZoomChanged;

  const _PinchZoomListener({
    required this.getCurrentZoom,
    required this.maxZoom,
    required this.onZoomChanged,
  });

  @override
  State<_PinchZoomListener> createState() => _PinchZoomListenerState();
}

class _PinchZoomListenerState extends State<_PinchZoomListener> {
  final Map<int, Offset> _pointers = {};
  // _startDistance, onDown'da DEĞİL ilk onMove'da set edilir.
  // Böylece parmakların "oturma" hareketi zoom'u etkilemez.
  double _startDistance = 0;
  double _startZoom     = 1.0;
  bool   _gestureActive = false; // iki parmak var mı?

  double _dist(Offset a, Offset b) => (a - b).distance;

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      // Başlangıç zoom'unu kaydet; mesafeyi ilk harekette alacağız.
      _startZoom     = widget.getCurrentZoom();
      _startDistance = 0; // lazy — ilk onMove'da set edilecek
      _gestureActive = true;
    } else if (_pointers.length > 2) {
      // Üçüncü parmak gelirse gesture'ı sıfırla (karışıklık önlenir).
      _gestureActive = false;
      _startDistance = 0;
    }
  }

  void _onMove(PointerMoveEvent e) {
    _pointers[e.pointer] = e.position;
    if (!_gestureActive || _pointers.length != 2) return;

    final pts  = _pointers.values.toList();
    final dist = _dist(pts[0], pts[1]);

    if (_startDistance == 0) {
      // İlk onMove: parmaklar oturdu, referans mesafeyi buradan al.
      _startDistance = dist;
      return;
    }

    final scale = dist / _startDistance;
    final zoom  = (_startZoom * scale).clamp(1.0, widget.maxZoom);
    widget.onZoomChanged(zoom);
  }

  void _onUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    _gestureActive = false;
    _startDistance = 0;
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _gestureActive = false;
    _startDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
    );
  }
}

// Sabit panel yüksekliği — 5 satır × 36px + başlık 44px
const double _kBidsH = 5 * 36.0 + 44; // 224px

// ── Veri modeli ────────────────────────────────────────────────────────────

class _BidGroup {
  final String? title;
  final List<({String bidder, double amount})> bids;
  _BidGroup({this.title}) : bids = [];
}

// ── Yardımcı widget'lar ────────────────────────────────────────────────────

class _BidsOverlay extends StatelessWidget {
  final List<_BidGroup> groups;
  final void Function(String username)? onUsernameTap;

  const _BidsOverlay({required this.groups, this.onUsernameTap});

  @override
  Widget build(BuildContext context) {
    final totalCount = groups.fold<int>(0, (s, g) => s + g.bids.length);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.48),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    const Text(
                      'TEKLİFLER',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$totalCount',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0x14FFFFFF)),
              // Gruplu scrollable liste
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 4),
                  physics: const BouncingScrollPhysics(),
                  // Her grup: 1 başlık + n teklif satırı
                  itemCount: groups.fold<int>(0, (s, g) => s + 1 + g.bids.length),
                  itemBuilder: (_, flatIndex) {
                    // flat index'i grup+satır'a çevir
                    int cursor = 0;
                    for (int gi = groups.length - 1; gi >= 0; gi--) {
                      final g = groups[gi];
                      if (flatIndex == cursor) {
                        // Grup başlığı
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: Colors.white.withOpacity(0.04),
                          child: Text(
                            g.title ?? 'Açık Artırma',
                            style: const TextStyle(
                              color: Color(0xFF06B6D4),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }
                      cursor++;
                      final bidIdx = flatIndex - cursor;
                      if (bidIdx >= 0 && bidIdx < g.bids.length) {
                        final bid = g.bids[bidIdx];
                        final isFirst = bidIdx == 0;
                        return GestureDetector(
                          onTap: onUsernameTap != null
                              ? () => onUsernameTap!(bid.bidder)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  child: Text(
                                    '#${bidIdx + 1}',
                                    style: TextStyle(
                                      color: isFirst
                                          ? const Color(0xFFFBBF24)
                                          : const Color(0xFF475569),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '@${bid.bidder}',
                                    style: TextStyle(
                                      color: usernameColor(bid.bidder),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      decoration: onUsernameTap != null
                                          ? TextDecoration.underline
                                          : null,
                                      decorationColor: usernameColor(bid.bidder)
                                          .withOpacity(0.5),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  fmtPrice(bid.amount),
                                  style: const TextStyle(
                                    color: Color(0xFF4ADE80),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      cursor += g.bids.length;
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BidsToggleTab extends StatelessWidget {
  final bool isOpen;
  final int count;
  final VoidCallback onToggle;

  const _BidsToggleTab({
    super.key,
    required this.isOpen,
    required this.count,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Toggle listenin solunda, sol kenarı yuvarlak; sağ kenarı listeye yapışık
    const radius = BorderRadius.horizontal(left: Radius.circular(12));
    final borderColor = Colors.white.withOpacity(isOpen ? 0.10 : 0.15);

    return GestureDetector(
      onTap: onToggle,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            width: isOpen ? 32 : 38,
            height: isOpen ? _kBidsH / 2 : null,
            padding: isOpen ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(isOpen ? 0.42 : 0.52),
              borderRadius: radius,
              border: Border(
                left: BorderSide(color: borderColor),
                top: BorderSide(color: borderColor),
                bottom: BorderSide(color: borderColor),
              ),
            ),
            child: isOpen ? _openChild() : _closedChild(),
          ),
        ),
      ),
    );
  }

  // Açıkken: liste yüksekliğini doldurur, ok ortada
  Widget _openChild() {
    return const Center(
      child: Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF64748B),
        size: 20,
      ),
    );
  }

  // Kapalıyken: sayı + dikey metin + ‹ (listeyi aç)
  Widget _closedChild() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Teklif sayısı rozeti — koyu gri
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFF334155),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Dikey "TEKLİFLER" yazısı — koyu
        RotatedBox(
          quarterTurns: 3,
          child: const Text(
            'TEKLİFLER',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ‹ oku — listeyi aç
        const Icon(
          Icons.chevron_left_rounded,
          color: const Color(0xFF64748B),
          size: 18,
        ),
      ],
    );
  }
}

// ── Moderasyon BottomSheet ──────────────────────────────────────────────────

class _ModerationSheet extends StatefulWidget {
  final int streamId;
  final String username;
  final bool isMuted;
  final bool isMod;
  final VoidCallback onMuted;
  final VoidCallback onUnmuted;
  final VoidCallback onPromoted;
  final VoidCallback onDemoted;

  const _ModerationSheet({
    required this.streamId,
    required this.username,
    required this.isMuted,
    required this.isMod,
    required this.onMuted,
    required this.onUnmuted,
    required this.onPromoted,
    required this.onDemoted,
  });

  @override
  State<_ModerationSheet> createState() => _ModerationSheetState();
}

class _ModerationSheetState extends State<_ModerationSheet> {
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
    } catch (e) {
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
          // Handle
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
          // Başlık
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
            _ModBtn(
              icon: '🔇',
              label: 'Sustur',
              color: const Color(0xFFD97706),
              loading: _loading,
              onTap: () => _act(
                () => ModerationService.mute(widget.streamId, widget.username),
                successMsg: '@${widget.username} susturuldu',
                onSuccess: () { widget.onMuted(); setState(() => _isMuted = true); },
              ),
            )
          else
            _ModBtn(
              icon: '🔊',
              label: 'Susturmayı Kaldır',
              color: const Color(0xFF16A34A),
              loading: _loading,
              onTap: () => _act(
                () => ModerationService.unmute(widget.streamId, widget.username),
                successMsg: 'Susturma kaldırıldı',
                onSuccess: () { widget.onUnmuted(); setState(() => _isMuted = false); },
              ),
            ),
          const SizedBox(height: 10),

          // Moderatör Yap / Moderatörlüğü Kaldır — XOR gösterim
          if (!widget.isMod)
            _ModBtn(
              icon: '⭐',
              label: 'Moderatör Yap',
              color: const Color(0xFFF59E0B),
              loading: _loading,
              onTap: () => _act(
                () => ModerationService.promoteUser(widget.streamId, widget.username),
                successMsg: '@${widget.username} moderatör yapıldı',
                onSuccess: () {
                  widget.onPromoted();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⭐ @${widget.username} moderatör yapıldı!'),
                      backgroundColor: const Color(0xFF16A34A),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
              ),
            )
          else
            _ModBtn(
              icon: '✖',
              label: 'Moderatörlüğü Kaldır',
              color: const Color(0xFF475569),
              loading: _loading,
              onTap: () => _act(
                () => ModerationService.demoteUser(widget.streamId, widget.username),
                successMsg: '@${widget.username} moderatörlükten alındı',
                onSuccess: () {
                  widget.onDemoted();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✖ @${widget.username} moderatörlükten alındı'),
                      backgroundColor: const Color(0xFF475569),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),

          // Yayından At
          _ModBtn(
            icon: '🚫',
            label: 'Yayından At',
            color: const Color(0xFFEF4444),
            loading: _loading,
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

          // Mesaj
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

class _ModBtn extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ModBtn({
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
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: Text('$icon  $label',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Pin giriş sheet'i — kendi state'inde ctrl tutar, parent rebuild'dan etkilenmez ──
class _PinInputSheet extends StatefulWidget {
  final void Function(String content) onPin;
  final VoidCallback onCancel;

  const _PinInputSheet({required this.onPin, required this.onCancel});

  @override
  State<_PinInputSheet> createState() => _PinInputSheetState();
}

class _PinInputSheetState extends State<_PinInputSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withOpacity(0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.push_pin_rounded, color: Colors.amber, size: 16),
                  SizedBox(width: 8),
                  Text('Sabitle',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                maxLines: 2,
                minLines: 2,
                maxLength: 120,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Tüm izleyicilere gösterilecek...',
                  hintStyle:
                      const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0F0F1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.amber.withOpacity(0.6)),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                  counterStyle:
                      const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('İptal',
                        style: TextStyle(color: Colors.white38)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final content = _ctrl.text.trim();
                      if (content.isEmpty) return;
                      widget.onPin(content);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.push_pin_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('Sabitle', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

