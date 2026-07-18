import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../config/api.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _CallHistoryItem {
  final int callId;
  final String status;
  final String role;
  final int? durationSeconds;
  final DateTime? startedAt;
  final int? otherUserId;
  final String? otherUsername;
  final String? otherAvatar;

  const _CallHistoryItem({
    required this.callId,
    required this.status,
    required this.role,
    this.durationSeconds,
    this.startedAt,
    this.otherUserId,
    this.otherUsername,
    this.otherAvatar,
  });

  factory _CallHistoryItem.fromMap(Map<String, dynamic> m) {
    final other = m['other_user'] as Map<String, dynamic>?;
    return _CallHistoryItem(
      callId: m['call_id'] as int,
      status: m['status'] as String,
      role: m['role'] as String,
      durationSeconds: m['duration_seconds'] as int?,
      startedAt: m['started_at'] != null
          ? DateTime.tryParse(m['started_at'] as String)
          : null,
      otherUserId: other?['id'] as int?,
      otherUsername: other?['username'] as String?,
      otherAvatar: other?['avatar'] as String?,
    );
  }

  bool get isMissed =>
      status == 'missed' || (status == 'ended' && role == 'callee' && (durationSeconds ?? 0) == 0);
  bool get isOutgoing => role == 'caller';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  static const _filters = ['all', 'missed', 'incoming', 'outgoing'];

  final Map<String, List<_CallHistoryItem>> _items = {
    'all': [],
    'missed': [],
    'incoming': [],
    'outgoing': [],
  };
  final Map<String, bool> _loading = {
    'all': false,
    'missed': false,
    'incoming': false,
    'outgoing': false,
  };
  final Map<String, bool> _hasMore = {
    'all': true,
    'missed': true,
    'incoming': true,
    'outgoing': true,
  };
  final Map<String, int> _page = {
    'all': 1,
    'missed': 1,
    'incoming': 1,
    'outgoing': 1,
  };
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _filters.length, vsync: this);
    _tabs.addListener(_onTabChange);
    _fetchPage('all');
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChange);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChange() {
    if (_tabs.indexIsChanging) return;
    final filter = _filters[_tabs.index];
    if (_items[filter]!.isEmpty && _hasMore[filter]! && !_loading[filter]!) {
      _fetchPage(filter);
    }
  }

  Future<void> _fetchPage(String filter, {bool refresh = false}) async {
    if (_loading[filter]! && !refresh) return;
    if (!_hasMore[filter]! && !refresh) return;

    if (refresh) {
      setState(() {
        _items[filter] = [];
        _page[filter] = 1;
        _hasMore[filter] = true;
        _errorMessage = null;
      });
    }

    setState(() => _loading[filter] = true);

    try {
      final token = await StorageService.getToken();
      final page = _page[filter]!;
      final uri = Uri.parse(
          '$kBaseUrl/calls/history?page=$page&per_page=20&filter=$filter');
      final resp = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final newItems = (data['items'] as List)
            .map((e) => _CallHistoryItem.fromMap(e as Map<String, dynamic>))
            .toList();

        setState(() {
          _items[filter] = [..._items[filter]!, ...newItems];
          _hasMore[filter] = data['has_more'] as bool;
          _page[filter] = page + 1;
          _loading[filter] = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _loading[filter] = false;
          _errorMessage = 'HTTP ${resp.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading[filter] = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.callHistoryTitle),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: false,
          tabs: [
            Tab(text: l.callHistoryAll),
            Tab(text: l.callHistoryMissed),
            Tab(text: l.callHistoryIncoming),
            Tab(text: l.callHistoryOutgoing),
          ],
        ),
      ),
      body: _errorMessage != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      color: colorScheme.error, size: 48),
                  const SizedBox(height: 12),
                  Text(_errorMessage!,
                      style: TextStyle(color: colorScheme.error)),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () {
                      final filter = _filters[_tabs.index];
                      _fetchPage(filter, refresh: true);
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: _filters
                  .map((f) => _FilteredList(
                        filter: f,
                        items: _items[f]!,
                        loading: _loading[f]!,
                        hasMore: _hasMore[f]!,
                        emptyLabel: l.callHistoryEmpty,
                        onLoadMore: () => _fetchPage(f),
                        onRefresh: () => _fetchPage(f, refresh: true),
                      ))
                  .toList(),
            ),
    );
  }
}

// ── Per-tab list ──────────────────────────────────────────────────────────────

class _FilteredList extends StatefulWidget {
  final String filter;
  final List<_CallHistoryItem> items;
  final bool loading;
  final bool hasMore;
  final String emptyLabel;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;

  const _FilteredList({
    required this.filter,
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.emptyLabel,
    required this.onLoadMore,
    required this.onRefresh,
  });

  @override
  State<_FilteredList> createState() => _FilteredListState();
}

class _FilteredListState extends State<_FilteredList> {
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
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      if (widget.hasMore && !widget.loading) {
        widget.onLoadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.items.isEmpty) {
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
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          if (i == widget.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _CallTile(item: widget.items[i]);
        },
      ),
    );
  }
}

// ── Single call row ───────────────────────────────────────────────────────────

class _CallTile extends StatelessWidget {
  final _CallHistoryItem item;
  const _CallTile({required this.item});

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);

    if (diff.inDays == 0) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[local.weekday - 1];
    } else {
      return '${local.day}/${local.month}/${local.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isMissed = item.isMissed || item.status == 'missed';
    final isOutgoing = item.isOutgoing;
    final duration = _formatDuration(item.durationSeconds);
    final timeLabel = _formatTime(item.startedAt);

    // Direction icon + color
    final (IconData dirIcon, Color dirColor) = switch (item.status) {
      'missed' => (Icons.call_missed, Colors.red),
      'rejected' => (Icons.call_missed_outgoing, cs.outline),
      _ when isOutgoing => (Icons.call_made, const Color(0xFF22C55E)),
      _ => (Icons.call_received, const Color(0xFF22C55E)),
    };

    // Status label
    final String statusLabel = switch (item.status) {
      'missed' => 'Missed',
      'rejected' => isOutgoing ? 'Declined' : 'You declined',
      'ended' when (item.durationSeconds ?? 0) > 0 => duration,
      'ended' => isOutgoing ? 'No answer' : 'Not answered',
      'calling' => 'Cancelled',
      _ => item.status,
    };

    return ListTile(
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
        item.otherUsername ?? 'Unknown',
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
