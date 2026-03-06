import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/ad.dart';
import '../../../../core/providers/live_room_provider.dart';
import '../../controllers/live_arena_viewer_controller.dart';
import '../../providers/ad_detail_provider.dart';

class ViewerTopHeader extends ConsumerWidget {
  final AdModel ad;

  const ViewerTopHeader({super.key, required this.ad});

  String _formatPrice(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewerState = ref.watch(viewerControllerProvider(ad));
    final adAsync = ref.watch(adDetailProvider(ad.id));
    final currentAd = adAsync.value ?? ad;
    final viewerCount =
        ref.watch(liveRoomProvider(ad.id).select((s) => s.viewerCount));

    final displayPrice = viewerState.isAuctionActive
        ? (viewerState.liveHighestBid ??
            currentAd.highestBidAmount ??
            currentAd.startingBid ??
            0)
        : (currentAd.isAuction
            ? (viewerState.liveHighestBid ??
                currentAd.highestBidAmount ??
                currentAd.startingBid ??
                0)
            : (currentAd.buyItNowPrice ?? 0));

    final label = viewerState.isAuctionActive
        ? 'GÜNCEL TEKLİF: '
        : (currentAd.isAuction ? 'BAŞLANGIÇ: ' : 'FİYAT: ');

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // CANLI pill
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter:
                              ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color:
                                      Colors.redAccent.withOpacity(0.5),
                                  width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                    radius: 4,
                                    backgroundColor: Colors.redAccent,
                                    child: Container(
                                        width: 2,
                                        height: 2,
                                        decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle))),
                                const SizedBox(width: 8),
                                const Text('CANLI',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                        letterSpacing: 1)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Viewer Count Pill
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter:
                              ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.visibility_outlined,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  '$viewerCount',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                      onPressed: () {
                        ref
                            .read(liveRoomProvider(ad.id).notifier)
                            .disconnect();
                        if (context.mounted) context.pop();
                      },
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                        Text(
                            _formatPrice(
                                (displayPrice as num).toDouble()),
                            style: const TextStyle(
                                color: Color(0xFF00B4CC),
                                fontWeight: FontWeight.w900,
                                fontSize: 16)),
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
}
