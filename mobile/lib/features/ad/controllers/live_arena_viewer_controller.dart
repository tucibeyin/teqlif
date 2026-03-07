import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/live_room_provider.dart';
import '../../../core/utils/profanity_filter.dart';
import '../models/live_bid.dart';
import '../providers/ad_detail_provider.dart';
import '../widgets/floating_reactions.dart';
import '../../dashboard/screens/dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ViewerState — Immutable snapshot of everything the viewer screen needs
// ─────────────────────────────────────────────────────────────────────────────

class ViewerState {
  final VideoQuality currentQuality;
  final List<EphemeralMessage> messages;
  final bool bidLoading;
  final List<DateTime> recentBids;
  final bool isHypeMode;
  final bool isGuest;
  final bool isAuctionActive;
  final double? liveHighestBid;
  final List<FloatingReaction> reactions;
  final int lastReactionTime;
  final bool isMuted;
  final int? countdownValue;
  final bool isSold;
  final String? soldWinnerName;
  final double? soldFinalPrice;
  final bool showSoldOverlay;
  final String? finalizedWinnerName;
  final double? finalizedAmount;
  final bool showFinalizationOverlay;
  final bool isReconnectingForStage;
  final String? liveHighestBidderName;
  /// Kanal modunda şu an aktif olan ürünün adId'si. null → klasik mod (adId kullanılır).
  final String? activeAdId;

  const ViewerState({
    required this.currentQuality,
    required this.messages,
    required this.bidLoading,
    required this.recentBids,
    required this.isHypeMode,
    required this.isGuest,
    required this.isAuctionActive,
    this.liveHighestBid,
    required this.reactions,
    required this.lastReactionTime,
    required this.isMuted,
    this.countdownValue,
    required this.isSold,
    this.soldWinnerName,
    this.soldFinalPrice,
    required this.showSoldOverlay,
    this.finalizedWinnerName,
    this.finalizedAmount,
    required this.showFinalizationOverlay,
    required this.isReconnectingForStage,
    this.liveHighestBidderName,
    this.activeAdId,
  });

  factory ViewerState.initial(AdModel? ad) => ViewerState(
        currentQuality: VideoQuality.HIGH,
        messages: const [],
        bidLoading: false,
        recentBids: const [],
        isHypeMode: false,
        isGuest: false,
        isAuctionActive: ad?.isAuctionActive ?? false,
        liveHighestBid: ad?.highestBidAmount,
        reactions: const [],
        lastReactionTime: 0,
        isMuted: false,
        countdownValue: null,
        isSold: false,
        soldWinnerName: null,
        soldFinalPrice: null,
        showSoldOverlay: false,
        finalizedWinnerName: null,
        finalizedAmount: null,
        showFinalizationOverlay: false,
        isReconnectingForStage: false,
        liveHighestBidderName: ad?.highestBidderName,
        activeAdId: null,
      );

  ViewerState copyWith({
    VideoQuality? currentQuality,
    List<EphemeralMessage>? messages,
    bool? bidLoading,
    List<DateTime>? recentBids,
    bool? isHypeMode,
    bool? isGuest,
    bool? isAuctionActive,
    Object? liveHighestBid = _sentinel,
    List<FloatingReaction>? reactions,
    int? lastReactionTime,
    bool? isMuted,
    Object? countdownValue = _sentinel,
    bool? isSold,
    Object? soldWinnerName = _sentinel,
    Object? soldFinalPrice = _sentinel,
    bool? showSoldOverlay,
    Object? finalizedWinnerName = _sentinel,
    Object? finalizedAmount = _sentinel,
    bool? showFinalizationOverlay,
    bool? isReconnectingForStage,
    Object? liveHighestBidderName = _sentinel,
    Object? activeAdId = _sentinel,
  }) {
    return ViewerState(
      currentQuality: currentQuality ?? this.currentQuality,
      messages: messages ?? this.messages,
      bidLoading: bidLoading ?? this.bidLoading,
      recentBids: recentBids ?? this.recentBids,
      isHypeMode: isHypeMode ?? this.isHypeMode,
      isGuest: isGuest ?? this.isGuest,
      isAuctionActive: isAuctionActive ?? this.isAuctionActive,
      liveHighestBid: liveHighestBid == _sentinel
          ? this.liveHighestBid
          : liveHighestBid as double?,
      reactions: reactions ?? this.reactions,
      lastReactionTime: lastReactionTime ?? this.lastReactionTime,
      isMuted: isMuted ?? this.isMuted,
      countdownValue: countdownValue == _sentinel
          ? this.countdownValue
          : countdownValue as int?,
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
      isReconnectingForStage:
          isReconnectingForStage ?? this.isReconnectingForStage,
      liveHighestBidderName: liveHighestBidderName == _sentinel
          ? this.liveHighestBidderName
          : liveHighestBidderName as String?,
      activeAdId: activeAdId == _sentinel
          ? this.activeAdId
          : activeAdId as String?,
    );
  }
}

