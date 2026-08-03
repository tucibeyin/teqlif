import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api.dart';
import '../services/localization_service.dart';
import 'public_profile_screen.dart';
import '../models/call_history_item.dart';
import 'viewmodels/call_history_view_model.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  static const _filters = ['all', 'missed', 'incoming', 'outgoing'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _filters.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('callHistoryTitle')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: false,
          tabs: [
            Tab(text: loc.t('callHistoryAll')),
            Tab(text: loc.t('callHistoryMissed')),
            Tab(text: loc.t('callHistoryIncoming')),
            Tab(text: loc.t('callHistoryOutgoing')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: _filters
            .map((f) => _FilteredList(
                  filter: f,
                  emptyLabel: loc.t('callHistoryEmpty'),
                ))
            .toList(),
      ),
    );
  }
}

// ── Per-tab list ──────────────────────────────────────────────────────────────

class _FilteredList extends ConsumerStatefulWidget {
  final String filter;
  final String emptyLabel;

  const _FilteredList({
    required this.filter,
    required this.emptyLabel,
  });

  @override
  ConsumerState<_FilteredList> createState() => _FilteredListState();
}

class _FilteredListState extends ConsumerState<_FilteredList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      ref.read(callHistoryProvider(widget.filter).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(callHistoryProvider(widget.filter));

    return stateAsync.when(
      data: (state) {
        if (state.items.isEmpty) {
          return Center(
            child: Text(
              widget.emptyLabel,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.read(callHistoryProvider(widget.filter).notifier).refresh(),
          child: ListView.separated(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: state.items.length + (state.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              if (i == state.items.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              return _CallTile(item: state.items[i]);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) {
        final loc = ref.watch(localizationProvider);
        final colorScheme = Theme.of(context).colorScheme;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: colorScheme.error, size: 48),
              const SizedBox(height: 12),
              Text(loc.t('errorNetworkMessage'), style: TextStyle(color: colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => ref.read(callHistoryProvider(widget.filter).notifier).refresh(),
                child: Text(loc.t('callHistoryRetry')),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Single call row ───────────────────────────────────────────────────────────

class _CallTile extends ConsumerWidget {
  final CallHistoryItem item;
  const _CallTile({required this.item});

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatTime(TranslationPack loc, DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final localDate = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(localDate).inDays;

    final timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    if (diffDays == 0) {
      return '${loc.t('callHistoryToday')} $timeStr';
    } else if (diffDays == 1) {
      return '${loc.t('callHistoryYesterday')} $timeStr';
    } else {
      final d = local.day.toString().padLeft(2, '0');
      final m = local.month.toString().padLeft(2, '0');
      return '$d/$m/${local.year} $timeStr';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = ref.watch(localizationProvider);

    final isMissed = item.isMissed || item.status == 'missed';
    final isOutgoing = item.isOutgoing;
    final duration = _formatDuration(item.durationSeconds);
    final timeLabel = _formatTime(loc, item.startedAt);

    // Direction icon + color
    final (IconData dirIcon, Color dirColor) = switch (item.status) {
      'missed' => (Icons.call_missed, Colors.red),
      'rejected' => (Icons.call_missed_outgoing, cs.outline),
      _ when isOutgoing => (Icons.call_made, const Color(0xFF22C55E)),
      _ => (Icons.call_received, const Color(0xFF22C55E)),
    };

    // Status label
    final String statusLabel = switch (item.status) {
      'missed' => loc.t('callHistoryStatusMissed'),
      'rejected' => isOutgoing ? loc.t('callHistoryStatusDeclined') : loc.t('callHistoryStatusYouDeclined'),
      'ended' when (item.durationSeconds ?? 0) > 0 => duration,
      'ended' => isOutgoing ? loc.t('callHistoryStatusNoAnswer') : loc.t('callHistoryStatusNotAnswered'),
      'calling' => loc.t('callHistoryStatusCancelled'),
      _ => item.status,
    };

    return ListTile(
      onTap: () {
        if (item.otherUsername != null && item.otherUsername!.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PublicProfileScreen(
                username: item.otherUsername!,
                userId: item.otherUserId,
              ),
            ),
          );
        }
      },
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: cs.surfaceContainerHighest,
            backgroundImage: item.otherAvatar != null &&
                    item.otherAvatar!.isNotEmpty
                ? CachedNetworkImageProvider(imgUrl(item.otherAvatar))
                : null,
            child: item.otherAvatar == null || item.otherAvatar!.isEmpty
                ? Text(
                    (item.otherUsername ?? '?')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: Icon(dirIcon, size: 16, color: dirColor),
            ),
          ),
        ],
      ),
      title: Text(
        item.otherUsername ?? loc.t('callHistoryUnknown'),
        style: TextStyle(
          fontWeight: isMissed ? FontWeight.bold : FontWeight.normal,
          color: isMissed ? Colors.red : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        statusLabel,
        style: TextStyle(
          fontSize: 13,
          color: isMissed ? Colors.red.withValues(alpha: 0.8) : cs.outline,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeLabel,
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
          const SizedBox(height: 4),
          Icon(Icons.info_outline, size: 16, color: cs.outlineVariant),
        ],
      ),
    );
  }
}
