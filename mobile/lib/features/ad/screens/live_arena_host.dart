import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../../core/models/ad.dart';
import '../../../core/providers/live_room_provider.dart';
import '../../../core/api/api_client.dart';

class LiveArenaHost extends ConsumerStatefulWidget {
  final AdModel ad;
  const LiveArenaHost({super.key, required this.ad});

  @override
  ConsumerState<LiveArenaHost> createState() => _LiveArenaHostState();
}

class _LiveArenaHostState extends ConsumerState<LiveArenaHost> {
  // Ephemeral Chat
  final List<_EphemeralMessage> _messages = [];
  final List<_LiveBid> _bids = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFocus = FocusNode();

  bool _isCameraEnabled = true;
  bool _isMicEnabled = true;
  bool _isAuctionActive = false;
  int _unreadBids = 0;

  @override
  void initState() {
    super.initState();
    // Hide system UI (FullScreen)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Connect to room as Host
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Request permissions first
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isGranted && micStatus.isGranted) {
        final notifier = ref.read(liveRoomProvider(widget.ad.id).notifier);
        await notifier.connect(true);
        
        final room = ref.read(liveRoomProvider(widget.ad.id)).room;
        if (room != null) {
          room.events.listen(_onRoomEvent);
          
          // Signal backend that we are LIVE
          try {
            await ApiClient().post('/api/ads/${widget.ad.id}/live', data: {
              'isLive': true,
              'liveKitRoomId': widget.ad.id,
            });
          } catch (e) {
            debugPrint('Failed to set isLive to true: $e');
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yayın başlatmak için kamera ve mikrofon izni gereklidir.')),
          );
          context.pop();
        }
      }
    });
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
  void dispose() {
    _chatCtrl.dispose();
    _chatFocus.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _formatPrice(double amount) {
    return NumberFormat.decimalPattern('tr').format(amount);
  }

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

  void _handleDataChannelMessage(List<int> data, RemoteParticipant? p, {String? customName}) {
    String message;
    try {
      message = utf8.decode(data);
    } catch (e) {
      debugPrint('UTF-8 Decode error: $e');
      message = String.fromCharCodes(data);
    }
    
    // Check if it's a bid
    if (message.startsWith('🔥 Yeni Teklif:')) {
      final amountStr = message.replaceAll('🔥 Yeni Teklif: ₺', '').trim();
      final amount = double.tryParse(amountStr.replaceAll('.', '').replaceAll(',', '.'));
      
      setState(() {
        _unreadBids++;
        final bidId = 'bid-${DateTime.now().millisecondsSinceEpoch}'; // Default ID
        _bids.insert(0, _LiveBid(
          id: bidId,
          amount: amount ?? 0,
          userLabel: _formatSenderName(customName ?? p?.name),
          timestamp: DateTime.now(),
        ));
        if (_bids.length > 50) _bids.removeLast();
      });
      return;
    }

    // Try parsing as JSON for structured events (BID_ACCEPTED, BID_REJECTED)
    try {
      final dataObj = jsonDecode(message);
      if (dataObj['type'] == 'BID_ACCEPTED') {
        final amount = (dataObj['amount'] as num).toDouble();
        final bidId = dataObj['bidId']?.toString();
        setState(() {
          // If we already have this bid, update it, otherwise add
          final existingIndex = _bids.indexWhere((b) => b.id == bidId);
          if (existingIndex != -1) {
            _bids[existingIndex] = _LiveBid(
              id: bidId!,
              amount: amount,
              userLabel: dataObj['bidderName'] ?? _bids[existingIndex].userLabel,
              timestamp: _bids[existingIndex].timestamp,
              isAccepted: true,
            );
          } else {
            _bids.insert(0, _LiveBid(
              id: bidId ?? 'bid-${DateTime.now().millisecondsSinceEpoch}',
              amount: amount,
              userLabel: _formatSenderName(dataObj['bidderName']),
              timestamp: DateTime.now(),
              isAccepted: true,
            ));
          }
        });
        return;
      } else if (dataObj['type'] == 'CHAT') {
         final chatText = dataObj['text']?.toString() ?? '';
         final chatSender = dataObj['senderName']?.toString();
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
      } else if (dataObj['type'] == 'NEW_BID') {
        final amount = (dataObj['amount'] as num).toDouble();
        final bidId = dataObj['bidId']?.toString();
        setState(() {
          _unreadBids++;
          _bids.insert(0, _LiveBid(
            id: bidId ?? 'bid-${DateTime.now().millisecondsSinceEpoch}',
            amount: amount,
            userLabel: _formatSenderName(dataObj['bidderName']),
            timestamp: DateTime.now(),
          ));
          if (_bids.length > 50) _bids.removeLast();
        });
        return;
      } else if (dataObj['type'] == 'BID_REJECTED') {
         final bidId = dataObj['bidId']?.toString();
         setState(() {
           _bids.removeWhere((b) => b.id == bidId);
         });
         return;
      }
    } catch (_) {}

    final senderName = customName ?? p?.name;
    
    setState(() {
      _messages.add(_EphemeralMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: message,
        senderName: _formatSenderName(senderName),
        timestamp: DateTime.now(),
      ));
      if (_messages.length > 5) {
        _messages.removeAt(0);
      }
    });
    _resetMessageTimer();
  }

  Future<void> _sendChatMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null) {
      final name = state.room!.localParticipant?.name;
      final payload = jsonEncode({
        'type': 'CHAT',
        'text': text,
        'senderName': name,
      });
      await state.room!.localParticipant?.publishData(utf8.encode(payload));
      _handleDataChannelMessage(utf8.encode(payload), null, customName: name);
    }
    _chatCtrl.clear();
    _chatFocus.unfocus();
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is DataReceivedEvent) {
      _handleDataChannelMessage(event.data, event.participant);
    }
  }

  Future<void> _toggleAuction() async {
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room == null) return;

    setState(() => _isAuctionActive = !_isAuctionActive);
    
    final signal = jsonEncode({
      'type': _isAuctionActive ? 'AUCTION_START' : 'AUCTION_END',
      'adId': widget.ad.id,
    });

    try {
      await state.room!.localParticipant?.publishData(signal.codeUnits);
      _showSystemMessage(
        _isAuctionActive ? '📣 MEZAT BAŞLATILDI!' : '📣 MEZAT DURDURULDU',
        _isAuctionActive ? Colors.green : Colors.orange
      );
      final signalName = state.room!.localParticipant?.name;
      final signalPayload = jsonEncode({
        'type': 'CHAT',
        'text': _isAuctionActive ? '📣 Mezat Başlatıldı!' : '📣 Mezat Durduruldu!',
        'senderName': signalName,
      });
      _handleDataChannelMessage(utf8.encode(signalPayload), null, customName: signalName);
    } catch (e) {
      debugPrint('Signal error: $e');
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

  Future<void> _endLiveStream() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yayını Bitir'),
        content: const Text('Canlı mezatı bitirmek istediğinize emin misiniz? Yayın kapandıktan sonra teklifler onay için hesabınıza düşecektir.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yayını Bitir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 1. Tell backend that we are no longer live
      // This ensures the isLive flag is cleared even if webhook takes a moment
      try {
        await ApiClient().post('/api/ads/${widget.ad.id}/live', data: {
          'isLive': false,
        });
      } catch (e) {
        debugPrint('Failed to update isLive status: $e');
      }

      // 2. Disconnect from LiveKit.
      await ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
      if (mounted) context.pop(); // Go back to normal ad detail
    }
  }

  Future<void> _kickGuest(String targetUserId) async {
    try {
      await ApiClient().post('/api/livekit/signal', data: {
        'adId': widget.ad.id,
        'targetUserId': targetUserId,
        'signal': 'KICK_FROM_STAGE',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konuk sahneden alındı.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
      }
    }
  }

  Future<void> _cancelBid(String bidId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teklifi İptal Et'),
        content: const Text('Bu teklifi reddetmek veya iptal etmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('İptal Et', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient().patch('/api/bids/$bidId/cancel');
        setState(() {
          _bids.removeWhere((b) => b.id == bidId);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İptal işlemi başarısız.')));
        }
      }
    }
  }

  void _showBidsBottomSheet() {
    setState(() => _unreadBids = 0);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInternalState) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.gavel, color: Color(0xFF00B4CC)),
                      const SizedBox(width: 12),
                      const Text('Gelen Teklifler', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: _bids.isEmpty 
                    ? const Center(child: Text('Henüz teklif gelmedi.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        controller: controller,
                        itemCount: _bids.length,
                        itemBuilder: (ctx, i) {
                          final bid = _bids[i];
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(bid.userLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text('₺${_formatPrice(bid.amount)}', 
                                        style: const TextStyle(fontSize: 18, color: Color(0xFF00B4CC), fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    // Accept Bid logic
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Teklifi Onayla'),
                                        content: Text('₺${_formatPrice(bid.amount)} tutarındaki teklifi kabul edip satışı ilanını sonlandırmak istiyor musunuz?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, Sat')),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      try {
                                        // This is a placeholder for actual bid acceptance API
                                        // Usually it requires bidId, but since we are handling dynamic bids from data channel
                                        // we might need to find the latest valid bid id for this ad
                                        await ApiClient().post('/api/ads/${widget.ad.id}/sell', data: {
                                          'amount': bid.amount,
                                          'buyerLabel': bid.userLabel,
                                        });
                                        if (mounted) {
                                          Navigator.pop(context); // Close sheet
                                          _endLiveStream(); // Offer to end live
                                        }
                                      } catch (e) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Satış işlemi başarısız.')));
                                      }
                                    }
                                  },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Onayla ve Sat'),
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
        ),
      ),
    );
  }

  Future<void> _acceptBidFromDashboard() async {
    if (_bids.isEmpty) return;
    final latestBid = _bids.first;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Satışı Onayla'),
        content: Text('₺${_formatPrice(latestBid.amount)} tutarındaki son teklifi kabul edip satışı ilanını sonlandırmak istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Onayla ve Sat', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient().post('/api/ads/${widget.ad.id}/sell', data: {
          'amount': latestBid.amount,
          'buyerLabel': latestBid.userLabel,
        });
        if (mounted) _endLiveStream();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Satış işlemi başarısız.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-pop when room is disconnected or closed by host
    ref.listen(liveRoomProvider(widget.ad.id), (previous, next) {
      if (previous?.room != null && next.room == null && !next.isConnecting) {
        if (mounted) context.pop();
      }
    });

    final roomState = ref.watch(liveRoomProvider(widget.ad.id));
    final room = roomState.room;

    VideoTrack? localVideoTrack;
    VideoTrack? guestTrack;
    String? guestIdentity;

    if (room != null) {
      if (room.localParticipant != null) {
        for (var pub in room.localParticipant!.videoTrackPublications) {
          if (pub.track != null) {
            localVideoTrack = pub.track as VideoTrack?;
            break;
          }
        }
      }

      // Guest logic
      if (room.remoteParticipants.isNotEmpty) {
        final firstGuest = room.remoteParticipants.values.first;
        guestIdentity = firstGuest.identity;
        
        for (var pub in firstGuest.videoTrackPublications) {
          if (pub.track != null) {
            guestTrack = pub.track as VideoTrack?;
            break;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview & Loading State (Same as before but with better fit)
          if (roomState.isConnecting || (room == null && roomState.error == null))
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Color(0xFF1a1a1a)],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.red),
                    const SizedBox(height: 24),
                    const Text('Arena Hazırlanıyor...', 
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Bağlantı kuruluyor, lütfen bekleyin.', 
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            )
          else if (localVideoTrack != null && _isCameraEnabled)
            SizedBox.expand(
              child: VideoTrackRenderer(
                localVideoTrack,
                fit: VideoViewFit.cover,
              ),
            )
          else
            const Center(child: Icon(Icons.videocam_off, size: 80, color: Colors.white54)),

          // 2. Premium Dashboard Header (NEW)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 8)],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sensors, color: Colors.white, size: 12),
                              const SizedBox(width: 4),
                              const Text('CANLI',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                          onPressed: _endLiveStream,
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Auction Stats Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('GÜNCEL TEKLİF', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _bids.isNotEmpty ? '₺${_formatPrice(_bids.first.amount)}' : 'Henüz Teklif Yok',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _isAuctionActive ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: _isAuctionActive ? Colors.green.withOpacity(0.5) : Colors.orange.withOpacity(0.5)),
                                      ),
                                      child: Text(
                                        _isAuctionActive ? 'MEZAT AKTİF' : 'MEZAT DURDURULDU',
                                        style: TextStyle(
                                          color: _isAuctionActive ? Colors.greenAccent : Colors.orangeAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5
                                        ),
                                      ),
                                    ),
                                    if (_bids.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(_bids.first.userLabel, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              ),
                              if (widget.ad.buyItNowPrice != null) ...[
                                Container(width: 1, height: 40, color: Colors.white.withOpacity(0.1), margin: const EdgeInsets.symmetric(horizontal: 16)),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('HEMEN AL', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                    const SizedBox(height: 2),
                                    Text('₺${_formatPrice(widget.ad.buyItNowPrice!)}', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_bids.isNotEmpty && _isAuctionActive)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: OutlinedButton(
                                onPressed: () => _cancelBid(_bids.first.id),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.redAccent.withOpacity(0.1),
                                  side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                                  foregroundColor: Colors.redAccent,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                                child: const Text('REDDET', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 7,
                              child: ElevatedButton.icon(
                                onPressed: _acceptBidFromDashboard,
                                icon: const Icon(Icons.check_circle_outline, color: Colors.black, size: 18),
                                label: const Text('ONAYLA VE SAT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.greenAccent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  elevation: 10,
                                  shadowColor: Colors.greenAccent.withOpacity(0.5),
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

          if (guestTrack != null)
            Positioned(
              top: 220,
              right: 16,
              width: 100,
              height: 140,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.black,
                      ),
                      child: VideoTrackRenderer(guestTrack, fit: VideoViewFit.cover),
                    ),
                  ),
                  if (guestIdentity != null)
                    Positioned(
                      top: -8,
                      right: -8,
                      child: GestureDetector(
                        onTap: () => _kickGuest(guestIdentity!),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // 3. UI Overlay - Chat & Controls
          SafeArea(
            child: Column(
              children: [
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
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.white, Colors.white],
                              stops: [0.0, 0.4, 1.0],
                            ).createShader(bounds);
                          },
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
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${msg.senderName}:', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13)),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      // Controls
                      Column(
                        children: [
                          _CircularControlButton(
                            icon: Icons.gavel,
                            onPressed: _showBidsBottomSheet,
                            badge: _unreadBids > 0 ? '$_unreadBids' : null,
                          ),
                          const SizedBox(height: 12),
                          _CircularControlButton(
                            icon: _isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                            onPressed: () async {
                              final p = room?.localParticipant;
                              if (p != null) {
                                await p.setCameraEnabled(!_isCameraEnabled);
                                setState(() => _isCameraEnabled = !_isCameraEnabled);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          _CircularControlButton(
                            icon: _isMicEnabled ? Icons.mic : Icons.mic_off,
                            onPressed: () async {
                              final p = room?.localParticipant;
                              if (p != null) {
                                await p.setMicrophoneEnabled(!_isMicEnabled);
                                setState(() => _isMicEnabled = !_isMicEnabled);
                              }
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                ),

                // Auction & Chat Controls
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (widget.ad.isAuction)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: _toggleAuction,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: _isAuctionActive ? Colors.redAccent : Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30),
                                boxShadow: _isAuctionActive ? [BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 15)] : null,
                              ),
                              child: Icon(_isAuctionActive ? Icons.stop : Icons.play_arrow, color: Colors.white, size: 30),
                            ),
                          ),
                        ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _chatCtrl,
                                      focusNode: _chatFocus,
                                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                                      decoration: const InputDecoration(
                                        hintText: 'Sohbete dahil ol...',
                                        hintStyle: TextStyle(color: Colors.black54, fontSize: 13),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                          ),
                        ),
                      ),
                    ],
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

class _LiveBid {
  final String id;
  final double amount;
  final String userLabel;
  final DateTime timestamp;

  final bool isAccepted;

  _LiveBid({
    required this.id,
    required this.amount,
    required this.userLabel,
    required this.timestamp,
    this.isAccepted = false,
  });
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
