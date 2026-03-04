import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:confetti/confetti.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/models/ad.dart';
import '../../../core/providers/live_room_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../providers/ad_detail_provider.dart';
import 'dart:math';
import '../widgets/floating_reactions.dart';
import '../../../core/api/api_client.dart';

class LiveArenaHost extends ConsumerStatefulWidget {
  final AdModel ad;
  const LiveArenaHost({super.key, required this.ad});

  @override
  ConsumerState<LiveArenaHost> createState() => _LiveArenaHostState();
}

class _StageRequest {
  final String id;
  final String name;
  _StageRequest(this.id, this.name);
}

class _LiveArenaHostState extends ConsumerState<LiveArenaHost>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Ephemeral Chat
  final List<_EphemeralMessage> _messages = [];
  final List<_LiveBid> _bids = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFocus = FocusNode();

  bool _isCameraEnabled = true;
  bool _isMicEnabled = true;
  bool _isAuctionActive = false;
  int _unreadBids = 0;

  bool _isFinalizing = false;

  // Stage Requests
  final List<_StageRequest> _stageRequests = [];

  // Countdown Gamification
  int _countdown = 0;
  Timer? _countdownTimer;
  late AnimationController _pulseController;

  // Reactions State
  final List<FloatingReaction> _reactions = [];
  int _lastReactionTime = 0;

  // Draggable PiP (Guest Window)
  Offset? _pipOffset;

  void _addReaction(String emoji) {
    if (!mounted) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
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

  // Sale Finalized Overlay State
  String? _finalizedWinnerName;
  double? _finalizedAmount;
  bool _showFinalizationOverlay = false;

  // 🎊 AUCTION_SOLD — permanent sold state
  bool _isSold = false;
  String? _soldWinnerName;
  double? _soldFinalPrice;
  late ConfettiController _confettiController;

  void _sendReaction(String emoji) {
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastReactionTime < 500) return;
    _lastReactionTime = now;

    final payload = jsonEncode({
      'type': 'REACTION',
      'emoji': emoji,
    });

    try {
      state.room!.localParticipant!.publishData(utf8.encode(payload));
      _addReaction(emoji);
    } catch (e) {
      debugPrint('Reaction send error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Hide system UI (FullScreen)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );

    // Connect to room as Host
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _isAuctionActive = widget.ad.isAuctionActive; // Initial state from DB

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
            const SnackBar(
                content: Text(
                    'Yayın başlatmak için kamera ve mikrofon izni gereklidir.')),
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
    final otherParts = parts
        .skip(1)
        .map((p) => p.isNotEmpty ? '${p[0]}.' : '')
        .where((s) => s.isNotEmpty)
        .join(' ');
    return '$firstName $otherParts';
  }

  @override
  void deactivate() {
    // 🛡️ Schedule after build frame — avoids ZonedGuarded 'modify during build' crash
    final adId = widget.ad.id;
    final container = ProviderScope.containerOf(context, listen: false);
    Future.microtask(() {
      try {
        container.read(liveRoomProvider(adId).notifier).disconnect();
        container.invalidate(adDetailProvider(adId));
      } catch (_) {}
    });
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    // ⛔ NO ref.read()/ref.invalidate() here — moved to deactivate()
    _pulseController.dispose();
    _confettiController.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused) {
      // User left the app, disconnect from LiveKit
      ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
    }
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

  void _handleDataChannelMessage(List<int> data, RemoteParticipant? p,
      {String? customName}) {
    String message;
    try {
      message = utf8.decode(data);
    } catch (e) {
      debugPrint('UTF-8 Decode error: $e');
      message = String.fromCharCodes(data);
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
              userLabel:
                  dataObj['bidderName'] ?? _bids[existingIndex].userLabel,
              timestamp: _bids[existingIndex].timestamp,
              isAccepted: true,
              userId: dataObj['bidderId']?.toString() ??
                  _bids[existingIndex].userId,
            );
          } else {
            _bids.insert(
                0,
                _LiveBid(
                  id: bidId ?? 'bid-${DateTime.now().millisecondsSinceEpoch}',
                  amount: amount,
                  userLabel: _formatSenderName(dataObj['bidderName']),
                  timestamp: DateTime.now(),
                  isAccepted: true,
                  userId: dataObj['bidderId']?.toString(),
                ));
          }
        });
        return;
      } else if (dataObj['type'] == 'CHAT') {
        final chatText = dataObj['text']?.toString() ?? '';
        final chatSender = dataObj['senderName']?.toString();
        final senderId = dataObj['senderId']?.toString();
        setState(() {
          _messages.add(_EphemeralMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: chatText,
            senderName: _formatSenderName(chatSender),
            timestamp: DateTime.now(),
            senderId: senderId,
          ));
          if (_messages.length > 5) _messages.removeAt(0);
        });
        _resetMessageTimer();
        return;
      } else if (dataObj['type'] == 'NEW_BID') {
        final amount = (dataObj['amount'] as num).toDouble();
        final bidId = dataObj['bidId']?.toString();
        final bidderId = dataObj['bidderId']?.toString();
        setState(() {
          _unreadBids++;
          _bids.insert(
              0,
              _LiveBid(
                id: bidId ?? 'bid-${DateTime.now().millisecondsSinceEpoch}',
                amount: amount,
                userLabel: _formatSenderName(dataObj['bidderName']),
                timestamp: DateTime.now(),
                userId: bidderId,
              ));
          if (_bids.length > 50) _bids.removeLast();
        });
        return;
      } else if (dataObj['type'] == 'SALE_FINALIZED') {
        final winnerName = dataObj['winnerName']?.toString();
        final amount = dataObj['amount'] != null
            ? (dataObj['amount'] as num).toDouble()
            : null;
        _showFinalizationOverlayAlert(winnerName, amount);
        return;
      } else if (dataObj['type'] == 'AUCTION_SOLD') {
        // 🎊 Host sees the SATILDI overlay too (reflects the finalized sale)
        final winner = dataObj['winnerName']?.toString() ?? 'Katılımcı';
        final price = dataObj['price'] != null
            ? (dataObj['price'] as num).toDouble()
            : 0.0;
        if (mounted) {
          setState(() {
            _isSold = true;
            _soldWinnerName = winner;
            _soldFinalPrice = price;
            _isAuctionActive = false;
          });
          _confettiController.play();
        }
        return;
      } else if (dataObj['type'] == 'BID_REJECTED') {
        final bidId = dataObj['bidId']?.toString();
        setState(() {
          _bids.removeWhere((b) => b.id == bidId);
        });
        return;
      } else if (dataObj['type'] == 'COUNTDOWN') {
        final count = dataObj['value'] as int;
        setState(() {
          _countdown = count;
          if (count > 0 && count <= 10) {
            _pulseController.repeat(reverse: true);
          } else {
            _pulseController.stop();
            _pulseController.value = 1.0;
          }
        });
        return;
      } else if (dataObj['type'] == 'REACTION') {
        _addReaction(dataObj['emoji']?.toString() ?? '❤️');
        return;
      } else if (dataObj['type'] == 'REQUEST_STAGE') {
        final userId = dataObj['userId']?.toString();
        final userName = dataObj['userName']?.toString() ?? 'Katılımcı';
        if (userId != null && !_stageRequests.any((r) => r.id == userId)) {
          setState(() {
            _stageRequests.add(_StageRequest(userId, userName));
          });
        }
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
      final identity = state.room!.localParticipant?.identity;
      final name = state.room!.localParticipant?.name;
      final payload = jsonEncode({
        'type': 'CHAT',
        'text': text,
        'senderName': name,
        'senderId': identity,
      });
      await state.room!.localParticipant?.publishData(utf8.encode(payload));
      _handleDataChannelMessage(utf8.encode(payload), null, customName: name);
    }
    _chatCtrl.clear();
    _chatFocus.unfocus();
  }

  void _onRoomEvent(RoomEvent event) {
    if (event is TrackSubscribedEvent ||
        event is TrackUnsubscribedEvent ||
        event is ParticipantConnectedEvent ||
        event is ParticipantDisconnectedEvent ||
        event is TrackMutedEvent ||
        event is TrackUnmutedEvent) {
      if (mounted) setState(() {});
    }
    if (event is DataReceivedEvent) {
      _handleDataChannelMessage(event.data, event.participant);
    }
  }

  void _inviteToStage(String userId) async {
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null) {
      final payload = jsonEncode({
        'type': 'INVITE_TO_STAGE',
        'targetIdentity': userId,
      });
      await state.room!.localParticipant?.publishData(utf8.encode(payload));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sahneye davet gönderildi!'),
            backgroundColor: Colors.blue),
      );
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

      // Persist state to DB
      await ApiClient().post('/api/ads/${widget.ad.id}/live', data: {
        'isAuctionActive': _isAuctionActive,
      });

      _showSystemMessage(
          _isAuctionActive
              ? '📣 AÇIK ARTTIRMA BAŞLATILDI!'
              : '📣 AÇIK ARTTIRMA DURDURULDU',
          _isAuctionActive ? Colors.green : Colors.orange);
      final signalName = state.room!.localParticipant?.name;
      final signalPayload = jsonEncode({
        'type': 'CHAT',
        'text': _isAuctionActive
            ? '📣 Açık Arttırma Başlatıldı!'
            : '📣 Açık Arttırma Durduruldu!',
        'senderName': signalName,
      });
      _handleDataChannelMessage(utf8.encode(signalPayload), null,
          customName: signalName);
    } catch (e) {
      debugPrint('Signal error: $e');
    }
  }

  Future<void> _resetAuction() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Açık Arttırmayı Sıfırla'),
        content: const Text('Tüm teklifleri iptal edip başlangıç fiyatına dönmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sıfırla', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final state = ref.read(liveRoomProvider(widget.ad.id));
    try {
      final res = await ApiClient().post('/api/ads/${widget.ad.id}/auction/reset', data: {});
      if (res.statusCode == 200 || res.statusCode == 201) {
        final payload = jsonEncode({'type': 'AUCTION_RESET'});
        if (state.room != null) {
          await state.room!.localParticipant?.publishData(utf8.encode(payload));
        }

        setState(() {
            _bids.clear();
            _unreadBids = 0;
        });
        _showSystemMessage('📣 AÇIK ARTTIRMA SIFIRLANDI!', Colors.orange);
      }
    } catch (e) {
      debugPrint('Reset auction error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sıfırlama başarısız oldu.')),
      );
    }
  }

  void _startCountdown() {
    if (_countdownTimer != null && _countdownTimer!.isActive) return;

    setState(() {
      _countdown = 10;
      _pulseController.repeat(reverse: true);
    });

    _broadcastCountdown(_countdown);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_countdown > 0) {
          _countdown--;
          _broadcastCountdown(_countdown);
        } else {
          timer.cancel();
          _pulseController.stop();
          _pulseController.value = 1.0;
        }
      });
    });
  }

  void _broadcastCountdown(int value) async {
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null) {
      final payload = jsonEncode({
        'type': 'COUNTDOWN',
        'value': value,
      });
      await state.room!.localParticipant?.publishData(utf8.encode(payload));
    }
  }

  void _showSystemMessage(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Center(
            child: Text(text,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: Colors.white))),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.7,
            left: 50,
            right: 50),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _closeLiveStreamSilently() async {
    if (mounted) setState(() => _isFinalizing = true);

    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null) {
      final payload = jsonEncode({'type': 'ROOM_CLOSED'});
      await state.room!.localParticipant?.publishData(utf8.encode(payload));
    }

    await ApiClient()
        .post('/api/ads/${widget.ad.id}/live', data: {'isLive': false});
    await ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _endLiveStream() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yayını Bitir'),
        content: const Text(
            'Canlı yayını sonlandırmak ve odadan çıkmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Evet, Bitir',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) setState(() => _isFinalizing = true);

      final state = ref.read(liveRoomProvider(widget.ad.id));
      if (state.room != null) {
        final payload = jsonEncode({'type': 'ROOM_CLOSED'});
        await state.room!.localParticipant?.publishData(utf8.encode(payload));
      }

      await ApiClient()
          .post('/api/ads/${widget.ad.id}/live', data: {'isLive': false});
      await ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
      if (mounted) context.pop();
    }
  }

  void _kickGuest(String userId) async {
    final state = ref.read(liveRoomProvider(widget.ad.id));
    if (state.room != null) {
      final payload = jsonEncode({
        'type': 'KICK_FROM_STAGE',
        'targetIdentity': userId,
      });
      await state.room!.localParticipant?.publishData(utf8.encode(payload));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Davetli çıkarıldı.'),
            backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _cancelBid(String bidId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('teqlifi İptal Et'),
        content: const Text(
            'Bu teqlifi reddetmek veya iptal etmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hayır')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('İptal Et', style: TextStyle(color: Colors.red))),
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
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('İptal işlemi başarısız.')));
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
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.gavel, color: Color(0xFF00B4CC)),
                      const SizedBox(width: 12),
                      const Text('Gelen teqlifler',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: _bids.isEmpty
                      ? const Center(
                          child: Text('Henüz teqlif gelmedi.',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          controller: controller,
                          itemCount: _bids.length,
                          itemBuilder: (ctx, i) {
                            final bid = _bids[i];
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(bid.userLabel,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                            overflow: TextOverflow.ellipsis),
                                        Text('₺${_formatPrice(bid.amount)}',
                                            style: const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF00B4CC),
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () async {
                                              // Accept Bid logic
                                              final confirmed =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text(
                                                      'teqlifi Onayla'),
                                                  content: Text(
                                                      '₺${_formatPrice(bid.amount)} tutarındaki teqlifi kabul edip satışı ilanını sonlandırmak istiyor musunuz?'),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, false),
                                                        child: const Text(
                                                            'Hayır')),
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, true),
                                                        child: const Text(
                                                            'Evet, Sat')),
                                                  ],
                                                ),
                                              );
                                              if (confirmed == true) {
                                                setState(
                                                    () => _isFinalizing = true);
                                                try {
                                                  // 1. Accept the bid
                                                  final acceptRes =
                                                      await ApiClient().patch(
                                                          '/api/bids/${bid.id}/accept');
                                                  if (acceptRes.statusCode ==
                                                      200) {
                                                    // 2. Finalize the sale
                                                    final finalizeRes =
                                                        await ApiClient().post(
                                                            '/api/bids/${bid.id}/finalize');
                                                    if (finalizeRes
                                                            .statusCode ==
                                                        200) {
                                                      if (mounted) {
                                                        setState(() =>
                                                            _isFinalizing =
                                                                false);
                                                        Navigator.pop(
                                                            context); // Close sheet
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                                const SnackBar(
                                                          content: Text(
                                                              'Satış başarıyla tamamlandı! İlan "Satıldı" olarak işaretlendi.',
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold)),
                                                          backgroundColor:
                                                              Colors.green,
                                                          duration: Duration(
                                                              seconds: 4),
                                                        ));
                                                        _closeLiveStreamSilently(); // End live quietly after sale
                                                      }
                                                      return;
                                                    }
                                                  }
                                                  throw Exception(
                                                      'Satış işlemleri sırasında bir hata oluştu');
                                                } catch (e) {
                                                  if (mounted) {
                                                    setState(() =>
                                                        _isFinalizing = false);
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                            const SnackBar(
                                                                content: Text(
                                                                    'Satış işlemi başarısız oldu. Lütfen tekrar deneyin.')));
                                                  }
                                                }
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                            ),
                                            child: const Text('Sat',
                                                style: TextStyle(fontSize: 12)),
                                          ),
                                        ),
                                        if (bid.userId != null)
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.mic,
                                                color: Colors.blueAccent,
                                                size: 22),
                                            onPressed: () =>
                                                _inviteToStage(bid.userId!),
                                          ),
                                      ],
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
        content: Text(
            '₺${_formatPrice(latestBid.amount)} tutarındaki son teqlifi kabul edip satışı ilanını sonlandırmak istiyor musunuz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Onayla ve Sat',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isFinalizing = true);
      try {
        // 1. Accept the bid
        final acceptRes =
            await ApiClient().patch('/api/bids/${latestBid.id}/accept');
        if (acceptRes.statusCode == 200) {
          // 2. Finalize the sale
          final finalizeRes =
              await ApiClient().post('/api/bids/${latestBid.id}/finalize');
          if (finalizeRes.statusCode == 200) {
            if (mounted) {
              setState(() {
                _isFinalizing = false;
                _isAuctionActive = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Satış başarıyla tamamlandı! İlan "Satıldı" olarak işaretlendi.',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 4),
              ));

              // Inform participants via DataChannel that the sale is finalized and auction is over
              final room = ref.read(liveRoomProvider(widget.ad.id)).room;
              final endSignal = jsonEncode({'type': 'AUCTION_END'});
              room?.localParticipant?.publishData(endSignal.codeUnits);

              final saleSignal = jsonEncode({
                'type': 'SALE_FINALIZED',
                'winnerName': latestBid.userLabel,
                'amount': latestBid.amount,
              });
              room?.localParticipant?.publishData(saleSignal.codeUnits);
            }
            return;
          }
        }
        throw Exception('API Hatası');
      } catch (e) {
        if (mounted) {
          setState(() => _isFinalizing = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Satış işlemi başarısız oldu. Lütfen tekrar deneyin.')));
        }
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
          OrientationBuilder(
            builder: (context, orientation) {
              if (orientation == Orientation.portrait) {
                return _buildPortraitLayout(roomState, room, localVideoTrack,
                    guestTrack, guestIdentity);
              } else {
                return _buildLandscapeLayout(roomState, room, localVideoTrack,
                    guestTrack, guestIdentity);
              }
            },
          ),
          _buildFinalizationOverlay(),

          // 🎊 AUCTION_SOLD — Permanent SATILDI Full-Screen Overlay (Host)
          if (_isSold)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.black.withOpacity(0.72),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConfettiWidget(
                            confettiController: _confettiController,
                            blastDirectionality: BlastDirectionality.explosive,
                            shouldLoop: false,
                            numberOfParticles: 60,
                            maxBlastForce: 55,
                            minBlastForce: 25,
                            emissionFrequency: 0.06,
                            colors: const [
                              Colors.amber, Color(0xFFFFA500),
                              Color(0xFF00B4CC), Colors.white,
                              Color(0xFF22c55e), Color(0xFFFF6B35),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('🏆', style: TextStyle(fontSize: 72)),
                        const SizedBox(height: 12),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFFD700)],
                          ).createShader(bounds),
                          child: const Text(
                            'SATILDI!',
                            style: TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 4,
                              shadows: [
                                Shadow(color: Color(0xFFFF8C00), blurRadius: 30),
                                Shadow(color: Color(0xFFFFD700), blurRadius: 50),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'KAZANAN',
                          style: TextStyle(
                            color: Colors.white54, fontSize: 12,
                            fontWeight: FontWeight.w800, letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _soldWinnerName ?? 'Katılımcı',
                          style: const TextStyle(
                            color: Colors.white, fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10b981), Color(0xFF059669)],
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x5010b981), blurRadius: 24, spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            '₺${_soldFinalPrice?.toStringAsFixed(0) ?? '-'}',
                            style: const TextStyle(
                              color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Bu ürün ${_soldWinnerName ?? 'Katılımcı'} adlı kullanıcıya '
                            '₺${_soldFinalPrice?.toStringAsFixed(0) ?? '-'}\'ye satılmıştır.',
                            style: const TextStyle(
                              color: Colors.white60, fontSize: 14, height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () {
                            // Explicit cleanup — disconnect first, then delay nav so invalidate fires cleanly
                            final router = GoRouter.of(context);
                            ref.read(liveRoomProvider(widget.ad.id).notifier).disconnect();
                            Future.delayed(const Duration(milliseconds: 100), () {
                              try { ref.invalidate(adDetailProvider(widget.ad.id)); } catch (_) {}
                              router.go('/home');
                            });
                          },
                          icon: const Icon(Icons.home_outlined, color: Colors.white),
                          label: const Text(
                            'Ana Sayfaya Dön',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.15),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                            shape: const StadiumBorder(
                              side: BorderSide(color: Colors.white54, width: 1.5),
                            ),
                            elevation: 0,
                          ),
                        ),
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

  Widget _buildLoadingOrCamera(
      dynamic roomState, Room? room, VideoTrack? localVideoTrack) {
    if (roomState.isConnecting || (room == null && roomState.error == null)) {
      return Container(
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
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Bağlantı kuruluyor, lütfen bekleyin.',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
      );
    } else if (localVideoTrack != null && _isCameraEnabled) {
      return SizedBox.expand(
        child: VideoTrackRenderer(
          localVideoTrack,
          fit: VideoViewFit.cover,
        ),
      );
    } else {
      return const Center(
          child: Icon(Icons.videocam_off, size: 80, color: Colors.white54));
    }
  }

  Widget _buildGuestTrackView(VideoTrack? guestTrack, String? guestIdentity) {
    if (guestTrack == null) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: Colors.white.withOpacity(0.5), width: 2),
              borderRadius: BorderRadius.circular(16),
              color: Colors.black,
            ),
            child: guestTrack.muted
                ? const Center(child: Icon(Icons.videocam_off, color: Colors.white54))
                : VideoTrackRenderer(guestTrack, fit: VideoViewFit.cover),
          ),
        ),
        if (guestIdentity != null)
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: () => _kickGuest(guestIdentity),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopDashboard(bool isLandscape) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.redAccent.withOpacity(0.3),
                          blurRadius: 8)
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sensors, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      const Text('CANLI',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Viewer Count Pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.visibility_outlined,
                          color: Colors.white, size: 12),
                      const SizedBox(width: 6),
                      Text(
                        '${ref.read(liveRoomProvider(widget.ad.id)).viewerCount}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
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
              padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 12 : 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: isLandscape
                  ? _buildLandscapeStatsInner()
                  : _buildPortraitStatsInner(),
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
                      side:
                          BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('REDDET',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 7,
                  child: ElevatedButton.icon(
                    onPressed: _acceptBidFromDashboard,
                    icon: const Icon(Icons.check_circle_outline,
                        color: Colors.black, size: 18),
                    label: const Text('ONAYLA VE SAT',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      elevation: 10,
                      shadowColor: Colors.greenAccent.withOpacity(0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPortraitStatsInner() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GÜNCEL TEQLİF',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(
                _bids.isNotEmpty
                    ? '₺${_formatPrice(_bids.first.amount)}'
                    : 'Henüz teqlif Yok',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _isAuctionActive
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: _isAuctionActive
                          ? Colors.green.withOpacity(0.5)
                          : Colors.orange.withOpacity(0.5)),
                ),
                child: Text(
                  _isAuctionActive
                      ? 'AÇIK ARTTIRMA AKTİF'
                      : 'AÇIK ARTTIRMA DURDURULDU',
                  style: TextStyle(
                      color: _isAuctionActive
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5),
                ),
              ),
              if (_bids.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Text(_bids.first.userLabel,
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    if (_bids.first.userId != null)
                      GestureDetector(
                        onTap: () => _inviteToStage(_bids.first.userId!),
                        child: Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.blue.withOpacity(0.5))),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mic,
                                  color: Colors.blueAccent, size: 10),
                              SizedBox(width: 2),
                              Text('Davet Et',
                                  style: TextStyle(
                                      color: Colors.blueAccent,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold))
                            ],
                          ),
                        ),
                      )
                  ]),
                ),
            ],
          ),
        ),
        if (widget.ad.buyItNowPrice != null) ...[
          Container(
              width: 1,
              height: 40,
              color: Colors.white.withOpacity(0.1),
              margin: const EdgeInsets.symmetric(horizontal: 16)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('HEMEN AL',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 2),
              Text('₺${_formatPrice(widget.ad.buyItNowPrice!)}',
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ]
      ],
    );
  }

  Widget _buildLandscapeStatsInner() {
    return Row(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('GÜNCEL TEQLİF',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                  Text(
                    _bids.isNotEmpty
                        ? '₺${_formatPrice(_bids.first.amount)}'
                        : 'Henüz teqlif Yok',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _isAuctionActive
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: _isAuctionActive
                          ? Colors.green.withOpacity(0.5)
                          : Colors.orange.withOpacity(0.5)),
                ),
                child: Text(
                  _isAuctionActive
                      ? 'AÇIK ARTTIRMA AKTİF'
                      : 'AÇIK ARTTIRMA DURDURULDU',
                  style: TextStyle(
                    color: _isAuctionActive
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (_bids.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(_bids.first.userLabel,
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ]
            ],
          ),
        ),
        if (widget.ad.buyItNowPrice != null) ...[
          Container(
              width: 1,
              height: 30,
              color: Colors.white.withOpacity(0.1),
              margin: const EdgeInsets.symmetric(horizontal: 12)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('HEMEN AL',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              Text('₺${_formatPrice(widget.ad.buyItNowPrice!)}',
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ]
      ],
    );
  }

  Widget _buildChatFlow({required double height, String? currentUserId}) {
    return ShaderMask(
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
        height: height,
        child: ListView.builder(
          reverse: true,
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final msg = _messages[_messages.length - 1 - index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${msg.senderName}:',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(msg.text,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500))),
                    if (msg.senderId != null && msg.senderId != currentUserId)
                      GestureDetector(
                        onTap: () => _inviteToStage(msg.senderId!),
                        child: Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.mic,
                              color: Colors.blueAccent, size: 12),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHostControls({required Room? room}) {
    return Column(
      children: [
        if (_stageRequests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CircularControlButton(
              icon: Icons.record_voice_over,
              onPressed: () {
                final req = _stageRequests.first;
                showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                          title: const Text('Sahne İsteği'),
                          content: Text(
                              '${req.name} adlı kullanıcı sahneye katılmak istiyor. Kabul ediyor musunuz?'),
                          actions: [
                            TextButton(
                                onPressed: () {
                                  setState(() => _stageRequests
                                      .removeWhere((r) => r.id == req.id));
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Reddet')),
                            TextButton(
                                onPressed: () {
                                  _inviteToStage(req.id);
                                  setState(() => _stageRequests
                                      .removeWhere((r) => r.id == req.id));
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Kabul Et',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                          ],
                        ));
              },
              badge: '${_stageRequests.length}',
              badgeColor: Colors.blueAccent,
            ),
          ),
        _CircularControlButton(
          icon: Icons.gavel,
          onPressed: _showBidsBottomSheet,
          badge: _unreadBids > 0 ? '$_unreadBids' : null,
        ),
        const SizedBox(height: 12),
        _CircularControlButton(
          icon: Icons.switch_camera,
          onPressed: () async {
            final p = room?.localParticipant;
            if (p != null) {
              final trackPub = p.videoTrackPublications.firstOrNull;
              if (trackPub != null && trackPub.track != null) {
                try {
                  final mediaTrack = trackPub.track!.mediaStreamTrack;
                  if (mediaTrack != null) {
                    await webrtc.Helper.switchCamera(mediaTrack);
                  }
                } catch (e) {
                  debugPrint("Error switching camera: $e");
                }
              }
            }
          },
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
    );
  }

  Widget _buildAuctionAndChatInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Remove strict widget.ad.isAuction check to allow hybrid auctions on fixed-price ads
          // Reset Auction Button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _resetAuction,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: const Icon(Icons.refresh, color: Colors.white, size: 28),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _toggleAuction,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _isAuctionActive
                      ? Colors.redAccent
                      : Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30),
                  boxShadow: _isAuctionActive
                      ? [
                          BoxShadow(
                              color: Colors.redAccent.withOpacity(0.4),
                              blurRadius: 15)
                        ]
                      : null,
                ),
                child: Icon(_isAuctionActive ? Icons.stop : Icons.play_arrow,
                    color: Colors.white, size: 30),
              ),
            ),
          ),
          if (_isAuctionActive) // Show countdown for any active auction
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _startCountdown,
                child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _countdown > 0 && _countdown <= 10
                            ? 1.0 + (_pulseController.value * 0.15)
                            : 1.0,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _countdown > 0 ? Colors.red : Colors.orange,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: (_countdown > 0
                                          ? Colors.red
                                          : Colors.orange)
                                      .withOpacity(0.5),
                                  blurRadius: 15)
                            ],
                          ),
                          child: Center(
                            child: _countdown > 0
                                ? Text('$_countdown',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 24))
                                : const Icon(Icons.timer,
                                    color: Colors.white, size: 28),
                          ),
                        ),
                      );
                    }),
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
                          style: const TextStyle(
                              color: Colors.black, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            hintText: 'Sohbete dahil ol...',
                            hintStyle:
                                TextStyle(color: Colors.black54, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
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
    );
  }

  Widget _buildPortraitLayout(
      dynamic roomState,
      Room? room,
      VideoTrack? localVideoTrack,
      VideoTrack? guestTrack,
      String? guestIdentity) {
    final screenSize = MediaQuery.of(context).size;
    if (guestTrack != null) {
      _pipOffset ??= Offset(screenSize.width - 116, 220);
    }

    return Stack(
      children: [
        _buildLoadingOrCamera(roomState, room, localVideoTrack),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTopDashboard(false),
            ),
          ),
        ),
        if (guestTrack != null)
          Positioned(
            top: _pipOffset!.dy,
            left: _pipOffset!.dx,
            width: 100,
            height: 140,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _pipOffset = Offset(
                    (_pipOffset!.dx + details.delta.dx)
                        .clamp(0.0, screenSize.width - 100.0),
                    (_pipOffset!.dy + details.delta.dy)
                        .clamp(0.0, screenSize.height - 140.0),
                  );
                });
              },
              child: _buildGuestTrackView(guestTrack, guestIdentity),
            ),
          ),
        FloatingReactionsOverlay(reactions: _reactions),
        SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: _buildChatFlow(
                          height: 150,
                          currentUserId: ref.read(authProvider).user?.id),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildHostControls(room: room),
                        const SizedBox(height: 12),
                        ReactionButtons(onReact: _sendReaction),
                      ],
                    ),
                  ),
                ],
              ),
              _buildAuctionAndChatInput(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(
      dynamic roomState,
      Room? room,
      VideoTrack? localVideoTrack,
      VideoTrack? guestTrack,
      String? guestIdentity) {
    return Row(
      children: [
        // LEFT side: Video constraints completely clean
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              _buildLoadingOrCamera(roomState, room, localVideoTrack),
              FloatingReactionsOverlay(reactions: _reactions),
            ],
          ),
        ),

        // RIGHT side: All interactions compacted
        Container(
          width: 380,
          color: Colors.black.withOpacity(0.5), // Distinct dashboard section
          child: SafeArea(
            left: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _buildTopDashboard(true),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      if (guestTrack != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: SizedBox(
                              width: 100,
                              height: 140,
                              child: _buildGuestTrackView(
                                  guestTrack, guestIdentity),
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16, bottom: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildHostControls(room: room),
                              const SizedBox(height: 12),
                              ReactionButtons(onReact: _sendReaction),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              left: 16, right: 80, bottom: 8),
                          child: _buildChatFlow(
                              height: 120,
                              currentUserId: ref.read(authProvider).user?.id),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildAuctionAndChatInput(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showFinalizationOverlayAlert(String? winnerName, double? amount) {
    if (!mounted) return;
    setState(() {
      _finalizedWinnerName = winnerName ?? 'Katılımcı';
      _finalizedAmount = amount;
      _showFinalizationOverlay = true;
    });

    // Optionally add a chat message about the sale
    final chatPayload = jsonEncode({
      'type': 'CHAT',
      'text':
          '🎉 Tebrikler! ${_formatSenderName(winnerName)} bu ürünü ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(amount)} bedel ile kazandı!',
      'senderName': 'SİSTEM',
    });
    _handleDataChannelMessage(utf8.encode(chatPayload), null,
        customName: 'SİSTEM');

    // Auto-hide the overlay after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showFinalizationOverlay = false;
        });
      }
    });
  }

  Widget _buildFinalizationOverlay() {
    if (!_showFinalizationOverlay) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.celebration,
                        color: Colors.amber, size: 80),
                    const SizedBox(height: 16),
                    const Text(
                      'SATILDI!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        shadows: [Shadow(blurRadius: 10, color: Colors.amber)],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tebrikler ${_formatSenderName(_finalizedWinnerName)}!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_finalizedAmount != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(_finalizedAmount)}',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CircularControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? badge;
  final Color badgeColor;

  const _CircularControlButton({
    required this.icon,
    required this.onPressed,
    this.badge,
    this.badgeColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
          ),
        ),
        if (badge != null)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
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
  final String? userId;

  _LiveBid({
    required this.id,
    required this.amount,
    required this.userLabel,
    required this.timestamp,
    this.isAccepted = false,
    this.userId,
  });
}

class _EphemeralMessage {
  final String id;
  final String text;
  final String senderName;
  final DateTime timestamp;
  final String? senderId;

  _EphemeralMessage({
    required this.id,
    required this.text,
    required this.senderName,
    required this.timestamp,
    this.senderId,
  });
}
