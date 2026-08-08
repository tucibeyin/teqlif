import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/commerce_activity.dart';
import '../../../services/localization_service.dart';
import '../../../utils/number_formatter.dart';
import '../../../utils/username_color.dart';

const double kCommerceActivityH = 5 * 36.0 + 44; // 224px — matches original

class CommerceActivityOverlay extends ConsumerWidget {
  final List<CommerceEventGroup> groups;
  final ScrollController scrollController;
  final void Function(String username)? onUsernameTap;

  const CommerceActivityOverlay({
    super.key,
    required this.groups,
    required this.scrollController,
    this.onUsernameTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.read(localizationProvider);
    final totalCount =
        groups.fold<int>(0, (s, g) => s + g.events.length);

    // Flatten groups into list items: each group = 1 header + n event rows
    // Groups are already newest-first (index 0 = newest)
    final items = <_ListItem>[];
    for (final g in groups) {
      items.add(_GroupHeaderItem(group: g));
      for (final e in g.events) {
        items.add(_EventItem(event: e, groupType: g.groupType));
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Text(
                      loc.t('lblCommerceActivity'),
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$totalCount',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                  height: 1, thickness: 1, color: Color(0x14FFFFFF)),
              // Scrollable list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 4),
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[i];
                    if (item is _GroupHeaderItem) {
                      return _buildGroupHeader(item.group, loc);
                    } else if (item is _EventItem) {
                      // Rank within its group: find position among siblings
                      final groupItem = items
                          .take(i)
                          .whereType<_GroupHeaderItem>()
                          .lastOrNull;
                      // count events before this one in the same group
                      int rank = 0;
                      for (int j = i - 1; j >= 0; j--) {
                        if (items[j] is _GroupHeaderItem) break;
                        rank++;
                      }
                      return _buildEventRow(
                          item.event, item.groupType, rank, loc);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader(
      CommerceEventGroup g, TranslationPack loc) {
    final isAuction = g.groupType == 'auction';
    final label = isAuction
        ? loc.t('lblCommerceGroupAuction')
        : loc.t('lblCommerceGroupDs');
    final color = isAuction
        ? const Color(0xFF06B6D4)
        : const Color(0xFF818CF8); // indigo for DS
    final separator = g.title != null ? ' · ${g.title}' : '';
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.white.withValues(alpha: 0.04),
      child: Text(
        '$label$separator',
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildEventRow(CommerceEvent event, String groupType,
      int rank, TranslationPack loc) {
    if (event is AuctionBidEvent) {
      return _BidRow(
          event: event,
          rank: rank,
          onUsernameTap: onUsernameTap);
    } else if (event is DsPurchaseEvent) {
      return _DsPurchaseRow(
          event: event,
          onUsernameTap: onUsernameTap);
    }
    return const SizedBox.shrink();
  }
}

// ── Bid Row ─────────────────────────────────────────────────────────────────

class _BidRow extends StatelessWidget {
  final AuctionBidEvent event;
  final int rank;
  final void Function(String)? onUsernameTap;

  const _BidRow({
    required this.event,
    required this.rank,
    this.onUsernameTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 0;
    return GestureDetector(
      onTap: onUsernameTap != null
          ? () => onUsernameTap!(event.actor)
          : null,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '#${rank + 1}',
                style: TextStyle(
                  color: isFirst
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFF475569),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '@${event.actor}',
                style: TextStyle(
                  color: usernameColor(event.actor),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  decoration: onUsernameTap != null
                      ? TextDecoration.underline
                      : null,
                  decorationColor:
                      usernameColor(event.actor).withValues(alpha: 0.5),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              TeqNumberFormatter.format(event.amount,
                  fieldKey: 'price', unit: '₺'),
              style: const TextStyle(
                color: Color(0xFF4ADE80),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── DS Purchase Row ──────────────────────────────────────────────────────────

class _DsPurchaseRow extends StatelessWidget {
  final DsPurchaseEvent event;
  final void Function(String)? onUsernameTap;

  const _DsPurchaseRow({required this.event, this.onUsernameTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onUsernameTap != null
          ? () => onUsernameTap!(event.actor)
          : null,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              child: Text(
                '🛍',
                style: TextStyle(fontSize: 10),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      '@${event.actor}',
                      style: TextStyle(
                        color: usernameColor(event.actor),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        decoration: onUsernameTap != null
                            ? TextDecoration.underline
                            : null,
                        decorationColor: usernameColor(event.actor)
                            .withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (event.quantity > 1) ...[
                    const SizedBox(width: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF818CF8)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${event.quantity}×',
                        style: const TextStyle(
                          color: Color(0xFF818CF8),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              TeqNumberFormatter.format(event.unitPrice,
                  fieldKey: 'price', unit: '₺'),
              style: const TextStyle(
                color: Color(0xFF4ADE80),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Internal list item types ─────────────────────────────────────────────────

sealed class _ListItem {}

class _GroupHeaderItem extends _ListItem {
  final CommerceEventGroup group;
  _GroupHeaderItem({required this.group});
}

class _EventItem extends _ListItem {
  final CommerceEvent event;
  final String groupType;
  _EventItem({required this.event, required this.groupType});
}