const _sentinel = Object();

// ─────────────────────────────────────────────────────────────────────────────
// ViewerController
// ─────────────────────────────────────────────────────────────────────────────

class ViewerController extends StateNotifier<ViewerState> {
  final String adId;
  final Ref ref;
  Timer? _inactivityTimer;
  Timer? _hypeTimer;
  bool _disposed = false;
  void Function()? _roomEventUnsubscribe;

  // Animation callbacks — wired from initState via addPostFrameCallback
  VoidCallback? onPlayConfetti;
  VoidCallback? onPulseStart;
  VoidCallback? onPulseStop;

  // _bidCtrl.text update callback (form controller stays in State)
  void Function(String)? onUpdateBidText;

  // Invite dialog callback (showDialog stays in State)
  VoidCallback? onShowInviteDialog;

  // Kicked snackbar callback (ScaffoldMessenger stays in State)
  VoidCallback? onKicked;

  // System message callback (ScaffoldMessenger stays in State)
  void Function(String, Color)? onShowSystemMessage;

  // Inactivity timeout callback
  VoidCallback? onInactivityTimeout;

  ViewerController(this.adId, this.ref, {AdModel? initialAd})
      : super(ViewerState.initial(initialAd));

  Room? get _room => ref.read(liveRoomProvider(adId)).room;

  AdModel? get ad => ref.read(adDetailProvider(adId)).value;

  @override
  void dispose() {
    _disposed = true;
    _inactivityTimer?.cancel();
    _hypeTimer?.cancel();
    _roomEventUnsubscribe?.call();
    super.dispose();
  }

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

