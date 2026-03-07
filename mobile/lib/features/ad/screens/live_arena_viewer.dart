import 'dart:convert';
import 'dart:ui';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/models/ad.dart';
import '../../../core/providers/live_room_provider.dart';
import '../controllers/live_arena_viewer_controller.dart';
import '../providers/ad_detail_provider.dart';
import '../widgets/floating_reactions.dart';
import '../widgets/viewer/viewer_chat_flow.dart';
import '../widgets/viewer/viewer_console.dart';
import '../widgets/viewer/viewer_finalization_overlay.dart';
import '../widgets/viewer/viewer_sold_overlay.dart';
import '../widgets/viewer/viewer_sidebar.dart';
import '../widgets/viewer/viewer_top_header.dart';

// ─────────────────────────────────────────────────────────────────────────────

class LiveArenaViewer extends ConsumerStatefulWidget {
  final AdModel? ad;
  final String? channelHostId;

  const LiveArenaViewer({super.key, this.ad, this.channelHostId})
      : assert(ad != null || channelHostId != null,
            'Either ad or channelHostId must be provided');

  @override
  ConsumerState<LiveArenaViewer> createState() => _LiveArenaViewerState();
}

// ─────────────────────────────────────────────────────────────────────────────

class _LiveArenaViewerState extends ConsumerState<LiveArenaViewer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Provider / room key ───────────────────────────────────────────────────
  String get _providerKey => widget.channelHostId != null
      ? 'channel:${widget.channelHostId}'
      : widget.ad!.id;

  static final _placeholderAd = AdModel(
    id: '',
    title: 'Kanal Yayını',
    description: '',
    price: 0,
    status: 'active',
    images: const [],
    views: 0,
    createdAt: DateTime(2024),
    userId: '',
  );

  // ── TickerProvider-dependent (cannot move to controller) ──────────────────
  late AnimationController _pulseController;
  late ConfettiController _confettiController;

  // ── Form controllers ──────────────────────────────────────────────────────
  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFocus = FocusNode();
  final TextEditingController _bidCtrl = TextEditingController();

  // ── Pure UI state ─────────────────────────────────────────────────────────
  bool _uiVisible = true;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );

    // Wire animation & dialog callbacks into controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl =
          ref.read(viewerControllerProvider(_providerKey).notifier);
      ctrl.onPlayConfetti = () {
        if (mounted) _confettiController.play();
      };
      ctrl.onPulseStart = () {
        if (mounted) _pulseController.repeat(reverse: true);
      };
      ctrl.onPulseStop = () {
        if (mounted) {
          _pulseController.stop();
          _pulseController.value = 1.0;
        }
      };
      ctrl.onUpdateBidText = (text) {
        if (mounted) _bidCtrl.text = text;
      };
      ctrl.onShowInviteDialog = () {
        if (mounted) _showInviteDialog();
      };
      ctrl.onKicked = () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sahneden çıkarıldınız.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      };
      ctrl.onShowSystemMessage = _showSystemMessage;
      ctrl.onInactivityTimeout = () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hareketsizlik modu aktif (AdaptiveStream).'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.black54,
            ),
          );
        }
      };
      ctrl.resetInactivityTimer();
    });

    // Connect to room, then trigger initial sync and reconnect listener
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(liveRoomProvider(_providerKey).notifier).connect(false,
          hostId: widget.channelHostId ?? widget.ad?.userId);
      if (mounted) {
        ref.read(viewerControllerProvider(_providerKey).notifier).setupSync();
      }
    });
  }

  @override
  void deactivate() {
    // Schedule after build frame to avoid ZonedGuarded crash
    final key = _providerKey;
    final container = ProviderScope.containerOf(context, listen: false);
    Future.microtask(() {
      try {
        container.read(liveRoomProvider(key).notifier).disconnect();
        container.invalidate(adDetailProvider(key));
      } catch (_) {}
    });
    super.deactivate();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _confettiController.dispose();
    _chatCtrl.dispose();
    _chatFocus.dispose();
    _bidCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // LiveKit adaptive stream pauses video when view is hidden.
    } else if (state == AppLifecycleState.resumed) {
      // Resume
    }
  }

  // ── Room event listener ───────────────────────────────────────────────────

  void _onRoomEvent(RoomEvent event) {
    if (event is TrackMutedEvent || event is TrackUnmutedEvent ||
        event is TrackSubscribedEvent || event is TrackUnsubscribedEvent) {
      if (mounted) setState(() {});
    }
    if (event is DataReceivedEvent) {
      ref
          .read(viewerControllerProvider(_providerKey).notifier)
          .handleDataChannelMessage(event.data, event.participant);
    }
  }

  void _onInteraction() {
    ref.read(viewerControllerProvider(_providerKey).notifier).resetInactivityTimer();
  }

  // ── System message ────────────────────────────────────────────────────────

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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.7,
            left: 50,
            right: 50),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── Modal dialogs (BuildContext required) ─────────────────────────────────

  void _showInviteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Sahneye Davet!'),
        content: const Text(
            'Yayıncı sizi sahneye davet ediyor. Kameranız ve mikrofonunuz açılacak. Kabul ediyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Reddet', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Sıfır Kopma: odadan ayrılmadan yetki alınır, kamera/mikrofon açılır.
              await ref
                  .read(viewerControllerProvider(_providerKey).notifier)
                  .acceptStageInvite(ctx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B4CC)),
            child: const Text('Kabul Et',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAdDetailsSheet() {
    final ad = widget.ad;
    if (ad == null) return;
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
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
              Text(ad.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (ad.startingBid != null)
                Text(
                    'Başlangıç Fiyatı: ${_formatPrice(ad.startingBid!)}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00B4CC))),
              const SizedBox(height: 24),
              const Text('Açıklama',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(ad.description,
                  style:
                      const TextStyle(fontSize: 16, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  void _showBidInputSheet(AdModel? currentAd) {
    final ad = currentAd ?? widget.ad ?? _placeholderAd;
    final viewerState = ref.read(viewerControllerProvider(_providerKey));
    if (!viewerState.isAuctionActive) {
      _showSystemMessage('Açık arttırma henüz başlatılmadı', Colors.orange);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
              color: Color(0xFF131722),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(30))),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              const Text('TEQLİF VER',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              const Text('Teklif vermek istediğiniz tutarı girin.',
                  style:
                      TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white10)),
                child: TextField(
                  controller: _bidCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                      border: InputBorder.none,
                      prefixText: '₺ ',
                      prefixStyle: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: ([
                  ad.minBidStep.toInt(),
                  100,
                  250,
                  500,
                  1000
                ].toSet().toList()
                      ..sort())
                    .map((inc) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 2),
                            child: ElevatedButton(
                              onPressed: () {
                                final currentPrice = ref
                                        .read(viewerControllerProvider(
                                            _providerKey))
                                        .liveHighestBid ??
                                    ad.highestBidAmount ??
                                    ad.startingBid ??
                                    0;
                                _bidCtrl.text = _formatPrice(
                                    (currentPrice + inc).toDouble());
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF00B4CC),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12))),
                              child: Text('+$inc',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _placeBidSlide();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4CC),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15))),
                child: const Text('TEKLİFİ ONAYLA',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chat & Bid (own form controllers) ────────────────────────────────────

  Future<void> _sendChatMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    await ref
        .read(viewerControllerProvider(_providerKey).notifier)
        .sendChatMessage(text);
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
      await Haptics.vibrate(HapticsType.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen geçerli bir teqlif girin')),
        );
      }
      return;
    }
    if (mounted) {
      await ref
          .read(viewerControllerProvider(_providerKey).notifier)
          .placeBid(amount, context);
    }
    _bidCtrl.clear();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatPrice(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Reactive listener for room-wide events & life-cycle
    ref.listen(liveRoomProvider(_providerKey), (previous, next) {
      final viewerState = ref.read(viewerControllerProvider(_providerKey));
      
      // 1. Auto-pop when room is disconnected (unless switching roles)
      if (!viewerState.isReconnectingForStage &&
          previous?.room != null &&
          next.room == null &&
          !next.isConnecting) {
        if (mounted) context.pop();
        return;
      }

      // 2. Attach data listener to new room instances
      if (previous?.room != next.room && next.room != null) {
          next.room!.events.listen(_onRoomEvent);
          // Auto-sync state request on new join (viewer only)
          if (next.room != null && !viewerState.isGuest) {
             try {
               final syncPayload = jsonEncode({'type': 'SYNC_STATE_REQUEST'});
               next.room!.localParticipant?.publishData(utf8.encode(syncPayload));
             } catch (_) {}
          }
      }
    });

    final viewerState = ref.watch(viewerControllerProvider(_providerKey));
    final roomState = ref.watch(liveRoomProvider(_providerKey));
    final room = roomState.room;
    // Resolve the effective ad: pinned item in channel mode, or constructor ad
    final activeAdId = viewerState.activeAdId;
    final adAsync = ref.watch(adDetailProvider(activeAdId ?? widget.ad?.id ?? ''));
    final currentAd = adAsync.valueOrNull ?? widget.ad;

    final isDisconnected = !viewerState.isReconnectingForStage &&
        (room?.connectionState.name == 'disconnected' ||
            (room == null && !roomState.isConnecting));

    // Track extraction
    VideoTrack? hostTrack;
    VideoTrack? guestTrack;
    if (room != null) {
      final allRemote = room.remoteParticipants.values.toList();
      for (var p in allRemote) {
        VideoTrack? t;
        for (var pub in p.videoTrackPublications) {
          if (pub.track != null && pub.track is VideoTrack) {
            t = pub.track as VideoTrack;
            break;
          }
        }
        if (t != null) {
          if (p.identity == (widget.channelHostId ?? widget.ad?.userId)) {
            hostTrack = t;
          } else if (p.isCameraEnabled() || p.isMicrophoneEnabled()) {
            // This is likely our invited guest who is now publishing
            guestTrack = t;
          }
        }
      }
      // PHASE 21: Improved host track extraction. 
      // If we didn't find the host by identity, we should only fall back if the first participant is NOT the guest we already found.
      if (hostTrack == null && allRemote.isNotEmpty) {
        final candidate = allRemote.first;
        // If this candidate identity matches our guestTrack identity, don't use it as host.
        bool isAlreadyGuest = false;
        if (guestTrack != null) {
           for (var p in allRemote) {
             for (var pub in p.videoTrackPublications) {
               if (pub.track == guestTrack) {
                 if (p == candidate) isAlreadyGuest = true;
                 break;
               }
             }
           }
        }

        if (!isAlreadyGuest) {
          for (var pub in candidate.videoTrackPublications) {
            if (pub.track != null && pub.track is VideoTrack) {
              hostTrack = pub.track as VideoTrack;
              break;
            }
          }
        }
      }
      if (viewerState.isGuest && room.localParticipant != null) {
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
            // 1. Video Player & States
            if (isDisconnected)
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.videocam_off_outlined,
                        color: Colors.white54, size: 64),
                    SizedBox(height: 16),
                    Text('Yayın Sona Erdi',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Yayıncı canlı yayını kapattı.',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 16)),
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
                      CircularProgressIndicator(
                          color: Color(0xFF00B4CC)),
                      SizedBox(height: 24),
                      Text('Arena\'ya Katılınıyor...',
                          style: TextStyle(
                              color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              )
            else if (hostTrack != null && !hostTrack.muted)
              SizedBox.expand(
                child: VideoTrackRenderer(hostTrack,
                    fit: VideoViewFit.contain),
              )
            else if (hostTrack != null && hostTrack.muted)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam_off,
                        size: 80, color: Colors.white54),
                    SizedBox(height: 16),
                    Text('Kamera Kapalı',
                        style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            else
              const Center(
                  child: Text('Yayın bekleniyor...',
                      style: TextStyle(color: Colors.white54))),

            // Guest PiP
            if (guestTrack != null)
              Positioned(
                top: 200,
                right: 16,
                width: 100,
                height: 140,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.white.withOpacity(0.5),
                                width: 2),
                            color: Colors.black),
                        child: guestTrack.muted
                            ? const Center(
                                child: Icon(Icons.videocam_off,
                                    color: Colors.white54))
                            : VideoTrackRenderer(guestTrack,
                                fit: VideoViewFit.cover),
                      ),
                    ),
                    if (viewerState.isGuest)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => ref
                              .read(viewerControllerProvider(_providerKey)
                                  .notifier)
                              .leaveStage(),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // Countdown overlay
            if (viewerState.countdownValue != null &&
                viewerState.countdownValue! > 0)
              Positioned.fill(
                child: Center(
                  child: TweenAnimationBuilder<double>(
                      key: ValueKey(viewerState.countdownValue),
                      tween: Tween(begin: 0.5, end: 1.0),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) {
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                                color: viewerState.countdownValue! <= 10
                                    ? Colors.red.withOpacity(0.9)
                                    : Colors.orange.withOpacity(0.9),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        viewerState.countdownValue! <= 10
                                            ? Colors.red.withOpacity(0.6)
                                            : Colors.orange
                                                .withOpacity(0.6),
                                    blurRadius: 50,
                                  )
                                ]),
                            child: Center(
                              child: Text(
                                '${viewerState.countdownValue}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 64,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                ),
              ),

            // 2. UI overlay (swipeable)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              left: _uiVisible ? 0 : MediaQuery.of(context).size.width,
              right: _uiVisible ? 0 : -MediaQuery.of(context).size.width,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_uiVisible,
                child: !isDisconnected
                    ? SafeArea(
                        child: OrientationBuilder(
                          builder: (context, orientation) {
                            if (orientation == Orientation.portrait) {
                              return _buildPortraitLayout(
                                  currentAd, isDisconnected);
                            } else {
                              return _buildLandscapeLayout(
                                  currentAd, isDisconnected, viewerState);
                            }
                          },
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // 3. SATILDI overlay
            if (viewerState.isSold && viewerState.showSoldOverlay)
              ViewerSoldOverlay(
                soldWinnerName: viewerState.soldWinnerName,
                soldFinalPrice: viewerState.soldFinalPrice,
                confettiController: _confettiController,
                onClose: () => ref
                    .read(viewerControllerProvider(_providerKey).notifier)
                    .hideSoldOverlay(),
              ),

            // 4. Finalization overlay
            ViewerFinalizationOverlay(
              show: viewerState.showFinalizationOverlay,
              winnerName: viewerState.finalizedWinnerName,
              amount: viewerState.finalizedAmount,
            ),
          ],
        ),
      ),
    );
  }

  // ── Portrait Layout ───────────────────────────────────────────────────────

  Widget _buildPortraitLayout(AdModel? currentAd, bool isDisconnected) {
    final viewerState = ref.read(viewerControllerProvider(_providerKey));
    final effectiveAd = currentAd ?? widget.ad;
    return Stack(
      children: [
        ViewerTopHeader(ad: effectiveAd ?? _placeholderAd, providerKey: _providerKey),
        ViewerSidebar(
          ad: effectiveAd ?? _placeholderAd,
          isPortrait: true,
          onShowAdDetails: _showAdDetailsSheet,
          providerKey: _providerKey,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: FloatingReactionsOverlay(
                reactions: viewerState.reactions),
          ),
        ),
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ViewerChatFlow(ad: effectiveAd ?? _placeholderAd, height: 140, providerKey: _providerKey),
              ViewerConsole(
                ad: currentAd ?? widget.ad ?? _placeholderAd,
                chatCtrl: _chatCtrl,
                bidCtrl: _bidCtrl,
                chatFocus: _chatFocus,
                isDisconnected: isDisconnected,
                onShowBidSheet: () => _showBidInputSheet(currentAd ?? widget.ad ?? _placeholderAd),
                onSendChat: _sendChatMessage,
                onPlaceBid: _placeBidSlide,
                providerKey: _providerKey,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Landscape Layout ──────────────────────────────────────────────────────

  Widget _buildLandscapeLayout(
      AdModel? currentAd, bool isDisconnected, ViewerState viewerState) {
    final effectiveLandAd = currentAd ?? widget.ad ?? _placeholderAd;
    final double nextBid;
    if (viewerState.liveHighestBid != null) {
      nextBid = viewerState.liveHighestBid! + effectiveLandAd.minBidStep;
    } else if (!effectiveLandAd.isAuction && !viewerState.isAuctionActive) {
      nextBid = effectiveLandAd.price;
    } else {
      nextBid = (effectiveLandAd.highestBidAmount ??
              effectiveLandAd.startingBid ??
              effectiveLandAd.price) +
          effectiveLandAd.minBidStep;
    }

    return Row(
      children: [
        Expanded(
          flex: 7,
          child: Stack(
            children: [
              ViewerTopHeader(ad: effectiveLandAd, providerKey: _providerKey),
              ViewerSidebar(
                ad: effectiveLandAd,
                isPortrait: false,
                onShowAdDetails: _showAdDetailsSheet,
                providerKey: _providerKey,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: FloatingReactionsOverlay(
                      reactions: viewerState.reactions),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 300,
          color: Colors.black.withOpacity(0.4),
          child: SafeArea(
            left: false,
            child: Column(
              children: [
                if (viewerState.isAuctionActive)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: Colors.white.withOpacity(0.05))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('SIRADAKİ TEKLİF',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        Text(_formatPrice(nextBid),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: (isDisconnected ||
                                  !viewerState.isAuctionActive ||
                                  viewerState.bidLoading)
                              ? null
                              : () {
                                  _bidCtrl.text = _formatPrice(nextBid);
                                  _placeBidSlide();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            elevation: 8,
                          ),
                          child: viewerState.bidLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('TEKLİF VER',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            effectiveLandAd.minBidStep.toInt(),
                            250,
                            500,
                            1000
                          ]
                              .map((inc) => Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: OutlinedButton(
                                        onPressed: () {
                                          final currentPrice =
                                              viewerState.liveHighestBid ??
                                                  effectiveLandAd.highestBidAmount ??
                                                  effectiveLandAd.startingBid ??
                                                  0;
                                          _bidCtrl.text = _formatPrice(
                                              (currentPrice + inc)
                                                  .toDouble());
                                          _placeBidSlide();
                                        },
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(
                                              color: Colors.white
                                                  .withOpacity(0.2)),
                                          foregroundColor: Colors.white,
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      8)),
                                        ),
                                        child: Text('+$inc',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.bold)),
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: ShaderMask(
                          shaderCallback: (bounds) =>
                              const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                Colors.transparent,
                                Colors.white,
                                Colors.white
                              ],
                                  stops: [
                                0.0,
                                0.4,
                                1.0
                              ]).createShader(bounds),
                          blendMode: BlendMode.dstIn,
                          child: Builder(builder: (context) {
                            final messages = ref.watch(
                                viewerControllerProvider(_providerKey)
                                    .select((s) => s.messages));
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              reverse: true,
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final msg = messages[
                                    messages.length - 1 - index];
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                  child: RichText(
                                      text: TextSpan(children: [
                                    TextSpan(
                                        text: '${msg.senderName}: ',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white70,
                                            fontSize: 13)),
                                    TextSpan(
                                        text: msg.text,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13))
                                  ])),
                                );
                              },
                            );
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                    color:
                                        Colors.white.withOpacity(0.1),
                                    borderRadius:
                                        BorderRadius.circular(22)),
                                child: TextField(
                                  controller: _chatCtrl,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13),
                                  decoration: const InputDecoration(
                                      hintText: 'Mesaj...',
                                      hintStyle: TextStyle(
                                          color: Colors.white54),
                                      border: InputBorder.none,
                                      contentPadding:
                                          EdgeInsets.symmetric(
                                              horizontal: 16)),
                                  onSubmitted: (_) => _sendChatMessage(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            viewerState.isAuctionActive
                                ? IconButton(
                                    icon: const Icon(Icons.edit_note,
                                        color: Colors.white70),
                                    onPressed: () =>
                                        _showBidInputSheet(currentAd),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                            Icons.favorite_border,
                                            color: Colors.white,
                                            size: 24),
                                        onPressed: () => ref
                                            .read(viewerControllerProvider(
                                                    _providerKey)
                                                .notifier)
                                            .sendReaction('❤️'),
                                      ),
                                      const Text('Beğen',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight:
                                                  FontWeight.bold)),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
