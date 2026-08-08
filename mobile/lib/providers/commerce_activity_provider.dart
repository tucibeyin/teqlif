import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/commerce_activity.dart';
import '../services/stream_service.dart';

class CommerceActivityNotifier
    extends StateNotifier<List<CommerceEventGroup>> {
  CommerceActivityNotifier() : super([]);

  void addBidEvent(String bidder, double amount, String? itemName) {
    final groups = _mutableGroups();
    if (groups.isEmpty ||
        groups.first.groupType != 'auction' ||
        groups.first.title != itemName) {
      groups.insert(
        0,
        CommerceEventGroup(
          title: itemName,
          groupType: 'auction',
          events: [],
        ),
      );
    }
    final updated = List<CommerceEvent>.from(groups.first.events)
      ..insert(
        0,
        AuctionBidEvent(
          actor: bidder,
          amount: amount,
          createdAt: DateTime.now(),
        ),
      );
    groups[0] = groups.first.copyWith(events: updated);
    state = groups;
  }

  void addPurchaseEvent(
      String buyer, double price, int qty, String? title) {
    final groups = _mutableGroups();
    if (groups.isEmpty ||
        groups.first.groupType != 'ds' ||
        groups.first.title != title) {
      groups.insert(
        0,
        CommerceEventGroup(
          title: title,
          groupType: 'ds',
          events: [],
        ),
      );
    }
    final updated = List<CommerceEvent>.from(groups.first.events)
      ..insert(
        0,
        DsPurchaseEvent(
          actor: buyer,
          unitPrice: price,
          quantity: qty,
          createdAt: DateTime.now(),
        ),
      );
    groups[0] = groups.first.copyWith(events: updated);
    state = groups;
  }

  void resetGroups() => state = [];

  Future<void> loadHistory(int streamId) async {
    final items = await StreamService.fetchCommerceActivity(streamId);
    state = _buildGroups(items);
  }

  List<CommerceEventGroup> _buildGroups(
      List<Map<String, dynamic>> items) {
    // items are already sorted newest-first from backend
    final groups = <CommerceEventGroup>[];

    for (final item in items) {
      final type = item['event_type'] as String;
      final actor = item['actor'] as String? ?? '';
      final value = (item['value'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final groupTitle = item['group_title'] as String?;
      final createdAt = item['created_at'] != null
          ? DateTime.tryParse(item['created_at'] as String) ?? DateTime.now()
          : DateTime.now();

      final groupType = type == 'bid' ? 'auction' : 'ds';

      CommerceEvent event;
      if (type == 'bid') {
        event = AuctionBidEvent(
            actor: actor, amount: value, createdAt: createdAt);
      } else {
        event = DsPurchaseEvent(
            actor: actor,
            unitPrice: value,
            quantity: qty,
            createdAt: createdAt);
      }

      // Append to current group if same type+title, else start new group
      if (groups.isNotEmpty &&
          groups.last.groupType == groupType &&
          groups.last.title == groupTitle) {
        final existing = groups.last;
        groups[groups.length - 1] =
            existing.copyWith(events: [...existing.events, event]);
      } else {
        groups.add(CommerceEventGroup(
          title: groupTitle,
          groupType: groupType,
          events: [event],
        ));
      }
    }

    return groups;
  }

  List<CommerceEventGroup> _mutableGroups() =>
      List<CommerceEventGroup>.from(state);
}

final commerceActivityProvider = StateNotifierProvider.autoDispose
    .family<CommerceActivityNotifier, List<CommerceEventGroup>, int>(
  (ref, streamId) => CommerceActivityNotifier(),
);
