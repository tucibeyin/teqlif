import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/ad.dart';
import '../../../../core/providers/live_room_provider.dart';
import '../../controllers/live_arena_host_controller.dart';

/// Top HUD + auction stats bar — portrait and landscape variants.
class HostTopDashboard extends ConsumerWidget {
  final bool isLandscape;
  final AdModel ad;
  final VoidCallback onEndStream;
  final VoidCallback onCancelTopBid;
  final VoidCallback onAcceptBid;

  const HostTopDashboard({
    super.key,
    required this.isLandscape,
    required this.ad,
    required this.onEndStream,
    required this.onCancelTopBid,
    required this.onAcceptBid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hostControllerProvider(ad.id));
    final controller = ref.read(hostControllerProvider(ad.id).notifier);

    return Column(
      children: [
        // ── Header row ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // CANLI pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.redAccent.withOpacity(0.3),
                          blurRadius: 8)
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sensors, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text('CANLI',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Viewer count pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                        '${ref.read(liveRoomProvider(ad.id)).viewerCount}',
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
              onPressed: onEndStream,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ── Stats bar ──
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
                  ? _LandscapeStatsInner(state: state, ad: ad,
                      onInvite: (id) => controller.inviteToStage(id, context))
                  : _PortraitStatsInner(state: state, ad: ad,
                      onInvite: (id) => controller.inviteToStage(id, context)),
            ),
          ),
        ),
        // ── Accept / Reject row (only when bids exist and auction active) ──
        if (state.bids.isNotEmpty && state.isAuctionActive)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: OutlinedButton(
                    onPressed: onCancelTopBid,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.1),
                      side: BorderSide(
                          color: Colors.redAccent.withOpacity(0.3)),
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
                    onPressed: onAcceptBid,
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
}

// ── Portrait stats inner ──────────────────────────────────────────────────────

class _PortraitStatsInner extends StatelessWidget {
  final HostState state;
  final AdModel ad;
  final void Function(String userId) onInvite;

  const _PortraitStatsInner(
      {required this.state, required this.ad, required this.onInvite});

  String _formatPrice(double amount) =>
      NumberFormat.decimalPattern('tr').format(amount);

  @override
  Widget build(BuildContext context) {
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
                state.bids.isNotEmpty
                    ? '₺${_formatPrice(state.bids.first.amount)}'
                    : 'Henüz teqlif Yok',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: state.isAuctionActive
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: state.isAuctionActive
                          ? Colors.green.withOpacity(0.5)
                          : Colors.orange.withOpacity(0.5)),
                ),
                child: Text(
                  state.isAuctionActive
                      ? 'AÇIK ARTTIRMA AKTİF'
                      : 'AÇIK ARTTIRMA DURDURULDU',
                  style: TextStyle(
                      color: state.isAuctionActive
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5),
                ),
              ),
              if (state.bids.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Text(state.bids.first.userLabel,
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    if (state.bids.first.userId != null)
                      GestureDetector(
                        onTap: () => onInvite(state.bids.first.userId!),
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
        if (ad.buyItNowPrice != null) ...[
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
              Text('₺${_formatPrice(ad.buyItNowPrice!)}',
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
}

// ── Landscape stats inner ─────────────────────────────────────────────────────

class _LandscapeStatsInner extends StatelessWidget {
  final HostState state;
  final AdModel ad;
  final void Function(String userId) onInvite;

  const _LandscapeStatsInner(
      {required this.state, required this.ad, required this.onInvite});

  String _formatPrice(double amount) =>
      NumberFormat.decimalPattern('tr').format(amount);

  @override
  Widget build(BuildContext context) {
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
                    state.bids.isNotEmpty
                        ? '₺${_formatPrice(state.bids.first.amount)}'
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: state.isAuctionActive
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: state.isAuctionActive
                          ? Colors.green.withOpacity(0.5)
                          : Colors.orange.withOpacity(0.5)),
                ),
                child: Text(
                  state.isAuctionActive
                      ? 'AÇIK ARTTIRMA AKTİF'
                      : 'AÇIK ARTTIRMA DURDURULDU',
                  style: TextStyle(
                    color: state.isAuctionActive
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (state.bids.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(state.bids.first.userLabel,
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ]
            ],
          ),
        ),
        if (ad.buyItNowPrice != null) ...[
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
              Text('₺${_formatPrice(ad.buyItNowPrice!)}',
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
}
