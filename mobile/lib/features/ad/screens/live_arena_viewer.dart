import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';

import '../../../core/models/ad.dart';
import '../../../core/providers/live_room_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../providers/ad_detail_provider.dart';
import '../../dashboard/screens/dashboard_screen.dart';

class LiveArenaViewer extends ConsumerStatefulWidget {
  final AdModel ad;
  const LiveArenaViewer({super.key, required this.ad});

  @override
  ConsumerState<LiveArenaViewer> createState() => _LiveArenaViewerState();
}

class _LiveArenaViewerState extends ConsumerState<LiveArenaViewer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _uiVisible = true;
  Timer? _inactivityTimer;
  VideoQuality _currentQuality = VideoQuality.HIGH;

  // Ephemeral Chat
  final List<_EphemeralMessage> _messages = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFocus = FocusNode();

  // Bid
  final _bidCtrl = TextEditingController();
  bool _bidLoading = false;

  final List<DateTime> _recentBids = [];
  bool _isHypeMode = false;
  Timer? _hypeTimer;

  // Animation for Pulse
  late AnimationController _pulseController;

  bool _isGuest = false;
  bool _isAuctionActive = false;

  @override
  void initState() {
    super.initState();
    // Hide system UI (FullScreen)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _resetInactivityTimer();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Connect to room
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(liveRoomProvider(widget.ad.id).notifier);
      await notifier.connect(false);
      
      // Listen to events after connection
      final room = ref.read(liveRoomProvider(widget.ad.id)).room;
      if (room != null) {
        room.events.listen(_onRoomEvent);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _hypeTimer?.cancel();
    _pulseController.dispose();
    _chatCtrl.dispose();
    _chatFocus.dispose();
    _bidCtrl.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _formatSenderName(String? name) {
    if (name == null || name.isEmpty) return 'Katılımcı';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0];
    
    final firstName = parts[0];
    final otherParts = parts.skip(1).map((p) => p.isNotEmpty ? '${p[0]}.' : '').where((s) => s.isNotEmpty).join(' ');
    return '$firstName $otherParts';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // In background, disable camera/audio? Viewer doesn't have it.
      // LiveKit adaptive stream pauses video when view is hidden.
    } else if (state == AppLifecycleState.resumed) {
      // Resume
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hareketsizlik modu aktif (AdaptiveStream).'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.black54,
          ),
        );
      }
    });
  }

  void _onInteraction() {
    _resetInactivityTimer();
  }

  void _handleDataChannelMessage(List<int> data, RemoteParticipant? p) {
    final message = String.fromCharCodes(data);
    
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic> && decoded['type'] != null) {
        final type = decoded['type'];
        if (type == 'INVITE_TO_STAGE') {
          _showInviteDialog();
          return;
        } else if (type == 'KICK_FROM_STAGE') {
          _handleKick();
          return;
        } else if (type == 'AUCTION_START') {
          setState(() => _isAuctionActive = true);
          _showSystemMessage('📣 MEZAT BAŞLADI!', Colors.green);
          return;
        } else if (type == 'AUCTION_END') {
          setState(() => _isAuctionActive = false);
          _showSystemMessage('📣 MEZAT DURDURULDU', Colors.orange);
          return;
        } else if (type == 'NEW_BID' || type == 'BID_ACCEPTED') {
          final amount = (decoded['amount'] as num).toDouble();
          
          // Auto-update bid controller for the user
          final nextBid = amount + (widget.ad.minBidStep);
          setState(() {
            _bidCtrl.text = nextBid.toStringAsFixed(0);
          });
          
          _recordBidVelocity();
          // Also refresh ad details to show the latest bid in header
          ref.invalidate(adDetailProvider(widget.ad.id));
        } else if (type == 'BID_REJECTED') {
           ref.invalidate(adDetailProvider(widget.ad.id));
        }
      }
    } catch (e) {
      // Fallback to normal text chat or skip
    }

    // Legacy text-based bid detection (optional, for backward compatibility)
    if (message.startsWith('🔥 Yeni Teklif:')) {
      final amountStr = message.replaceAll('🔥 Yeni Teklif: ₺', '').trim();
      final amount = double.tryParse(amountStr.replaceAll('.', '').replaceAll(',', '.'));
      if (amount != null) {
        final nextBid = amount + (widget.ad.minBidStep);
        setState(() {
          _bidCtrl.text = nextBid.toStringAsFixed(0);
        });
      }
      _recordBidVelocity();
    }

    setState(() {
      _messages.add(_EphemeralMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: message,
        senderName: _formatSenderName(p?.name),
        timestamp: DateTime.now(),
      ));
      if (_messages.length > 3) {
        _messages.removeAt(0);
      }
    });
    // Remove after 4 seconds
    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty) {
            _messages.removeAt(0);
          }
        });
      }
    });
  }

  void _showInviteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Sahneye Davet!'),
        content: const Text('Yayıncı sizi sahneye davet ediyor. Kameranız ve mikrofonunuz açılacak. Kabul ediyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Reddet', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final notifier = ref.read(liveRoomProvider(widget.ad.id).notifier);
              await notifier.disconnect();
              await notifier.connect(false, isGuest: true);
              setState(() => _isGuest = true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B4CC)),
            child: const Text('Kabul Et', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleKick() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sahneden alındınız.')));
    final notifier = ref.read(liveRoomProvider(widget.ad.id).notifier);
    await notifier.disconnect();
    await notifier.connect(false);
    setState(() => _isGuest = false);
  }

  void _recordBidVelocity() {
    final now = DateTime.now();
    _recentBids.add(now);
    
    // Remove bids older than 5 seconds
    _recentBids.removeWhere((t) => now.difference(t).inSeconds > 5);
    
    // Trigger Haptic
    Haptics.vibrate(HapticsType.heavy);

    if (_recentBids.length >= 3 && !_isHypeMode) {
      setState(() => _isHypeMode = true);
      _pulseController.repeat(reverse: true);
      
      _hypeTimer?.cancel();
      _hypeTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _isHypeMode = false);
          _pulseController.stop();
          _pulseController.value = 1.0;
        }
      });
    } else if (_isHypeMode) {
      // Extend hype
      _hypeTimer?.cancel();
      _hypeTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _isHypeMode = false);
          _pulseController.stop();
          _pulseController.value = 1.0;
        }
      });
    }
  }

  Future<void> _sendChatMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null) {
      await state.room!.localParticipant?.publishData(text.codeUnits);
      // For local message, we use the literal name if available or "Ben"
      final myName = state.room!.localParticipant?.name;
      _handleDataChannelMessage(text.codeUnits, null); 
      // Note: _handleDataChannelMessage will call _formatSenderName
    }
    _chatCtrl.clear();
    _chatFocus.unfocus();
  }



  Future<void> _placeBidSlide() async {
    final rawText = _bidCtrl.text
        .replaceAll('₺', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final amount = double.tryParse(rawText);
    
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen geçerli bir teklif girin')),
      );
      return;
    }

    setState(() => _bidLoading = true);
    await Haptics.vibrate(HapticsType.heavy);

    try {
      await ApiClient().post(Endpoints.bids, data: {
        'adId': widget.ad.id,
        'amount': amount,
      });
      _bidCtrl.clear();
      ref.invalidate(adDetailProvider(widget.ad.id));
      ref.invalidate(myBidsProvider);
      
      // Broadcast bid to data channel for others to see instantly
      final state = ref.read(liveRoomProvider(widget.ad.id));
      if (state.room != null) {
        state.room!.localParticipant?.publishData('🔥 Yeni Teklif: ₺$amount'.codeUnits);
        _handleDataChannelMessage('🔥 Yeni Teklif: ₺$amount'.codeUnits, null);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teklifiniz verildi! 🎉'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teklif verilemedi.')),
      );
    } finally {
      if (mounted) setState(() => _bidLoading = false);
    }
  }

  void _showSystemMessage(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Center(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white))),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.7, left: 50, right: 50),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showAdDetailsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(widget.ad.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (widget.ad.startingBid != null)
                Text('Başlangıç Fiyatı: ₺${widget.ad.startingBid}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00B4CC))),
              const SizedBox(height: 24),
              const Text('Açıklama',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(widget.ad.description,
                  style: const TextStyle(fontSize: 16, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Auto-pop when room is disconnected or closed by host
    ref.listen(liveRoomProvider(widget.ad.id), (previous, next) {
      if (previous?.room != null && (next.room == null) && !next.isConnecting) {
        if (mounted) context.pop();
      }
    });

    final updatedAdAsync = ref.watch(adDetailProvider(widget.ad.id));
    final currentAd = updatedAdAsync.value ?? widget.ad;
    
    final roomState = ref.watch(liveRoomProvider(widget.ad.id));
    final room = roomState.room;

    VideoTrack? hostTrack;
    VideoTrack? guestTrack;

    if (room != null) {
      final allRemote = room.remoteParticipants.values.toList();
      for (var p in allRemote) {
        VideoTrack? t;
        for (var pub in p.videoTrackPublications) {
          if (pub.track != null) {
            t = pub.track as VideoTrack;
            break;
          }
        }
        if (t != null) {
          if (p.identity == widget.ad.userId) {
            hostTrack = t; // Found the host
          } else {
            guestTrack = t; // Found another guest
          }
        }
      }
      
      // Fallback host track
      if (hostTrack == null && allRemote.isNotEmpty) {
        for (var pub in allRemote.first.videoTrackPublications) {
           if (pub.track != null) { hostTrack = pub.track as VideoTrack; break; }
        }
      }

      if (_isGuest && room.localParticipant != null) {
        for (var pub in room.localParticipant!.videoTrackPublications) {
          if (pub.track != null) {
            guestTrack = pub.track as VideoTrack;
            break;
          }
        }
      }
    }

    return GestureDetector(
      onTap: _onInteraction,
      onPanUpdate: (details) {
        _onInteraction();
        if (details.delta.dx > 10) {
          if (_uiVisible) setState(() => _uiVisible = false);
        } else if (details.delta.dx < -10) {
          if (!_uiVisible) setState(() => _uiVisible = true);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. Video Player
            if (roomState.isConnecting)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Color(0xFF1a1a1a)],
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00B4CC)),
                      SizedBox(height: 24),
                      Text('Arena\'ya Katılınıyor...', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              )
            else if (hostTrack != null)
              SizedBox.expand(
                child: VideoTrackRenderer(hostTrack, fit: VideoViewFit.cover),
              )
            else
              const Center(child: Text('Yayın bekleniyor...', style: TextStyle(color: Colors.white54))),

            if (guestTrack != null)
              Positioned(
                top: 200,
                right: 16,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.5), width: 2), color: Colors.black),
                    child: VideoTrackRenderer(guestTrack, fit: VideoViewFit.cover),
                  ),
                ),
              ),

            // 2. Premium Overlay (UI)
            AnimatedOpacity(
              opacity: _uiVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: SafeArea(
                child: IgnorePointer(
                  ignoring: !_uiVisible,
                  child: Column(
                    children: [
                      // Header Dashboard
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                                  child: Row(
                                    children: [
                                      CircleAvatar(radius: 5, backgroundColor: Colors.redAccent, child: Container(width: 3, height: 3, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                                      const SizedBox(width: 8),
                                      const Text('CANLI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: () => context.pop()),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('GÜNCEL TEKLİF', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                            const SizedBox(height: 4),
                                            Text('₺${(currentAd.highestBidAmount ?? currentAd.startingBid ?? 0).toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF22c55e), fontSize: 20, fontWeight: FontWeight.w900)),
                                          ],
                                        ),
                                      ),
                                      if (currentAd.buyItNowPrice != null) ...[
                                        Container(width: 1, height: 40, color: Colors.white12, margin: const EdgeInsets.all(12)),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text('HEMEN AL', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                            const SizedBox(height: 4),
                                            Text('₺${currentAd.buyItNowPrice?.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 20, fontWeight: FontWeight.w900)),
                                          ],
                                        ),
                                      ]
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Chat Flow
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: ShaderMask(
                                shaderCallback: (bounds) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.white, Colors.white], stops: [0.0, 0.4, 1.0]).createShader(bounds),
                                blendMode: BlendMode.dstIn,
                                child: SizedBox(
                                  height: 150,
                                  child: ListView.builder(
                                    reverse: true,
                                    itemCount: _messages.length,
                                    itemBuilder: (context, index) {
                                      final msg = _messages[_messages.length - 1 - index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                          child: RichText(text: TextSpan(children: [TextSpan(text: '${msg.senderName}: ', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white70, fontSize: 13)), TextSpan(text: msg.text, style: const TextStyle(color: Colors.white, fontSize: 13))])),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              children: [
                                _CircularControlButton(icon: Icons.info_outline, onPressed: _showAdDetailsSheet),
                                const SizedBox(height: 12),
                                _CircularControlButton(icon: Icons.camera_alt, onPressed: () {
                                  // Request to join stage logic
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sahneye katılma isteği gönderildi.')));
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Bidding & Chat Column
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            if (_isAuctionActive) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [50, 100, 250, 500, 1000].map((inc) => Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ActionChip(
                                        label: Text('+₺$inc', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        backgroundColor: Colors.white10,
                                        side: const BorderSide(color: Colors.white24),
                                        labelStyle: const TextStyle(color: Colors.white),
                                        onPressed: () {
                                          _bidCtrl.text = inc.toString();
                                          _placeBidSlide();
                                        },
                                      ),
                                    )).toList(),
                                  ),
                                ),
                              ),
                            ],
                            
                            ClipRRect(
                              borderRadius: BorderRadius.circular(35),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(35), border: Border.all(color: Colors.white12)),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: _bidCtrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                                          decoration: InputDecoration(hintText: 'Pey...', hintStyle: TextStyle(color: Colors.white38, fontSize: 15), border: InputBorder.none),
                                        ),
                                      ),
                                      if (_isAuctionActive)
                                        ElevatedButton(
                                          onPressed: _placeBidSlide,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF00B4CC), 
                                            foregroundColor: Colors.white, 
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), 
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                                          ),
                                          child: const Text('PEY VER', style: TextStyle(fontWeight: FontWeight.w900)),
                                        ),
                                      if (currentAd.buyItNowPrice != null) ...[
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: () async {
                                            // Handle Buy Now
                                            try {
                                              await ApiClient().post('/api/ads/${widget.ad.id}/buy-it-now');
                                              if (mounted) context.pop();
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFFFD700), 
                                            foregroundColor: Colors.black, 
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), 
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                                          ),
                                          child: Text('HEMEN AL: ₺${currentAd.buyItNowPrice?.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                                        ),
                                      ]
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(25)),
                              child: Row(
                                children: [
                                  Expanded(child: TextField(controller: _chatCtrl, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 14), decoration: const InputDecoration(hintText: 'Mesaj gönder...', hintStyle: TextStyle(color: Colors.black54), border: InputBorder.none), onSubmitted: (_) => _sendChatMessage())),
                                  IconButton(icon: const Icon(Icons.send, color: Color(0xFF00B4CC), size: 20), onPressed: _sendChatMessage),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is DataReceivedEvent) {
      _handleDataChannelMessage(event.data, event.participant);
    }
  }
}

class _CircularControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CircularControlButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: Colors.black26, shape: BoxShape.circle, border: Border.all(color: Colors.white12)),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

class _EphemeralMessage {
  final String id;
  final String text;
  final String senderName;
  final DateTime timestamp;

  _EphemeralMessage({required this.id, required this.text, required this.senderName, required this.timestamp});
}