  String _formatPrice(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  double getNextBidAmount(AdModel currentAd) {
    if (state.liveHighestBid != null) {
      return state.liveHighestBid! + currentAd.minBidStep;
    }
    if (!currentAd.isAuction && !state.isAuctionActive) return currentAd.price;
    final base =
        currentAd.highestBidAmount ?? currentAd.startingBid ?? currentAd.price;
    return base + currentAd.minBidStep;
  }

  // ── State mutators ─────────────────────────────────────────────────────────

  void hideSoldOverlay() => state = state.copyWith(showSoldOverlay: false);
  void setIsMuted(bool value) => state = state.copyWith(isMuted: value);
  void setIsGuest(bool value) => state = state.copyWith(isGuest: value);
  void setReconnectingForStage(bool value) =>
      state = state.copyWith(isReconnectingForStage: value);

  void resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 30), () {
      if (!_disposed) onInactivityTimeout?.call();
    });
  }

  // ── Sync (Late Joiner / Reconnection) ──────────────────────────────────────

  Future<void> _syncAuctionState() async {
    // Kanal modu: hostId (sellerId) varsa önce kanal sync'ini dene
    final hostId = ad?.userId;
    if (hostId != null) {
      try {
        final res = await ApiClient().get(
          '/api/livekit/channel/sync',
          params: {'hostId': hostId},
        );
        if (res.statusCode == 200 && !_disposed) {
          final data = res.data as Map<String, dynamic>;
          final newActiveAdId = data['activeAdId']?.toString();
          // Sadece gerçek bir kanal aktifse işle; null ise klasik sync'e düş
          if (newActiveAdId != null) {
            final auction = data['auction'] as Map<String, dynamic>?;
            state = state.copyWith(
              activeAdId: newActiveAdId,
              isAuctionActive: auction?['isAuctionActive'] == true,
              liveHighestBid: (auction?['highestBid'] as num?)?.toDouble(),
            );
            return;
          }
        }
      } catch (_) {
        // Kanal sync başarısız — klasik sync'e düş
      }
    }

    // Klasik mod fallback
    try {
      final res = await ApiClient().get('/api/livekit/sync', params: {'adId': adId});
      if (res.statusCode != 200 || _disposed) return;
      final data = res.data as Map<String, dynamic>;
      state = state.copyWith(
        isAuctionActive: data['isAuctionActive'] == true,
        liveHighestBid: (data['highestBid'] as num?)?.toDouble(),
      );
    } catch (_) {
      // Sync hatası kritik değil — DataChannel eventleri UI'yı güncel tutmaya devam eder
    }
  }

  /// Odaya bağlandıktan sonra bir kez çağrılır.
  /// İlk sync'i tetikler ve RoomReconnectedEvent için dinleyici kurar.
  void setupSync() {
    final room = _room;
    if (room == null) return;

    _syncAuctionState(); // Late joiner initial snapshot

    _roomEventUnsubscribe?.call();
    _roomEventUnsubscribe = room.events.listen((event) {
      if (event is RoomReconnectedEvent) {
        _syncAuctionState();
      }
    });
  }

  void _resetMessageTimer() {
    Timer(const Duration(seconds: 4), () {
      if (_disposed) return;
      final msgs = List<EphemeralMessage>.from(state.messages);
      if (msgs.isNotEmpty) msgs.removeAt(0);
      state = state.copyWith(messages: msgs);
    });
  }

  // ── Reactions ──────────────────────────────────────────────────────────────

  void addReaction(String emoji) {
    if (_disposed) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
    final updated = [...state.reactions, FloatingReaction(id: id, emoji: emoji)];
    if (updated.length > 20) updated.removeAt(0);
    state = state.copyWith(reactions: updated);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (_disposed) return;
      state = state.copyWith(
        reactions: state.reactions.where((r) => r.id != id).toList(),
      );
    });
  }

  void sendReaction(String emoji) {
    final roomState = ref.read(liveRoomProvider(adId));
    final room = roomState.room;
    final isDisconnected = room?.connectionState.name == 'disconnected' ||
        (room == null && !roomState.isConnecting);
    if (isDisconnected) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - state.lastReactionTime < 500) return;
    state = state.copyWith(lastReactionTime: now);

    if (room?.localParticipant == null) return;
    final payload = jsonEncode({'type': 'REACTION', 'emoji': emoji});
    try {
      room!.localParticipant!.publishData(utf8.encode(payload));
      addReaction(emoji);
    } catch (e) {
      debugPrint('Reaction send error: $e');
    }
  }

  // ── Stage ──────────────────────────────────────────────────────────────────

  void requestStage(BuildContext ctx) {
    final roomState = ref.read(liveRoomProvider(adId));
    final room = roomState.room;
    if (room?.localParticipant == null) return;
    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Kullanıcı girişi gerekli.')));
      return;
    }
    final payload = jsonEncode({
      'type': 'REQUEST_STAGE',
      'userId': currentUser.id,
      'userName': currentUser.name,
    });
    try {
      room!.localParticipant!.publishData(utf8.encode(payload));
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
            content: Text('Sahneye katılma isteği gönderildi!',
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      debugPrint('Stage request error: $e');
    }
  }

  /// Odadan KOPMADAN sahne yetkisini bırakır.
  /// Kamera ve mikrofonu kapatır; disconnect() ASLA çağrılmaz.
  Future<void> _revertToViewer() async {
    final room = ref.read(liveRoomProvider(adId)).room;
    if (room?.localParticipant != null) {
      await room!.localParticipant!.setCameraEnabled(false).catchError((_) {});
      await room.localParticipant!.setMicrophoneEnabled(false).catchError((_) {});
    }
    if (!_disposed) {
      state = state.copyWith(isGuest: false, isReconnectingForStage: false);
    }
  }

  /// Host tarafından sahne daveti kabul edildiğinde çağrılır.
  /// Backend'e POST /api/livekit/stage { action: 'accept' } gönderir,
  /// ardından kamera ve mikrofonu açar — disconnect/reconnect YOK.
  Future<void> acceptStageInvite(BuildContext ctx) async {
    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) return;
    try {
      final res = await ApiClient().post('/api/livekit/stage', data: {
        'adId': adId,
        'targetIdentity': currentUser.id,
        'action': 'accept',
      });
      if ((res.statusCode == 200 || res.statusCode == 201) && !_disposed) {
        final room = ref.read(liveRoomProvider(adId)).room;
        if (room?.localParticipant != null) {
          await room!.localParticipant!.setCameraEnabled(true);
          await room.localParticipant!.setMicrophoneEnabled(true);
        }
        state = state.copyWith(isGuest: true);
      }
    } catch (e) {
      debugPrint('acceptStageInvite error: $e');
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Sahneye katılınamadı.')));
      }
    }
  }

  Future<void> handleKick() async {
    onKicked?.call();
    await _revertToViewer();
  }

  /// İzleyici kendi isteğiyle sahneden iner.
  /// Backend'e revoke isteği gönderir; backend updateParticipant + STAGE_UPDATE broadcast yapar.
  Future<void> leaveStage() async {
    final currentUser = ref.read(authProvider).user;
    if (currentUser != null) {
      try {
        await ApiClient().post('/api/livekit/stage', data: {
          'adId': adId,
          'targetIdentity': currentUser.id,
          'action': 'revoke',
        });
      } catch (_) {}
    }
    await _revertToViewer();
  }

  // ── Bid velocity ───────────────────────────────────────────────────────────

  void recordBidVelocity() {
    final now = DateTime.now();
    final updated = [...state.recentBids, now]
        .where((t) => now.difference(t).inSeconds <= 5)
        .toList();
    state = state.copyWith(recentBids: updated);
    Haptics.vibrate(HapticsType.heavy);

    if (updated.length >= 3 && !state.isHypeMode) {
      state = state.copyWith(isHypeMode: true);
      onPulseStart?.call();
      _hypeTimer?.cancel();
      _hypeTimer = Timer(const Duration(seconds: 5), () {
        if (_disposed) return;
        state = state.copyWith(isHypeMode: false);
        onPulseStop?.call();
      });
    } else if (state.isHypeMode) {
      _hypeTimer?.cancel();
      _hypeTimer = Timer(const Duration(seconds: 5), () {
        if (_disposed) return;
        state = state.copyWith(isHypeMode: false);
        onPulseStop?.call();
      });
    }
  }

  // ── Chat ───────────────────────────────────────────────────────────────────

  Future<void> sendChatMessage(String text) async {
    if (text.isEmpty) return;
    final censoredText = ProfanityFilter.censor(text);
    final currentUser = ref.read(authProvider).user;
    final roomState = ref.read(liveRoomProvider(adId));
    if (roomState.room != null) {
      final name = roomState.room!.localParticipant?.name;
      final payload = jsonEncode({
        'type': 'CHAT',
        'text': censoredText,
        'senderName': name,
        'senderId': currentUser?.id,
      });
      await roomState.room!.localParticipant?.publishData(utf8.encode(payload));
      handleDataChannelMessage(utf8.encode(payload), null);
    }
  }

  // ── Bid ────────────────────────────────────────────────────────────────────

  Future<void> placeBid(double amount, BuildContext ctx) async {
    state = state.copyWith(bidLoading: true);
    await Haptics.vibrate(HapticsType.medium);
    // Kanal modunda aktif ürünün adId'sini kullan; yoksa klasik adId
    final effectiveAdId = state.activeAdId ?? adId;
    final hostId = ad?.userId;
    try {
      await ApiClient().post('/api/livekit/bid', data: {
        'adId': effectiveAdId,
        'amount': amount.toInt(),
        // channelHostId yalnızca kanal modunda gönderilir (activeAdId != null)
        // Klasik/hızlı canlı yayında gönderilmez — Lua script'in kanal kontrolü tetiklenmesin
        if (state.activeAdId != null && hostId != null) 'channelHostId': hostId,
      });

      ref.invalidate(adDetailProvider(effectiveAdId));
      await Haptics.vibrate(HapticsType.success);
      if (!_disposed) {
        ScaffoldMessenger.of(ctx).clearSnackBars();
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('teqlifiniz iletildi! 🎉'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      await Haptics.vibrate(HapticsType.error);
      String message = 'teqlif iletilemedi.';
      
      if (e is DioException) {
        final errorMsg = e.response?.data?['error']?.toString();
        if (errorMsg != null) {
          // The API now returns Turkish messages, so we can use them directly.
          // We keep the mapping as a fallback if the API returns English or specific codes.
          if (errorMsg.contains('higher than the current highest bid')) {
            message = 'Teklifiniz en yüksek tekliften düşük.';
          } else if (errorMsg.contains('başlatılmadı')) {
            message = 'Açık arttırma henüz başlatılmadı.';
          } else {
            message = errorMsg;
          }
        }
      } else {
        message = e.toString().replaceFirst('Exception: ', '');
      }

      if (!_disposed) {
        ScaffoldMessenger.of(ctx).clearSnackBars();
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (!_disposed) state = state.copyWith(bidLoading: false);
    }
  }

  // ── Data channel ───────────────────────────────────────────────────────────

  void handleDataChannelMessage(List<int> data, RemoteParticipant? p) {
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
          ref.read(liveRoomProvider(adId).notifier).disconnect();
          return;
        } else if (type == 'INVITE_TO_STAGE') {
          final targetIdentity = decoded['targetIdentity'] ?? decoded['targetUserId'];
          final currentUser = ref.read(authProvider).user;
          if (currentUser != null && targetIdentity == currentUser.id) {
            onShowInviteDialog?.call();
          }
          return;
        } else if (type == 'KICK_FROM_STAGE') {
          // Eski DataChannel tabanlı kick — yeni mimaride STAGE_UPDATE kullanılır.
          // Geriye dönük uyumluluk için korunur.
          final targetIdentity = decoded['targetIdentity'] ?? decoded['targetUserId'];
          final currentUser = ref.read(authProvider).user;
          if (currentUser != null && targetIdentity == currentUser.id) {
            handleKick(); // _revertToViewer() — disconnect YOK
          }
          return;
        } else if (type == 'STAGE_UPDATE') {
          // Backend, updateParticipant çağrısı sonrası tüm odaya broadcast eder.
          final action = decoded['action']?.toString();
          final identity = decoded['identity']?.toString();
          final currentUser = ref.read(authProvider).user;
          // Sahneden çıkarıldıysak (kicked veya izin alındıysa): cam/mic kapat, disconnect YOK
          if (action == 'left' && identity != null &&
              identity == currentUser?.id && state.isGuest) {
            handleKick();
          }
          return;
        } else if (type == 'AUCTION_START') {
          state = state.copyWith(isAuctionActive: true);
          onShowSystemMessage?.call('📣 AÇIK ARTTIRMA BAŞLADI!', Colors.green);
          return;
        } else if (type == 'AUCTION_RESET') {
          final msgs = List<EphemeralMessage>.from(state.messages);
          msgs.add(EphemeralMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: '📣 Yeni Ürün Açık Arttırmada!',
            senderName: 'Sistem',
            timestamp: DateTime.now(),
          ));
          state = state.copyWith(
            liveHighestBid: null, // Reset to null to fallback to AdModel price
            isSold: false,
            showSoldOverlay: false,
            soldWinnerName: null,
            soldFinalPrice: null,
            isAuctionActive: false,
            countdownValue: null,
            messages: msgs,
          );
          ref.invalidate(adDetailProvider(adId)); // Refresh starting price
          onShowSystemMessage?.call(
              '📣 Yeni Ürün Açık Arttırmada!', Colors.orange);
          return;
        } else if (type == 'AUCTION_END') {
          state = state.copyWith(isAuctionActive: false);
          onShowSystemMessage?.call(
              '📣 AÇIK ARTTIRMA DURDURULDU', Colors.orange);
          return;
        } else if (type == 'AUCTION_SOLD') {
          final winner = _formatSenderName(decoded['winnerName']?.toString());
          final price = (decoded['price'] as num?)?.toDouble() ?? 0.0;
          if (!_disposed) {
            state = state.copyWith(
              isSold: true,
              showSoldOverlay: true,
              soldWinnerName: winner,
              soldFinalPrice: price,
              isAuctionActive: false,
            );
            onPlayConfetti?.call();
          }
          return;
        } else if (type == 'AUCTION_ENDED') {
          final winner = _formatSenderName(decoded['winner']?.toString());
          final amount = (decoded['amount'] as num?)?.toDouble();
          state = state.copyWith(isAuctionActive: false);
          _showFinalizationOverlayAlert(winner, amount);
          onPlayConfetti?.call();
          return;
        } else if (type == 'REACTION') {
          addReaction(decoded['emoji']?.toString() ?? '❤️');
          return;
        } else if (type == 'SALE_FINALIZED') {
          final winnerName = _formatSenderName(decoded['winnerName']?.toString());
          final amount = decoded['amount'] != null
              ? (decoded['amount'] as num).toDouble()
              : null;
          _showFinalizationOverlayAlert(winnerName, amount);
          return;
        } else if (type == 'CHAT') {
          final chatText = decoded['text']?.toString() ?? '';
          final censoredText = ProfanityFilter.censor(chatText);
          final chatSender = decoded['senderName']?.toString();
          final msgs = List<EphemeralMessage>.from(state.messages);
          msgs.add(EphemeralMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: censoredText,
            senderName: _formatSenderName(chatSender),
            timestamp: DateTime.now(),
          ));
          if (msgs.length > 5) msgs.removeAt(0);
          state = state.copyWith(messages: msgs);
          _resetMessageTimer();
          return;
        } else if (type == 'ITEM_PINNED') {
          final pinnedAdId = decoded['adId']?.toString();
          final startingBid = (decoded['startingBid'] as num?)?.toDouble();
          if (pinnedAdId == null) return;
          state = state.copyWith(
            activeAdId: pinnedAdId,
            liveHighestBid: startingBid,
            liveHighestBidderName: null,
            isAuctionActive: true,
            isSold: false,
            showSoldOverlay: false,
            soldWinnerName: null,
            soldFinalPrice: null,
            showFinalizationOverlay: false,
            finalizedWinnerName: null,
            finalizedAmount: null,
            countdownValue: null,
          );
          onShowSystemMessage?.call('📦 Yeni ürün sahnede! Teklif verebilirsiniz.', Colors.blue);
          return;
        } else if (type == 'NEW_BID' || type == 'BID_ACCEPTED') {
          // Kanal modunda: payload'daki adId, şu an aktif ürünle eşleşmiyorsa yut
          final payloadAdId = decoded['adId']?.toString();
          final currentActiveAdId = state.activeAdId;
          if (payloadAdId != null && currentActiveAdId != null && payloadAdId != currentActiveAdId) {
            return;
          }
          final amount = (decoded['amount'] as num).toDouble();
          final nextBid = amount + (ad?.minBidStep ?? 1000);
          final bidderName = decoded['bidderName']?.toString();
          state = state.copyWith(
            liveHighestBid: amount,
            liveHighestBidderName: bidderName ?? state.liveHighestBidderName,
          );
          onUpdateBidText?.call(_formatPrice(nextBid));
          if (type == 'BID_ACCEPTED' &&
              (decoded['bidderId'] ?? decoded['bidderIdentity']) == ref.read(authProvider).user?.id) {
            Haptics.vibrate(HapticsType.success);
          }
          recordBidVelocity();
          ref.invalidate(adDetailProvider(adId));
          return;
        } else if (type == 'BID_REJECTED') {
          if ((decoded['bidderId'] ?? decoded['bidderIdentity']) == ref.read(authProvider).user?.id) {
            Haptics.vibrate(HapticsType.error);
          }
          ref.invalidate(adDetailProvider(adId));
          return;
        } else if (type == 'COUNTDOWN') {
          final value = int.tryParse(decoded['value']?.toString() ?? '');
          if (!_disposed && value != null) {
            state = state.copyWith(countdownValue: value);
            if (value == 0) {
              Future.delayed(const Duration(seconds: 2), () {
                if (!_disposed) state = state.copyWith(countdownValue: null);
              });
            }
          }
          return;
        } else if (type == 'SYNC_STATE_RESPONSE') {
          if (!_disposed) {
            final isSold = decoded['isSold'] == true;
            final hostSuppliedWinner =
                decoded['highestBidderName']?.toString();
            final hostHighestBid = (decoded['highestBid'] as num?)?.toDouble() ?? 0.0;
            
            // PHASE 21: Protect against downgrading the local bid (race condition)
            final currentLocalBid = state.liveHighestBid ?? 0.0;
            final finalBid = (hostHighestBid > currentLocalBid) ? hostHighestBid : currentLocalBid;

            var newState = state.copyWith(
              isAuctionActive: decoded['isAuctionActive'] == true,
              liveHighestBid: finalBid > 0 ? finalBid : null,
              isSold: isSold,
            );
            if (isSold) {
              newState = newState.copyWith(
                showSoldOverlay: true,
                soldWinnerName:
                    hostSuppliedWinner ?? state.soldWinnerName,
              );
            }
            state = newState;
          }
          return;
        } else {
          // Unknown or unhandled internal message type
          return;
        }
      }
    } catch (e) {
      // Fallback to normal text chat or skip
    }

    final censoredMessage = ProfanityFilter.censor(message);
    final msgs = List<EphemeralMessage>.from(state.messages);
    msgs.add(EphemeralMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: censoredMessage,
      senderName: _formatSenderName(p?.name),
      timestamp: DateTime.now(),
    ));
    if (msgs.length > 3) msgs.removeAt(0);
    state = state.copyWith(messages: msgs);
    _resetMessageTimer();
  }

  // ── Finalization overlay ───────────────────────────────────────────────────

  void _showFinalizationOverlayAlert(String? winnerName, double? amount) {
    if (_disposed) return;
    state = state.copyWith(
      finalizedWinnerName: winnerName ?? 'Katılımcı',
      finalizedAmount: amount,
      showFinalizationOverlay: true,
    );
    final chatPayload = jsonEncode({
      'type': 'CHAT',
      'text':
          '🎉 Tebrikler! ${_formatSenderName(winnerName)} bu ürünü ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(amount ?? 0)} bedel ile kazandı!',
      'senderName': 'SİSTEM',
    });
    handleDataChannelMessage(utf8.encode(chatPayload), null);
    Future.delayed(const Duration(seconds: 10), () {
      if (!_disposed) state = state.copyWith(showFinalizationOverlay: false);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final viewerControllerProvider =
    StateNotifierProvider.family<ViewerController, ViewerState, String>(
  (ref, adId) {
    // We can read the initial ad from adDetailProvider or elsewhere
    // but for the controller, we just need the stable ID.
    // For the initial state, we'll try to find the ad in the cache
    final ad = ref.read(adDetailProvider(adId)).value;
    return ViewerController(adId, ref, initialAd: ad);
  },
);
