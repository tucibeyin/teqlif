import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/ad.dart';
import '../../controllers/live_arena_viewer_controller.dart';

class ViewerConsole extends ConsumerWidget {
  final AdModel ad;
  final TextEditingController chatCtrl;
  final TextEditingController bidCtrl;
  final FocusNode chatFocus;
  final bool isDisconnected;
  final VoidCallback onShowBidSheet;
  final VoidCallback onSendChat;
  final VoidCallback onPlaceBid;

  const ViewerConsole({
    super.key,
    required this.ad,
    required this.chatCtrl,
    required this.bidCtrl,
    required this.chatFocus,
    required this.isDisconnected,
    required this.onShowBidSheet,
    required this.onSendChat,
    required this.onPlaceBid,
  });

  String _formatPrice(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewerState = ref.watch(viewerControllerProvider(ad.id));

    // Compute next bid amount
    final double nextBid;
    if (viewerState.liveHighestBid != null) {
      nextBid = viewerState.liveHighestBid! + ad.minBidStep;
    } else if (!ad.isAuction && !viewerState.isAuctionActive) {
      nextBid = ad.price;
    } else {
      nextBid = (ad.highestBidAmount ?? ad.startingBid ?? ad.price) +
          ad.minBidStep;
    }

    Widget buildPrimaryAction() {
      if (viewerState.isSold) {
        return Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: const Center(
              child: Text('BU ÜRÜN SATILMIŞTIR',
                  style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w900,
                      fontSize: 13)),
            ),
          ),
        );
      } else if (ad.isAuction || viewerState.isAuctionActive) {
        return Expanded(
          child: GestureDetector(
            onTap: (isDisconnected ||
                    !viewerState.isAuctionActive ||
                    viewerState.bidLoading)
                ? null
                : () {
                    if (bidCtrl.text.isEmpty) {
                      bidCtrl.text = _formatPrice(nextBid);
                    }
                    onPlaceBid();
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 56,
              decoration: BoxDecoration(
                gradient: viewerState.isAuctionActive
                    ? const LinearGradient(
                        colors: [Color(0xFFE50914), Color(0xFFB81D24)])
                    : LinearGradient(colors: [
                        Colors.grey.shade800,
                        Colors.grey.shade900
                      ]),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white30),
                boxShadow: viewerState.isAuctionActive
                    ? [
                        BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 15)
                      ]
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (viewerState.bidLoading)
                    const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            viewerState.isAuctionActive
                                ? Icons.gavel
                                : Icons.hourglass_empty,
                            color: viewerState.isAuctionActive
                                ? Colors.white
                                : Colors.white38,
                            size: 22),
                        const SizedBox(width: 8),
                        Text(
                          viewerState.isAuctionActive
                              ? 'TEKLİF VER: ${_formatPrice(nextBid)}'
                              : 'BEKLENİYOR',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.5),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      } else {
        // Fixed Price "Hemen Al"
        return Expanded(
          child: GestureDetector(
            onTap: isDisconnected
                ? null
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Hemen satın almak için ilan detayından işleme devam ediniz.'),
                          duration: Duration(seconds: 3)),
                    );
                    context.pop();
                  },
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white30),
                boxShadow: [
                  BoxShadow(
                      color: Colors.amber.withOpacity(0.3),
                      blurRadius: 10)
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart, color: Colors.black, size: 22),
                  SizedBox(width: 8),
                  Text('HEMEN AL',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        );
      }
    }

    Widget buildQuickBidButtons() {
      if (!ad.isAuction && !viewerState.isAuctionActive) {
        return const SizedBox.shrink();
      }
      final minStep = ad.minBidStep.toInt();
      final quickBids = {minStep, 100, 250, 500, 1000, 5000}.toList()
        ..sort();
      return Container(
        height: 48,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: quickBids
              .map((amount) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: !viewerState.isAuctionActive
                        ? null
                        : () {
                            final currentPrice = viewerState.liveHighestBid ??
                                ad.highestBidAmount ??
                                ad.startingBid ??
                                0;
                            bidCtrl.text =
                                _formatPrice((currentPrice + amount).toDouble());
                            onPlaceBid();
                          },
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            Color(0xFF00B4CC),
                            Color(0xFF008D9E)
                          ]),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    const Color(0xFF00B4CC).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Center(
                          child: Text('+$amount ₺',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 0.5)),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildQuickBidButtons(),
          Row(
            children: [
              buildPrimaryAction(),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: !viewerState.isAuctionActive ? null : onShowBidSheet,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: viewerState.isAuctionActive
                        ? Colors.white.withOpacity(0.1)
                        : Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: viewerState.isAuctionActive
                            ? Colors.white24
                            : Colors.white12),
                  ),
                  child: Icon(Icons.add,
                      color: viewerState.isAuctionActive
                          ? Colors.white
                          : Colors.white24,
                      size: 24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
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
                        controller: chatCtrl,
                        focusNode: chatFocus,
                        enabled: !isDisconnected,
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          hintText: 'Mesaj gönder...',
                          hintStyle: TextStyle(
                              color: Colors.black54, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        onSubmitted: (_) => onSendChat(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send,
                          color: Color(0xFF00B4CC)),
                      onPressed: isDisconnected ? null : onSendChat,
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
