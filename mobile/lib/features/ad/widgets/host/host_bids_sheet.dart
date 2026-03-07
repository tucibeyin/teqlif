import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/live_arena_host_controller.dart';
import '../../models/live_bid.dart';

/// Modal bottom sheet displaying incoming bids with accept / cancel actions.
class HostBidsSheet extends ConsumerWidget {
  final String providerKey;

  const HostBidsSheet({super.key, required this.providerKey});

  String _formatPrice(double amount) {
    // Simple Turkish format (comma as thousands separator)
    return amount.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hostControllerProvider(providerKey));
    final controller = ref.read(hostControllerProvider(providerKey).notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Container(
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
                children: const [
                  Icon(Icons.gavel, color: Color(0xFF00B4CC)),
                  SizedBox(width: 12),
                  Text('Gelen teqlifler',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: state.bids.isEmpty
                  ? const Center(
                      child: Text('Henüz teqlif gelmedi.',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: state.bids.length,
                      itemBuilder: (ctx, i) {
                        final bid = state.bids[i];
                        return _BidListItem(
                          bid: bid,
                          formatPrice: _formatPrice,
                          onAccept: () => controller.acceptBidFromSheet(
                              bid, context, () => Navigator.of(context).pop()),
                          onInvite: bid.userId != null
                              ? () =>
                                  controller.inviteToStage(bid.userId!, context)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BidListItem extends StatelessWidget {
  final LiveBid bid;
  final String Function(double) formatPrice;
  final VoidCallback onAccept;
  final VoidCallback? onInvite;

  const _BidListItem({
    required this.bid,
    required this.formatPrice,
    required this.onAccept,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
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
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bid.userLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                Text('₺${formatPrice(bid.amount)}',
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
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Sat',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                if (onInvite != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.mic,
                        color: Colors.blueAccent, size: 22),
                    onPressed: onInvite,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
