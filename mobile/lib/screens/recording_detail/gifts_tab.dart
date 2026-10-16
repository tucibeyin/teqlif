import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/recording.dart';
import '../../services/image_cache_manager.dart';
import '../../services/localization_service.dart';
import '../public_profile_screen.dart';
import 'widgets/gift_bars_painter.dart';
import 'widgets/modal_sheet.dart';
import 'widgets/rd_formatters.dart';

enum _GiftSort { mostTeqlik, newest }

class GiftsTab extends StatelessWidget {
  final RecordingGifts gifts;
  final TranslationPack loc;

  const GiftsTab({
    super.key,
    required this.gifts,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    if (gifts.events.isEmpty) {
      return Center(
        child: Text(
          loc.t('recordingDetailGifts'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _GiftSummaryCard(
          gifts: gifts,
          loc: loc,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _GiftSendersModal(events: gifts.events, loc: loc),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          loc.t('recordingGiftDistribution'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        GiftBarsChart(gifts: gifts, lang: loc.lang),
      ],
    );
  }
}

class _GiftSummaryCard extends StatelessWidget {
  final RecordingGifts gifts;
  final TranslationPack loc;
  final VoidCallback? onTap;

  const _GiftSummaryCard({
    required this.gifts,
    required this.loc,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withAlpha(26),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.card_giftcard,
                  color: Color(0xFFF97316), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rdTeqliq(gifts.totalTeqlik, loc.lang),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  Text(
                    loc.t('giftSenderCount')
                        .replaceAll('{count}', '${gifts.senderCount}'),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, color: AppColors.textTertiary(context)),
          ],
        ),
      ),
    );
  }
}

class _GiftSendersModal extends StatefulWidget {
  final List<RecordingGiftEvent> events;
  final TranslationPack loc;

  const _GiftSendersModal({required this.events, required this.loc});

  @override
  State<_GiftSendersModal> createState() => _GiftSendersModalState();
}

class _GiftSendersModalState extends State<_GiftSendersModal> {
  _GiftSort _sort = _GiftSort.mostTeqlik;

  List<RecordingGiftEvent> get _sorted {
    final list = [...widget.events];
    switch (_sort) {
      case _GiftSort.mostTeqlik:
        list.sort((a, b) => b.costTeqlik.compareTo(a.costTeqlik));
      case _GiftSort.newest:
        list.sort((a, b) {
          if (a.sentAt == null || b.sentAt == null) return 0;
          return b.sentAt!.compareTo(a.sentAt!);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return RecordingModalSheet(
      title: widget.loc.t('recordingDetailGifts'),
      children: [
        _SortHeader<_GiftSort>(
          title: widget.loc
              .t('giftSenderCount')
              .replaceAll('{count}', '${widget.events.length}'),
          current: _sort,
          options: [
            (_GiftSort.mostTeqlik, widget.loc.t('recordingSortMostGifts')),
            (_GiftSort.newest,     widget.loc.t('recordingSortNewest')),
          ],
          onChanged: (v) => setState(() => _sort = v),
        ),
        const SizedBox(height: 8),
        ..._sorted.map((e) => _GiftEventRow(event: e, loc: widget.loc)),
      ],
    );
  }
}

class _GiftEventRow extends StatelessWidget {
  final RecordingGiftEvent event;
  final TranslationPack loc;
  const _GiftEventRow({required this.event, required this.loc});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PublicProfileScreen(username: event.username)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundImage: event.avatarUrl != null
                  ? CachedNetworkImageProvider(
                      event.avatarUrl!,
                      cacheKey: 'user_${event.userId}_avatar',
                      cacheManager: TeqlifCacheManager(),
                    )
                  : null,
              child: event.avatarUrl == null
                  ? const Icon(Icons.person, size: 15)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${event.username}',
                      style: TextStyle(color: AppColors.textPrimary(context))),
                  Text(event.giftName,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(context))),
                ],
              ),
            ),
            Text(
              rdTeqliq(event.costTeqlik, loc.lang),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFFF97316),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortHeader<T> extends StatelessWidget {
  final String title;
  final T current;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _SortHeader({
    required this.title,
    required this.current,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (options.length > 1)
          PopupMenuButton<T>(
            initialValue: current,
            onSelected: onChanged,
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  options.firstWhere((o) => o.$1 == current).$2,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textTertiary(context)),
                ),
                const SizedBox(width: 2),
                Icon(Icons.sort,
                    size: 16, color: AppColors.textTertiary(context)),
              ],
            ),
            itemBuilder: (_) => options
                .map((o) => PopupMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
          ),
      ],
    );
  }
}
