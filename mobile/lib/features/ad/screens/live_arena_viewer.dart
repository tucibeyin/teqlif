import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:slider_button/slider_button.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';
import 'dart:async';

import 'dart:convert';

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
  final _bidFormatter = CurrencyTextInputFormatter.currency(
    locale: 'tr_TR',
    symbol: '',
    decimalDigits: 0,
  );
  bool _bidLoading = false;

  final List<DateTime> _recentBids = [];
  bool _isHypeMode = false;
  Timer? _hypeTimer;

  // Animation for Pulse
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetInactivityTimer();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
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
    super.dispose();
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
        if (decoded['type'] == 'INVITE_TO_STAGE') {
          _showInviteDialog();
          return;
        } else if (decoded['type'] == 'KICK_FROM_STAGE') {
          _handleKick();
          return;
        }
      }
    } catch (e) {
      // Fallback to normal text chat
    }

    // Check if it's a bid broadcast to calculate velocity
    if (message.startsWith('🔥 Yeni Teklif:')) {
      _recordBidVelocity();
    }

    setState(() {
      _messages.add(_EphemeralMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: message,
        senderName: p?.name ?? 'Biri',
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
      _handleDataChannelMessage(text.codeUnits, null); // Add my own
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
      if (previous?.room != null && next.room == null && !next.isConnecting) {
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
      
      // If no definitive host recognized but there is a track, fallback
      if (hostTrack == null && allRemote.isNotEmpty) {
        for (var pub in allRemote.first.videoTrackPublications) {
           if (pub.track != null) { hostTrack = pub.track as VideoTrack; break; }
        }
      }

      // If I am the guest, my local video is the guest track
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
          // Swipe Right: Ghost Screen
          if (_uiVisible) setState(() => _uiVisible = false);
        } else if (details.delta.dx < -10) {
          // Swipe Left: Show UI
          if (!_uiVisible) setState(() => _uiVisible = true);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. Video Player & Loading State
            if (roomState.isConnecting)
              Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 24),
                      const Text('Arena\'ya Katılınıyor...', 
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                      const SizedBox(height: 32),
                      TextButton(
                        onPressed: () {
                           Navigator.pop(context);
                        }, 
                        child: const Text('İptal Et ve Geri Dön', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              )
            else if (hostTrack != null)
              SizedBox.expand(
                child: VideoTrackRenderer(
                  hostTrack,
                  fit: VideoViewFit.cover,
                ),
              )
            else
              Center(
                child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                      const Icon(Icons.videocam_off, color: Colors.white24, size: 64),
                      const SizedBox(height: 16),
                      const Text('Yayın bekleniyor...', style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Geri Dön'),
                      ),
                   ],
                )
              ),

            if (guestTrack != null)
              Positioned(
                top: 80,
                right: 16,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black,
                    ),
                    child: VideoTrackRenderer(
                      guestTrack,
                      fit: VideoViewFit.cover,
                    ),
                  ),
                ),
              ),

            // 2. Ghost Screen Overlay (UI)
            AnimatedOpacity(
              opacity: _uiVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: SafeArea(
                child: IgnorePointer(
                  ignoring: !_uiVisible,
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.circle,
                                      color: Colors.white, size: 10),
                                  const SizedBox(width: 6),
                                  const Text('CANLI MEZAT',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white, size: 28),
                              onPressed: () {
                                ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
                                context.pop();
                              },
                            )
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Ephemeral Chat & Info Drawer Button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Chat flow
                            Expanded(
                              child: ShaderMask(
                                shaderCallback: (Rect bounds) {
                                  return LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.white,
                                      Colors.white,
                                    ],
                                    stops: const [0.0, 0.4, 1.0],
                                  ).createShader(bounds);
                                },
                                blendMode: BlendMode.dstIn,
                                child: SizedBox(
                                  height: 200,
                                  child: ListView.builder(
                                    reverse: true,
                                    itemCount: _messages.length,
                                    itemBuilder: (context, index) {
                                      // Because it's reversed, 0 is the newest, but we append to end. 
                                      // Wait, we append to end. So reversed means we should read from end.
                                      final msg = _messages[_messages.length - 1 - index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${msg.senderName}:',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                msg.text,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            // Details Button
                            IconButton(
                              onPressed: _showAdDetailsSheet,
                              icon: const Icon(Icons.info_outline, color: Colors.white, size: 32),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Bid input and Chat input
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Column(
                          children: [
                            // Chat Input
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _chatCtrl,
                                      focusNode: _chatFocus,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: const InputDecoration(
                                        hintText: 'Mesaj yaz...',
                                        hintStyle: TextStyle(color: Colors.white54),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                                      ),
                                      onSubmitted: (_) => _sendChatMessage(),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.send, color: Color(0xFF00B4CC)),
                                    onPressed: _sendChatMessage,
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Bid Section
                            if (roomState.isFrozen)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Yayıncı bağlantısı bekleniyor...',
                                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              )
                            else
                              ScaleTransition(
                                scale: _pulseAnimation,
                                child: Container(
                                  decoration: _isHypeMode ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(26),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.redAccent.withOpacity(0.6),
                                        blurRadius: 15,
                                        spreadRadius: 2,
                                      )
                                    ]
                                  ) : null,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(26),
                                          ),
                                          child: TextField(
                                            controller: _bidCtrl,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            inputFormatters: [_bidFormatter],
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                            textAlign: TextAlign.center,
                                            decoration: const InputDecoration(
                                              hintText: 'Miktar (₺)',
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 16),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child: _bidLoading 
                                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00B4CC)))
                                          : SliderButton(
                                              action: () async {
                                                await _placeBidSlide();
                                                return true; // reset
                                              },
                                              label: const Text(
                                                "Kaydırarak Teklif Ver",
                                                style: TextStyle(
                                                    color: Colors.white, 
                                                    fontWeight: FontWeight.bold, 
                                                    fontSize: 14),
                                              ),
                                              icon: const Center(
                                                  child: Icon(Icons.gavel,
                                                      color: Color(0xFF00B4CC),
                                                      size: 24)),
                                              width: 200,
                                              radius: 26,
                                              buttonColor: Colors.white,
                                              backgroundColor: _isHypeMode ? Colors.redAccent : const Color(0xFF00B4CC),
                                              highlightedColor: Colors.white,
                                              baseColor: Colors.white,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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

class _EphemeralMessage {
  final String id;
  final String text;
  final String senderName;
  final DateTime timestamp;

  _EphemeralMessage({
    required this.id,
    required this.text,
    required this.senderName,
    required this.timestamp,
  });
}
