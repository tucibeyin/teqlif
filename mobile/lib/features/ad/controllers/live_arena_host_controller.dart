import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/models/ad.dart';
import '../../../core/providers/live_room_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/utils/profanity_filter.dart';
import '../models/live_bid.dart';
import '../models/stage_request.dart';
import '../providers/ad_detail_provider.dart';
import '../widgets/floating_reactions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HostState — Immutable snapshot of everything the host screen needs
// ─────────────────────────────────────────────────────────────────────────────

class HostState {
  final List<LiveBid> bids;
  final List<EphemeralMessage> messages;
  final bool isAuctionActive;
  final bool isCameraEnabled;
  final bool isMicEnabled;
  final bool isFinalizing;
  final int countdown;
  final int unreadBids;
  final List<StageRequest> stageRequests;
  final List<FloatingReaction> reactions;
  final int lastReactionTime;
  final bool isSold;
  final String? soldWinnerName;
  final double? soldFinalPrice;
  final bool showSoldOverlay;
  final String? finalizedWinnerName;
  final double? finalizedAmount;
  final bool showFinalizationOverlay;

  const HostState({
    required this.bids,
    required this.messages,
    required this.isAuctionActive,
    required this.isCameraEnabled,
    required this.isMicEnabled,
    required this.isFinalizing,
    required this.countdown,
    required this.unreadBids,
    required this.stageRequests,
    required this.reactions,
    required this.lastReactionTime,
    required this.isSold,
    this.soldWinnerName,
    this.soldFinalPrice,
    required this.showSoldOverlay,
    this.finalizedWinnerName,
    this.finalizedAmount,
    required this.showFinalizationOverlay,
  });

  factory HostState.initial(AdModel? ad) => HostState(
        bids: const [],
        messages: const [],
        isAuctionActive: ad?.isAuctionActive ?? false,
        isCameraEnabled: true,
        isMicEnabled: true,
        isFinalizing: false,
        countdown: 0,
        unreadBids: 0,
        stageRequests: const [],
        reactions: const [],
        lastReactionTime: 0,
        isSold: false,
        showSoldOverlay: false,
        showFinalizationOverlay: false,
      );

  HostState copyWith({
    List<LiveBid>? bids,
    List<EphemeralMessage>? messages,
    bool? isAuctionActive,
    bool? isCameraEnabled,
    bool? isMicEnabled,
    bool? isFinalizing,
    int? countdown,
    int? unreadBids,
    List<StageRequest>? stageRequests,
    List<FloatingReaction>? reactions,
    int? lastReactionTime,
    bool? isSold,
    Object? soldWinnerName = _sentinel,
    Object? soldFinalPrice = _sentinel,
    bool? showSoldOverlay,
    Object? finalizedWinnerName = _sentinel,
    Object? finalizedAmount = _sentinel,
    bool? showFinalizationOverlay,
  }) {
    return HostState(
      bids: bids ?? this.bids,
      messages: messages ?? this.messages,
      isAuctionActive: isAuctionActive ?? this.isAuctionActive,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isMicEnabled: isMicEnabled ?? this.isMicEnabled,
      isFinalizing: isFinalizing ?? this.isFinalizing,
      countdown: countdown ?? this.countdown,
      unreadBids: unreadBids ?? this.unreadBids,
      stageRequests: stageRequests ?? this.stageRequests,
      reactions: reactions ?? this.reactions,
      lastReactionTime: lastReactionTime ?? this.lastReactionTime,
      isSold: isSold ?? this.isSold,
      soldWinnerName: soldWinnerName == _sentinel
          ? this.soldWinnerName
          : soldWinnerName as String?,
      soldFinalPrice: soldFinalPrice == _sentinel
          ? this.soldFinalPrice
          : soldFinalPrice as double?,
      showSoldOverlay: showSoldOverlay ?? this.showSoldOverlay,
      finalizedWinnerName: finalizedWinnerName == _sentinel
          ? this.finalizedWinnerName
          : finalizedWinnerName as String?,
      finalizedAmount: finalizedAmount == _sentinel
          ? this.finalizedAmount
          : finalizedAmount as double?,
      showFinalizationOverlay:
          showFinalizationOverlay ?? this.showFinalizationOverlay,
    );
  }
}

