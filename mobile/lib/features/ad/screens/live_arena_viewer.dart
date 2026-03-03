import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/models/ad.dart';
import '../../../core/providers/live_room_provider.dart';
import '../../../core/providers/auth_provider.dart';
import 'dart:math';
import '../widgets/floating_reactions.dart';
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

  // Reactions State
  final List<FloatingReaction> _reactions = [];
  int _lastReactionTime = 0;
  bool _isMuted = false;

  void _addReaction(String emoji) {
    if (!mounted) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(1000).toString();
    setState(() {
      _reactions.add(FloatingReaction(id: id, emoji: emoji));
      if (_reactions.length > 20) _reactions.removeAt(0);
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() {
        _reactions.removeWhere((r) => r.id == id);
      });
    });
  }

  void _sendReaction(String emoji) {
    final state = ref.read(liveRoomProvider(widget.ad.id));
    final room = state.room;
    final isDisconnected = room?.connectionState.name == 'disconnected' || (room == null && !state.isConnecting);
    if (isDisconnected) return;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastReactionTime < 500) return;
    _lastReactionTime = now;

    if (room?.localParticipant == null) return;
    
    final payload = jsonEncode({
      'type': 'REACTION',
      'emoji': emoji,
    });
    
    try {
      room!.localParticipant!.publishData(utf8.encode(payload));
      _addReaction(emoji);
    } catch (e) {
      debugPrint('Reaction send error: $e');
    }
  }

  void _requestStage() {
    final state = ref.read(liveRoomProvider(widget.ad.id));
    final room = state.room;
    if (room?.localParticipant == null) return;
    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanıcı girişi gerekli.')));
      return;
    }

    final payload = jsonEncode({
      'type': 'REQUEST_STAGE',
      'userId': currentUser.id,
      'userName': currentUser.name,
    });

    try {
      room!.localParticipant!.publishData(utf8.encode(payload));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sahneye katılma isteği gönderildi!', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green),
      );
    } catch (e) {
      debugPrint('Stage request error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Hide system UI (FullScreen)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
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
    WakelockPlus.disable();
    ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
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

  String _formatPrice(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  void _resetMessageTimer() {
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

  void _handleDataChannelMessage(List<int> data, RemoteParticipant? p) {
    String message;
    try {
      message = utf8.decode(data);
    } catch (e) {
      debugPrint('UTF-8 Decode error: $e');
      message = String.fromCharCodes(data);
    }
    
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic> && decoded['type'] != null) {
        final type = decoded['type'];
        if (type == 'ROOM_CLOSED') {
          // Instead of popping out instantly, cleanly display disconnected state.
          ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
          return;
        } else if (type == 'INVITE_TO_STAGE') {
          final targetIdentity = decoded['targetIdentity'];
          final currentUser = ref.read(authProvider).user;
          if (currentUser != null && targetIdentity == currentUser.id) {
            _showInviteDialog();
          }
          return;
        } else if (type == 'KICK_FROM_STAGE') {
          final targetIdentity = decoded['targetIdentity'];
          final currentUser = ref.read(authProvider).user;
          if (currentUser != null && targetIdentity == currentUser.id) {
            _handleKick();
          }
          return;
        } else if (type == 'AUCTION_START') {
          setState(() => _isAuctionActive = true);
          _showSystemMessage('📣 AÇIK ARTTIRMA BAŞLADI!', Colors.green);
          return;
        } else if (type == 'AUCTION_END') {
          setState(() => _isAuctionActive = false);
          _showSystemMessage('📣 AÇIK ARTTIRMA DURDURULDU', Colors.orange);
          return;
        } else if (type == 'REACTION') {
          _addReaction(decoded['emoji']?.toString() ?? '❤️');
          return;
        } else if (type == 'CHAT') {
           final chatText = decoded['text']?.toString() ?? '';
           final chatSender = decoded['senderName']?.toString();
           setState(() {
             _messages.add(_EphemeralMessage(
               id: DateTime.now().millisecondsSinceEpoch.toString(),
               text: chatText,
               senderName: _formatSenderName(chatSender),
               timestamp: DateTime.now(),
             ));
             if (_messages.length > 5) _messages.removeAt(0);
           });
           _resetMessageTimer();
           return;
        } else if (type == 'NEW_BID' || type == 'BID_ACCEPTED') {
          final amount = (decoded['amount'] as num).toDouble();
          
          // Auto-update bid controller for the user
          final nextBid = amount + (widget.ad.minBidStep);
          setState(() {
            _bidCtrl.text = _formatPrice(nextBid);
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

    // Removed legacy text-based bid detection to enforce JSON payloads

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
    _resetMessageTimer();
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

  Future<void> _handleKick() async {
    if (!mounted) return;
    
    // First notify the user
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sahneden çıkarıldınız.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );

    // Turn off local tracks if they are on (just in case)
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null && state.room!.localParticipant != null) {
      await state.room!.localParticipant!.setCameraEnabled(false);
      await state.room!.localParticipant!.setMicrophoneEnabled(false);
    }
    
    // Switch state back to viewer only
    final wasGuest = _isGuest;
    setState(() {
      _isGuest = false;
    });

    if (wasGuest) {
      // Best approach to downgrade permissions is to reconnect with a standard token
      // Because we can't tell the server to demote us from the client side without an API.
      // Easiest reliable fallback: Disconnect and Reconnect.
      try {
        await ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
        // Give it a tiny delay to ensure proper cleanup
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          ref.read(liveRoomProvider(widget.ad.id).notifier).connect(false);
        }
      } catch (e) {
        debugPrint('Error restoring viewer state: $e');
      }
    }
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
    final currentUser = ref.read(authProvider).user;
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null) {
      final name = state.room!.localParticipant?.name;
      final payload = jsonEncode({
        'type': 'CHAT',
        'text': text,
        'senderName': name,
        'senderId': currentUser?.id,
      });
      await state.room!.localParticipant?.publishData(utf8.encode(payload));
      _handleDataChannelMessage(utf8.encode(payload), null); 
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
        const SnackBar(content: Text('Lütfen geçerli bir teqlif girin')),
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
      
      // DO NOT broadcast manually via CHAT. The Backend API handles publishing NO_BID via webhook/LiveKit API
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teqlifiniz verildi! 🎉'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teqlif verilemedi.')),
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
                Text('Başlangıç Fiyatı: ₺${_formatPrice(widget.ad.startingBid!)}',
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

  Widget _buildTopHeader(AdModel currentAd) {
    // Show current auction price if active, otherwise show ad price
    final displayPrice = _isAuctionActive 
      ? (currentAd.highestBidAmount ?? currentAd.startingBid ?? 0)
      : (currentAd.isAuction ? (currentAd.highestBidAmount ?? currentAd.startingBid ?? 0) : (currentAd.buyItNowPrice ?? 0));
    
    final label = _isAuctionActive ? 'GÜNCEL TEKLİF: ' : (currentAd.isAuction ? 'BAŞLANGIÇ: ' : 'FİYAT: ');

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 4, 
                              backgroundColor: Colors.redAccent, 
                              child: Container(width: 2, height: 2, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                            ),
                            const SizedBox(width: 8),
                            const Text('CANLI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Price Info Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                        Text(_formatPrice(displayPrice), style: const TextStyle(color: Color(0xFF00B4CC), fontWeight: FontWeight.w900, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickBidButtons(AdModel currentAd) {
    if (!_isAuctionActive) return const SizedBox.shrink();
    
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [100, 200, 500, 1000].map((amount) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              final currentPrice = currentAd.highestBidAmount 
                                   ?? currentAd.startingBid 
                                   ?? (currentAd.isFixedPrice ? currentAd.price : 0);
              _bidCtrl.text = _formatPrice(currentPrice + amount);
              _placeBidSlide();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00B4CC).withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text('+$amount ₺', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildSidebar(bool isDisconnected) {
    return Positioned(
      right: 16,
      top: 0,
      bottom: 120, // Avoid overlapping with bottom console
      child: Center(
        child: SingleChildScrollView(
          clipBehavior: Clip.none,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CircularControlButton(icon: Icons.info_outline, onPressed: _showAdDetailsSheet),
              const SizedBox(height: 16),
              _CircularControlButton(
                icon: _isMuted ? Icons.volume_off : Icons.volume_up, 
                onPressed: () {
                  setState(() => _isMuted = !_isMuted);
                }
              ),
              const SizedBox(height: 16),
              _CircularControlButton(icon: Icons.mic_none, onPressed: _requestStage),
              const SizedBox(height: 16),
              _CircularControlButton(icon: Icons.cameraswitch_outlined, onPressed: () {}), // Ghosted
              const SizedBox(height: 24),
              ReactionButtons(onReact: _sendReaction, isVertical: true),
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

    final adAsync = ref.watch(adDetailProvider(widget.ad.id));
    final currentAd = adAsync.value ?? widget.ad;
    
    final roomState = ref.watch(liveRoomProvider(widget.ad.id));
    final room = roomState.room;
    final isDisconnected = room?.connectionState.name == 'disconnected' || (room == null && !roomState.isConnecting);

    // Sync isAuctionActive from currentAd (initial state or polling updates)
    if (currentAd.isAuctionActive != _isAuctionActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isAuctionActive = currentAd.isAuctionActive);
      });
    }

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
            // 1. Video Player & Error State
            if (isDisconnected)
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 64),
                    const SizedBox(height: 16),
                    const Text('Yayın Sona Erdi', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Yayıncı canlı yayını kapattı.', style: TextStyle(color: Colors.white54, fontSize: 16)),
                  ],
                ),
              )
            else if (roomState.isConnecting)
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
                child: VideoTrackRenderer(
                  hostTrack, 
                  fit: VideoViewFit.contain, // Ensure full video visibility
                ),
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

            // 2. Premium Overlay (UI) with Smooth Swipe Animation
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              left: _uiVisible ? 0 : MediaQuery.of(context).size.width,
              right: _uiVisible ? 0 : -MediaQuery.of(context).size.width,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_uiVisible,
                child: !isDisconnected ? SafeArea(
                  child: OrientationBuilder(
                    builder: (context, orientation) {
                      if (orientation == Orientation.portrait) {
                        return _buildPortraitLayout(currentAd, isDisconnected);
                      } else {
                        return _buildLandscapeLayout(currentAd, isDisconnected);
                      }
                    },
                  ),
                )
              : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(AdModel currentAd, bool isDisconnected) {
    return Stack(
      children: [
        // Header (Status & Price)
        _buildTopHeader(currentAd),

        // Sidebar Actions & Reactions
        _buildSidebar(isDisconnected),

        // Floating Reactions Animation Layer
        Positioned.fill(child: IgnorePointer(child: FloatingReactionsOverlay(reactions: _reactions))),

        // Interaction Layer (Bottom)
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Chat Flow (Floating Left)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8, right: 80), // Keep space from sidebar
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.white, Colors.white],
                    stops: [0.0, 0.3, 1.0], 
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: SizedBox(
                    height: 140, // Reduced slightly to accommodate quick bids
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[_messages.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(text: '${msg.senderName}: ', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white70, fontSize: 13)),
                                TextSpan(text: msg.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                              ]
                            )
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Quick Bid Buttons (Above Console)
              _buildQuickBidButtons(currentAd),
              
              // Bottom Console
              _buildBottomInteractionConsole(currentAd, isDisconnected),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomInteractionConsole(AdModel currentAd, bool isDisconnected) {
    // Primary Action Button (Teqlif Ver or Hemen Al)
    Widget buildPrimaryAction() {
      // Prioritize Bid if auction is active, regardless of ad type
      if (currentAd.isAuction || _isAuctionActive) {
        return GestureDetector(
          onTap: (isDisconnected || !_isAuctionActive) ? null : _placeBidSlide,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: _isAuctionActive 
                ? const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFB81D24)])
                : LinearGradient(colors: [Colors.grey.shade800, Colors.grey.shade900]),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
              boxShadow: _isAuctionActive ? [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 15)] : null,
            ),
            child: Center(
              child: Icon(
                _isAuctionActive ? Icons.gavel : Icons.hourglass_empty, 
                color: _isAuctionActive ? Colors.white : Colors.white38, 
                size: 26
              )
            ),
          ),
        );
      } else {
        // Fixed Price "Hemen Al" (Only if no auction active)
        return GestureDetector(
          onTap: isDisconnected ? null : () async {
            try {
              await ApiClient().post('/api/ads/${widget.ad.id}/buy-it-now');
              if (mounted) context.pop();
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
            }
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
              boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.3), blurRadius: 10)],
            ),
            child: const Center(
              child: Icon(Icons.shopping_cart, color: Colors.black, size: 24),
            ),
          ),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: buildPrimaryAction(),
          ),
          
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatCtrl,
                          enabled: !isDisconnected,
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            hintText: 'Mesaj gönder...',
                            hintStyle: TextStyle(color: Colors.black54, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onSubmitted: (_) => _sendChatMessage(),
                        ),
                      ),
                      if (_isAuctionActive)
                        IconButton(
                          icon: const Icon(Icons.edit_note, color: Color(0xFF00B4CC)),
                          onPressed: () => _showBidInputSheet(currentAd),
                        ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Color(0xFF00B4CC)),
                        onPressed: isDisconnected ? null : _sendChatMessage,
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(AdModel currentAd, bool isDisconnected) {
    return Stack(
      children: [
        // Header (Status & Price)
        _buildTopHeader(currentAd),

        // Sidebar Actions & Reactions
        _buildSidebar(isDisconnected),

        // Bottom Chat & Quick Bids (Floating Left)
        Positioned(
          left: 16,
          bottom: 16,
          width: 300,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Bids
                if (_isAuctionActive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [100, 200, 500, 1000].map((amount) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              final currentPrice = currentAd.highestBidAmount ?? currentAd.startingBid ?? 0;
                              _bidCtrl.text = _formatPrice(currentPrice + amount);
                              _placeBidSlide();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFF00B4CC).withOpacity(0.4)),
                              ),
                              child: Center(
                                child: Text('+$amount ₺', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                  ),

                // Chat
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.white, Colors.white], stops: [0.0, 0.4, 1.0]).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: SizedBox(
                    height: 100,
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[_messages.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: RichText(text: TextSpan(children: [TextSpan(text: '${msg.senderName}: ', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white70, fontSize: 12)), TextSpan(text: msg.text, style: const TextStyle(color: Colors.white, fontSize: 12))])),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Floating Reaction Animation Layer
        Positioned.fill(child: IgnorePointer(child: FloatingReactionsOverlay(reactions: _reactions))),
      ],
    );
  }

  void _showBidInputSheet(AdModel currentAd) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: Color(0xFF131722), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              const Text('TEQLİF VER', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 8),
              const Text('Teklif vermek istediğiniz tutarı girin.', style: TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
                child: TextField(
                  controller: _bidCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(border: InputBorder.none, prefixText: '₺ ', prefixStyle: TextStyle(color: Color(0xFF00B4CC))),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [50, 100, 250, 500].map((inc) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      onPressed: () {
                        final raw = _bidCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                        final val = (double.tryParse(raw) ?? (currentAd.highestBidAmount ?? currentAd.startingBid ?? 0)) + inc;
                        _bidCtrl.text = _formatPrice(val);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text('+$inc'),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _placeBidSlide();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B4CC), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: const Text('TEKLİFİ ONAYLA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 12),
            ],
          ),
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
  final String? badge;

  const _CircularControlButton({required this.icon, required this.onPressed, this.badge});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
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
