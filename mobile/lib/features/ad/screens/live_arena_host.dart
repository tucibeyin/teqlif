import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/ad.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/live_room_provider.dart';
import '../controllers/live_arena_host_controller.dart';
import '../providers/ad_detail_provider.dart';
import '../widgets/floating_reactions.dart';
import '../widgets/host/host_auction_input.dart';
import '../widgets/host/host_bids_sheet.dart';
import '../widgets/host/host_camera_view.dart';
import '../widgets/host/host_chat_flow.dart';
import '../widgets/host/host_controls_widget.dart';
import '../widgets/host/host_finalization_overlay.dart';
import '../widgets/host/host_sold_overlay.dart';
import '../widgets/host/host_top_dashboard.dart';

// ─────────────────────────────────────────────────────────────────────────────

class LiveArenaHost extends ConsumerStatefulWidget {
  final AdModel? ad;
  final String? channelHostId;

  const LiveArenaHost({super.key, this.ad, this.channelHostId})
      : assert(ad != null || channelHostId != null,
            'Either ad or channelHostId must be provided');

  @override
  ConsumerState<LiveArenaHost> createState() => _LiveArenaHostState();
}

// ─────────────────────────────────────────────────────────────────────────────

class _LiveArenaHostState extends ConsumerState<LiveArenaHost>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Provider / room key ───────────────────────────────────────────────────
  String get _providerKey => widget.channelHostId != null
      ? 'channel:${widget.channelHostId}'
      : widget.ad!.id;

  // ── Saf UI state (TickerProvider / drag) ──────────────────────────────────
  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFocus = FocusNode();
  Offset? _pipOffset;
  late ConfettiController _confettiController;
  late AnimationController _pulseController;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );

    // Wire animation callbacks into the controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl =
          ref.read(hostControllerProvider(_providerKey).notifier);
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
    });

    // Connect to room as Host
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus.isGranted && micStatus.isGranted) {
        final notifier =
            ref.read(liveRoomProvider(_providerKey).notifier);
        await notifier.connect(true, hostId: widget.channelHostId ?? widget.ad?.userId);

        final room = ref.read(liveRoomProvider(_providerKey)).room;
        if (room != null) {
          final ctrl =
              ref.read(hostControllerProvider(_providerKey).notifier);
          
          // PHASE 21: Sync initial state from Redis before handling messages
          await ctrl.syncInitialState();

          room.events.listen((event) {
            if (event is TrackSubscribedEvent ||
                event is TrackUnsubscribedEvent ||
                event is ParticipantConnectedEvent ||
                event is ParticipantDisconnectedEvent ||
                event is TrackMutedEvent ||
                event is TrackUnmutedEvent) {
              if (mounted) setState(() {});
            }
            if (event is DataReceivedEvent) {
              ctrl.handleDataChannelMessage(
                  event.data, event.participant);
            }
          });

          // Signal backend that we are LIVE (skip for pure channel mode)
          if (widget.channelHostId == null && widget.ad != null) {
            try {
              await ApiClient().post('/api/ads/${widget.ad!.id}/live',
                  data: {
                    'isLive': true,
                    'liveKitRoomId': widget.ad!.id,
                  });
            } catch (e) {
              debugPrint('Failed to set isLive to true: $e');
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Yayın başlatmak için kamera ve mikrofon izni gereklidir.')),
          );
          context.go('/home');
        }
      }
    });
  }

  @override
  void deactivate() {
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
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _chatCtrl.dispose();
    _chatFocus.dispose();
    _pulseController.dispose();
    _confettiController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused) {
      ref.read(liveRoomProvider(_providerKey).notifier).disconnect();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Auto-pop when room disconnects
    ref.listen(liveRoomProvider(_providerKey), (previous, next) {
      if (previous?.room != null &&
          next.room == null &&
          !next.isConnecting) {
        if (mounted) context.go('/home');
      }
    });

    final roomState = ref.watch(liveRoomProvider(_providerKey));
    final room = roomState.room;
    final hostState = ref.watch(hostControllerProvider(_providerKey));
    final controller =
        ref.read(hostControllerProvider(_providerKey).notifier);

    // Extract tracks
    VideoTrack? localVideoTrack;
    VideoTrack? guestTrack;
    String? guestIdentity;

    if (room != null) {
      for (var pub
          in room.localParticipant?.videoTrackPublications ?? []) {
        if (pub.track != null) {
          localVideoTrack = pub.track as VideoTrack?;
          break;
        }
      }
      // Evrensel filtre: kamerası VEYA mikrofonu açık olan ilk remote katılımcı = aktif sahne misafiri.
      // Yayın yapmayan (izleyen) katılımcılar atlanır.
      for (final p in room.remoteParticipants.values) {
        if (p.isCameraEnabled() || p.isMicrophoneEnabled()) {
          guestIdentity = p.identity;
          for (var pub in p.videoTrackPublications) {
            if (pub.track != null) {
              guestTrack = pub.track as VideoTrack?;
              break;
            }
          }
          break; // ilk aktif yayıncı = misafir
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
                return _buildPortraitLayout(
                    roomState, room, localVideoTrack, guestTrack,
                    guestIdentity, hostState, controller);
              } else {
                return _buildLandscapeLayout(
                    roomState, room, localVideoTrack, guestTrack,
                    guestIdentity, hostState, controller);
              }
            },
          ),
          // Finalization overlay (short-lived)
          HostFinalizationOverlay(
            show: hostState.showFinalizationOverlay,
            winnerName: hostState.finalizedWinnerName,
            amount: hostState.finalizedAmount,
          ),
          // SATILDI overlay (permanent until closed)
          if (hostState.isSold && hostState.showSoldOverlay)
            HostSoldOverlay(
              soldWinnerName: hostState.soldWinnerName,
              soldFinalPrice: hostState.soldFinalPrice,
              isQuickLive: widget.channelHostId != null ||
                  widget.ad?.description == 'Hızlı Canlı Yayın (Ghost Ad)',
              confettiController: _confettiController,
              onClose: controller.hideSoldOverlay,
              onResetAuction: () => controller.resetAuction(context),
            ),
        ],
      ),
    );
  }

  // ── Portrait layout ───────────────────────────────────────────────────────

  Widget _buildPortraitLayout(
    dynamic roomState,
    Room? room,
    VideoTrack? localVideoTrack,
    VideoTrack? guestTrack,
    String? guestIdentity,
    HostState hostState,
    HostController controller,
  ) {
    final screenSize = MediaQuery.of(context).size;
    if (guestTrack != null) {
      _pipOffset ??= Offset(screenSize.width - 116, 220);
    }

    final currentUserId = ref.read(authProvider).user?.id;

    return Stack(
      children: [
        // Camera / loading
        HostCameraView(
          roomState: roomState,
          room: room,
          localVideoTrack: localVideoTrack,
          isCameraEnabled: hostState.isCameraEnabled,
        ),
        // Top HUD + stats
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HostTopDashboard(
                isLandscape: false,
                providerKey: _providerKey,
                ad: widget.ad,
                onEndStream: () => controller.endLiveStream(context),
                onCancelTopBid: hostState.bids.isNotEmpty
                    ? () => controller.cancelBid(
                        hostState.bids.first.id, context)
                    : () {},
                onAcceptBid: () =>
                    controller.acceptBidFromDashboard(context),
              ),
            ),
          ),
        ),
        // Draggable PiP (guest)
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
              child: GuestTrackPiP(
                guestTrack: guestTrack,
                guestIdentity: guestIdentity,
                onKick: () =>
                    controller.kickGuest(guestIdentity!, context),
              ),
            ),
          ),
        // Floating reactions
        FloatingReactionsOverlay(reactions: hostState.reactions),
        // Bottom chat + controls
        SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.only(left: 16, bottom: 8),
                      child: HostChatFlow(
                        messages: hostState.messages,
                        height: 150,
                        currentUserId: currentUserId,
                        onModerate: (id, name) => _showModMenu(id, name, controller),
                        onInvite: (id) =>
                            controller.inviteToStage(id, context),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.only(right: 16, bottom: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        HostControlsWidget(
                          room: room,
                          providerKey: _providerKey,
                          onShowBidsSheet: _showBidsSheet,
                        ),
                        const SizedBox(height: 12),
                        ReactionButtons(
                            onReact: controller.sendReaction),
                      ],
                    ),
                  ),
                ],
              ),
              HostAuctionInput(
                providerKey: _providerKey,
                chatCtrl: _chatCtrl,
                chatFocus: _chatFocus,
                pulseAnimation: _pulseController,
                countdown: hostState.countdown,
                onStartCountdown: controller.startCountdown,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Landscape layout ──────────────────────────────────────────────────────

  Widget _buildLandscapeLayout(
    dynamic roomState,
    Room? room,
    VideoTrack? localVideoTrack,
    VideoTrack? guestTrack,
    String? guestIdentity,
    HostState hostState,
    HostController controller,
  ) {
    final currentUserId = ref.read(authProvider).user?.id;

    return Row(
      children: [
        // Left: video
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              HostCameraView(
                roomState: roomState,
                room: room,
                localVideoTrack: localVideoTrack,
                isCameraEnabled: hostState.isCameraEnabled,
              ),
              FloatingReactionsOverlay(reactions: hostState.reactions),
            ],
          ),
        ),
        // Right: dashboard
        Container(
          width: 380,
          color: Colors.black.withOpacity(0.5),
          child: SafeArea(
            left: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: HostTopDashboard(
                    isLandscape: true,
                    providerKey: _providerKey,
                    ad: widget.ad,
                    onEndStream: () =>
                        controller.endLiveStream(context),
                    onCancelTopBid: hostState.bids.isNotEmpty
                        ? () => controller.cancelBid(
                            hostState.bids.first.id, context)
                        : () {},
                    onAcceptBid: () =>
                        controller.acceptBidFromDashboard(context),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // Guest PiP (top-right)
                      if (guestTrack != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(
                              width: 100,
                              height: 140,
                              child: GuestTrackPiP(
                                guestTrack: guestTrack,
                                guestIdentity: guestIdentity,
                                onKick: () => controller.kickGuest(
                                    guestIdentity!, context),
                              ),
                            ),
                          ),
                        ),
                      // Controls + reactions (bottom-right)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              right: 16, bottom: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              HostControlsWidget(
                                room: room,
                                providerKey: _providerKey,
                                onShowBidsSheet: _showBidsSheet,
                              ),
                              const SizedBox(height: 12),
                              ReactionButtons(
                                  onReact: controller.sendReaction),
                            ],
                          ),
                        ),
                      ),
                      // Chat (bottom-left)
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              left: 16, right: 80, bottom: 8),
                          child: HostChatFlow(
                            messages: hostState.messages,
                            height: 120,
                            currentUserId: currentUserId,
                            onModerate: (id, name) =>
                                _showModMenu(id, name, controller),
                            onInvite: (id) =>
                                controller.inviteToStage(id, context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                HostAuctionInput(
                  providerKey: _providerKey,
                  chatCtrl: _chatCtrl,
                  chatFocus: _chatFocus,
                  pulseAnimation: _pulseController,
                  countdown: hostState.countdown,
                  onStartCountdown: controller.startCountdown,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showBidsSheet() {
    final controller =
        ref.read(hostControllerProvider(_providerKey).notifier);
    controller.readBids();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HostBidsSheet(providerKey: _providerKey),
    );
  }

  void _showModMenu(
      String identity, String name, HostController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '$name Yönet',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.mic_off,
                  color: Colors.orangeAccent),
              title: const Text('Sustur',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                controller.moderateUser(
                    identity, name, 'mute', context);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.gavel, color: Colors.redAccent),
              title: const Text('Odadan At',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                controller.moderateUser(
                    identity, name, 'kick', context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