// Sentinel for nullable copyWith fields
const _sentinel = Object();

// ─────────────────────────────────────────────────────────────────────────────
// HostController — all business logic
// ─────────────────────────────────────────────────────────────────────────────

class HostController extends StateNotifier<HostState> {
  final String adId; // Changed from AdModel ad
  final Ref ref;
  Timer? _countdownTimer;
  VoidCallback? onPlayConfetti;
  VoidCallback? onPulseStart;
  VoidCallback? onPulseStop;

  HostController(this.adId, this.ref, {AdModel? initialAd})
      : super(HostState.initial(initialAd));

  Room? get _room => ref.read(liveRoomProvider(adId)).room;

  AdModel get ad {
    final liveAd = ref.read(adDetailProvider(adId)).value;
    if (liveAd != null) return liveAd;
    throw Exception('Ad not found in provider for $adId');
  }

  // Expose room for widgets that need local participant info (e.g. chat input)
  Room? get currentRoom => _room;

  // ── Helpers ────────────────────────────────────────────────────────────────

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

  String _formatPrice(double amount) {
    return NumberFormat.decimalPattern('tr').format(amount);
  }

  void _resetMessageTimer() {
    Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final msgs = List<EphemeralMessage>.from(state.messages);
      if (msgs.isNotEmpty) msgs.removeAt(0);
      state = state.copyWith(messages: msgs);
    });
  }

  // ── Reactions ──────────────────────────────────────────────────────────────

  void addReaction(String emoji) {
    if (!mounted) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
    final updated = List<FloatingReaction>.from(state.reactions)
      ..add(FloatingReaction(id: id, emoji: emoji));
    if (updated.length > 20) updated.removeAt(0);
    state = state.copyWith(reactions: updated);

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      state = state.copyWith(
        reactions: state.reactions.where((r) => r.id != id).toList(),
      );
    });
  }

  void sendReaction(String emoji) {
    if (_room == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - state.lastReactionTime < 500) return;
    state = state.copyWith(lastReactionTime: now);

    final payload = jsonEncode({'type': 'REACTION', 'emoji': emoji});
    try {
      _room!.localParticipant!.publishData(utf8.encode(payload));
      addReaction(emoji);
    } catch (e) {
      debugPrint('Reaction send error: $e');
    }
  }

  // ── Chat ───────────────────────────────────────────────────────────────────

  Future<void> sendChatMessage(String text) async {
    if (text.isEmpty) return;
    final room = _room;
    if (room != null) {
      final identity = room.localParticipant?.identity;
      final name = room.localParticipant?.name;
      final censoredText = ProfanityFilter.censor(text);
      final payload = jsonEncode({
        'type': 'CHAT',
        'text': censoredText,
        'senderName': name,
        'senderId': identity,
      });
      await room.localParticipant?.publishData(utf8.encode(payload));
      handleDataChannelMessage(utf8.encode(payload), null, customName: name);
    }
  }

  // Camera / mic state (called from widgets)
  void setCameraEnabled(bool enabled) =>
      state = state.copyWith(isCameraEnabled: enabled);
  void setMicEnabled(bool enabled) =>
      state = state.copyWith(isMicEnabled: enabled);

  // ── Data Channel ───────────────────────────────────────────────────────────

  void handleDataChannelMessage(List<int> data, RemoteParticipant? p,
      {String? customName}) {
    String message;
    try {
      message = utf8.decode(data);
    } catch (e) {
      debugPrint('UTF-8 Decode error: $e');
      message = String.fromCharCodes(data);
    }

    try {
      final dataObj = jsonDecode(message);

      if (dataObj['type'] == 'BID_ACCEPTED') {
        final amount = (dataObj['amount'] as num).toDouble();
        final bidId = dataObj['bidId']?.toString();
        final bids = List<LiveBid>.from(state.bids);
        final existingIndex = bids.indexWhere((b) => b.id == bidId);
        if (existingIndex != -1) {
          bids[existingIndex] = bids[existingIndex].copyWith(
            amount: amount,
            userLabel: dataObj['bidderName'] ?? bids[existingIndex].userLabel,
            isAccepted: true,
            userId: dataObj['bidderId']?.toString() ?? bids[existingIndex].userId,
          );
        } else {
          bids.insert(
            0,
            LiveBid(
              id: bidId ?? 'bid-${DateTime.now().millisecondsSinceEpoch}',
              amount: amount,
              userLabel: _formatSenderName(dataObj['bidderName']),
              timestamp: DateTime.now(),
              isAccepted: true,
              userId: dataObj['bidderId']?.toString(),
            ),
          );
        }
        state = state.copyWith(bids: bids);
        return;

      } else if (dataObj['type'] == 'CHAT') {
        final chatText = dataObj['text']?.toString() ?? '';
        final chatSender = dataObj['senderName']?.toString();
        final senderId = dataObj['senderId']?.toString();
        final msgs = List<EphemeralMessage>.from(state.messages)
          ..add(EphemeralMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: chatText,
            senderName: _formatSenderName(chatSender),
            timestamp: DateTime.now(),
            senderId: senderId,
          ));
        if (msgs.length > 5) msgs.removeAt(0);
        state = state.copyWith(messages: msgs);
        _resetMessageTimer();
        return;

      } else if (dataObj['type'] == 'NEW_BID') {
        final amount = (dataObj['amount'] as num).toDouble();
        final bidId = dataObj['bidId']?.toString();
        final bidderId = dataObj['bidderIdentity']?.toString() ?? dataObj['bidderId']?.toString();
        final bids = List<LiveBid>.from(state.bids);
        bids.insert(
          0,
          LiveBid(
            id: bidId ?? 'bid-${DateTime.now().millisecondsSinceEpoch}',
            amount: amount,
            userLabel: _formatSenderName(dataObj['bidderName']),
            timestamp: DateTime.now(),
            userId: bidderId,
          ),
        );
        if (bids.length > 50) bids.removeLast();
        state = state.copyWith(bids: bids, unreadBids: state.unreadBids + 1);
        return;

      } else if (dataObj['type'] == 'SALE_FINALIZED') {
        final winnerName = dataObj['winnerName']?.toString();
        final amount = dataObj['amount'] != null
            ? (dataObj['amount'] as num).toDouble()
            : null;
        _showFinalizationOverlayAlert(winnerName, amount);
        return;

      } else if (dataObj['type'] == 'AUCTION_SOLD') {
        final winner = dataObj['winnerName']?.toString() ?? 'Katılımcı';
        final price = dataObj['price'] != null
            ? (dataObj['price'] as num).toDouble()
            : 0.0;
        state = state.copyWith(
          isSold: true,
          showSoldOverlay: true,
          soldWinnerName: winner,
          soldFinalPrice: price,
          isAuctionActive: false,
        );
        onPlayConfetti?.call();
        return;

      } else if (dataObj['type'] == 'AUCTION_RESET') {
        state = state.copyWith(
          isSold: false,
          showSoldOverlay: false,
          soldWinnerName: null,
          soldFinalPrice: null,
          isAuctionActive: false,
          bids: [],
          unreadBids: 0,
          countdown: 0,
        );
        return;

      } else if (dataObj['type'] == 'AUCTION_ENDED') {
        final winner = dataObj['winner']?.toString() ?? 'Katılımcı';
        final amount = (dataObj['amount'] as num?)?.toDouble();
        state = state.copyWith(isAuctionActive: false);
        _showFinalizationOverlayAlert(winner, amount);
        onPlayConfetti?.call();
        return;

      } else if (dataObj['type'] == 'BID_REJECTED') {
        final bidId = dataObj['bidId']?.toString();
        state = state.copyWith(
          bids: state.bids.where((b) => b.id != bidId).toList(),
        );
        return;

      } else if (dataObj['type'] == 'COUNTDOWN') {
        final count = dataObj['value'] as int;
        state = state.copyWith(countdown: count);
        if (count > 0 && count <= 10) {
          onPulseStart?.call();
        } else {
          onPulseStop?.call();
        }
        return;

      } else if (dataObj['type'] == 'REACTION') {
        addReaction(dataObj['emoji']?.toString() ?? '❤️');
        return;

      } else if (dataObj['type'] == 'REQUEST_STAGE') {
        final userId = dataObj['userId']?.toString();
        final userName = dataObj['userName']?.toString() ?? 'Katılımcı';
        if (userId != null && !state.stageRequests.any((r) => r.id == userId)) {
          state = state.copyWith(
            stageRequests: [...state.stageRequests, StageRequest(userId, userName)],
          );
        }
        return;

      } else if (dataObj['type'] == 'SYNC_STATE_REQUEST') {
        if (_room != null) {
          final payload = jsonEncode({
            'type': 'SYNC_STATE_RESPONSE',
            'isAuctionActive': state.isAuctionActive,
            'highestBid': state.bids.isNotEmpty
                ? state.bids.first.amount
                : (ad.highestBidAmount ?? 0.0),
            'highestBidderName':
                state.bids.isNotEmpty ? state.bids.first.userLabel : null,
            'isSold': state.isSold,
          });
          _room!.localParticipant?.publishData(utf8.encode(payload));
        }
        return;
      }
    } catch (_) {}

    // Fallback: plain text message
    final senderName = customName ?? p?.name;
    final msgs = List<EphemeralMessage>.from(state.messages)
      ..add(EphemeralMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: message,
        senderName: _formatSenderName(senderName),
        timestamp: DateTime.now(),
      ));
    if (msgs.length > 5) msgs.removeAt(0);
    state = state.copyWith(messages: msgs);
    _resetMessageTimer();
  }

  // ── Countdown ──────────────────────────────────────────────────────────────

  void broadcastCountdown(int value) async {
    if (_room != null) {
      final payload = jsonEncode({'type': 'COUNTDOWN', 'value': value});
      await _room!.localParticipant?.publishData(utf8.encode(payload));
    }
  }

  void startCountdown() {
    if (_countdownTimer != null && _countdownTimer!.isActive) return;
    state = state.copyWith(countdown: 10);
    onPulseStart?.call();
    broadcastCountdown(10);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (state.countdown > 0) {
        final next = state.countdown - 1;
        state = state.copyWith(countdown: next);
        broadcastCountdown(next);
      } else {
        timer.cancel();
        onPulseStop?.call();
      }
    });
  }

  // ── Auction ────────────────────────────────────────────────────────────────

  Future<void> toggleAuction() async {
    if (_room == null) return;
    final newActive = !state.isAuctionActive;
    state = state.copyWith(isAuctionActive: newActive);

    final signal = jsonEncode({
      'type': newActive ? 'AUCTION_START' : 'AUCTION_END',
      'adId': adId,
    });

    try {
      await _room!.localParticipant?.publishData(signal.codeUnits);
      await ApiClient().post('/api/ads/$adId/live', data: {
        'isAuctionActive': newActive,
      });

      final signalName = _room!.localParticipant?.name;
      final chatPayload = jsonEncode({
        'type': 'CHAT',
        'text': newActive
            ? '📣 Açık Arttırma Başlatıldı!'
            : '📣 Açık Arttırma Durduruldu!',
        'senderName': signalName,
      });
      handleDataChannelMessage(utf8.encode(chatPayload), null,
          customName: signalName);
    } catch (e) {
      debugPrint('Signal error: $e');
    }
  }

  Future<void> resetAuction(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Açık Arttırmayı Sıfırla'),
        content: const Text(
            'Tüm teklifleri iptal edip başlangıç fiyatına dönmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sıfırla', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final res = await ApiClient()
          .post('/api/livekit/reset', data: {'adId': adId});
      if (res.statusCode == 200 || res.statusCode == 201) {
        final payload = jsonEncode({'type': 'AUCTION_RESET'});
        if (_room != null) {
          await _room!.localParticipant?.publishData(utf8.encode(payload));
        }
        state = state.copyWith(bids: [], unreadBids: 0);
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            _systemSnack('📣 AÇIK ARTTIRMA SIFIRLANDI!', Colors.orange, ctx),
          );
        }
      }
    } catch (e) {
      debugPrint('Reset auction error: $e');
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Sıfırlama başarısız oldu.')),
        );
      }
    }
  }

  // ── Bids ───────────────────────────────────────────────────────────────────

  Future<void> cancelBid(String bidId, BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('teqlifi İptal Et'),
        content: const Text(
            'Bu teqlifi reddetmek veya iptal etmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Hayır')),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('İptal Et',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient().patch('/api/bids/$bidId/cancel');
        state = state.copyWith(
          bids: state.bids.where((b) => b.id != bidId).toList(),
        );
      } catch (e) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('İptal işlemi başarısız.')));
        }
      }
    }
  }

  Future<void> _finalizeBid(LiveBid bid, BuildContext ctx) async {
    state = state.copyWith(isFinalizing: true);
    try {
      final isQuickLive = ad.description == 'Hızlı Canlı Yayın (Ghost Ad)';
      final res = await ApiClient().post('/api/livekit/finalize', data: {
        'adId': adId,
        'isQuickLive': isQuickLive,
      });
      if (res.statusCode != 200 && res.statusCode != 201) {
        final errMsg = res.data['error']?.toString() ?? 'Satış tamamlanamadı.';
        throw Exception(errMsg);
      }
      // Backend broadcasts AUCTION_ENDED to all participants.
      // handleDataChannelMessage will update UI when that signal arrives.
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(
                e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) state = state.copyWith(isFinalizing: false);
    }
  }

  Future<void> acceptBidFromDashboard(BuildContext ctx) async {
    if (state.bids.isEmpty) return;
    final latestBid = state.bids.first;

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Satışı Onayla'),
        content: Text(
            '₺${_formatPrice(latestBid.amount)} tutarındaki son teqlifi kabul edip satışı ilanını sonlandırmak istiyor musunuz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('İptal')),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Onayla ve Sat',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirmed == true) {
      await _finalizeBid(latestBid, ctx);
    }
  }

  Future<void> acceptBidFromSheet(
      LiveBid bid, BuildContext ctx, VoidCallback closeSheet) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('teqlifi Onayla'),
        content: Text(
            '₺${_formatPrice(bid.amount)} tutarındaki teqlifi kabul edip satışı ilanını sonlandırmak istiyor musunuz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Hayır')),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Evet, Sat')),
        ],
      ),
    );
    if (confirmed == true) {
      closeSheet();
      await _finalizeBid(bid, ctx);
    }
  }

  // ── Stage ──────────────────────────────────────────────────────────────────

  void inviteToStage(String userId, BuildContext ctx) async {
    if (_room != null) {
      final payload = jsonEncode(
          {'type': 'INVITE_TO_STAGE', 'targetIdentity': userId});
      await _room!.localParticipant?.publishData(utf8.encode(payload));
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
              content: Text('Sahneye davet gönderildi!'),
              backgroundColor: Colors.blue),
        );
      }
    }
  }

  void kickGuest(String userId, BuildContext ctx) async {
    if (_room != null) {
      final payload = jsonEncode(
          {'type': 'KICK_FROM_STAGE', 'targetIdentity': userId});
      await _room!.localParticipant?.publishData(utf8.encode(payload));
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
              content: Text('Davetli çıkarıldı.'),
              backgroundColor: Colors.orange),
        );
      }
    }
  }

  void dismissStageRequest(String requestId) {
    state = state.copyWith(
      stageRequests:
          state.stageRequests.where((r) => r.id != requestId).toList(),
    );
  }

  // ── Moderation ─────────────────────────────────────────────────────────────

  Future<void> moderateUser(
      String identity, String name, String action, BuildContext ctx) async {
    try {
      final res = await ApiClient().post(
        Endpoints.moderation,
        data: {
          'roomId': adId,
          'identity': identity,
          'action': action,
        },
      );

      if (res.statusCode == 200) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(action == 'kick'
                ? '$name odadan atıldı.'
                : '$name susturuldu.'),
            backgroundColor: Colors.green,
          ));
        }
      } else {
        throw Exception(res.data['error'] ?? 'İşlem başarısız.');
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Moderasyon hatası: ${e.toString()}'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Room lifecycle ─────────────────────────────────────────────────────────

  Future<void> endLiveStream(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Yayını Bitir'),
        content: const Text(
            'Canlı yayını sonlandırmak ve odadan çıkmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('İptal')),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Evet, Bitir',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirmed == true) {
      if (!ctx.mounted) return;
      try {
        state = state.copyWith(isFinalizing: true);

        // Signal room closing (Best effort)
        if (_room != null) {
          try {
            final payload = jsonEncode({'type': 'ROOM_CLOSED'});
            await _room!.localParticipant
                ?.publishData(utf8.encode(payload))
                .timeout(const Duration(seconds: 1));
          } catch (_) {}
        }

        // Tell backend we're done (Best effort)
        try {
          await ApiClient()
              .post('/api/ads/$adId/live', data: {'isLive': false})
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      } finally {
        // Essential Cleanup: Disconnect RTC
        await ref.read(liveRoomProvider(adId).notifier).disconnect();

        // Exit screen
        if (ctx.mounted) {
          ctx.go('/home');
        }
      }
    }
  }

  Future<void> closeLiveStreamSilently(BuildContext ctx) async {
    try {
      state = state.copyWith(isFinalizing: true);

      // Signal room closing (Best effort)
      if (_room != null) {
        try {
          final payload = jsonEncode({'type': 'ROOM_CLOSED'});
          await _room!.localParticipant
              ?.publishData(utf8.encode(payload))
              .timeout(const Duration(seconds: 1));
        } catch (_) {}
      }

      // Tell backend we're done (Best effort)
      try {
        await ApiClient()
            .post('/api/ads/$adId/live', data: {'isLive': false})
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    } finally {
      // Essential Cleanup: Disconnect RTC
      await ref.read(liveRoomProvider(adId).notifier).disconnect();

      // Exit screen
      if (ctx.mounted) {
        ctx.go('/home');
      }
    }
  }

  // ── Overlay helpers ────────────────────────────────────────────────────────

  void hideSoldOverlay() => state = state.copyWith(showSoldOverlay: false);

  void _showFinalizationOverlayAlert(String? winnerName, double? amount) {
    state = state.copyWith(
      finalizedWinnerName: winnerName ?? 'Katılımcı',
      finalizedAmount: amount,
      showFinalizationOverlay: true,
    );

    final chatPayload = jsonEncode({
      'type': 'CHAT',
      'text':
          '🎉 Tebrikler! ${_formatSenderName(winnerName)} bu ürünü ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(amount)} bedel ile kazandı!',
      'senderName': 'SİSTEM',
    });
    handleDataChannelMessage(utf8.encode(chatPayload), null,
        customName: 'SİSTEM');

    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted) return;
      state = state.copyWith(showFinalizationOverlay: false);
    });
  }

  void readBids() => state = state.copyWith(unreadBids: 0);

  // ── Snack helper ───────────────────────────────────────────────────────────

  SnackBar _systemSnack(String text, Color color, BuildContext ctx) {
    return SnackBar(
      content: Center(
          child: Text(text,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: Colors.white))),
      behavior: SnackBarBehavior.floating,
      backgroundColor: color.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).size.height * 0.7,
          left: 50,
          right: 50),
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final hostControllerProvider =
    StateNotifierProvider.family<HostController, HostState, String>(
  (ref, adId) {
    final ad = ref.read(adDetailProvider(adId)).value;
    return HostController(adId, ref, initialAd: ad);
  },
);
