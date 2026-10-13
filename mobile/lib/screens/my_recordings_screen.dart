import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/recording.dart';
import '../services/category_service.dart';
import '../services/localization_service.dart';
import 'viewmodels/my_recordings_view_model.dart';
import 'recording_detail_screen.dart';
import '../widgets/pro_paywall_overlay.dart';

class MyRecordingsScreen extends ConsumerStatefulWidget {
  final bool isPremium;
  const MyRecordingsScreen({super.key, required this.isPremium});

  @override
  ConsumerState<MyRecordingsScreen> createState() => _MyRecordingsScreenState();
}

class _MyRecordingsScreenState extends ConsumerState<MyRecordingsScreen> {
  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);

    if (!widget.isPremium) {
      return Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: AppBar(
          backgroundColor: AppColors.bg(context),
          elevation: 0,
          title: Text(loc.t('proToolMyRecordingsTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: Stack(children: [
          const ProLockedPlaceholder(),
          ProPaywallOverlay(
            icon: Icons.video_library_outlined,
            gradientColors: const [Color(0xFFF97316), Color(0xFFEA580C)],
            descKey: 'recordingPaywallDesc',
          ),
        ]),
      );
    }

    final stateAsync = ref.watch(myRecordingsProvider);
    final filter    = ref.watch(recordingFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        title: Text(
          loc.t('proToolMyRecordingsTitle'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          _RecordingFilterBar(loc: loc),
          Expanded(
            child: stateAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  e.toString(),
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ),
              data: (allItems) {
                final items = filter.apply(allItems);
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      loc.t('recordingEmptyState'),
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(myRecordingsProvider.notifier).reload(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    itemCount: items.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _RecordingCard(
                      item: items[index],
                      loc: loc,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RecordingDetailScreen(
                              streamId: items[index].streamId),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  final RecordingItem item;
  final TranslationPack loc;
  final VoidCallback onTap;

  const _RecordingCard({
    required this.item,
    required this.loc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.status.canWatch ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            _StatusIcon(status: item.status),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.streamTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StatusChip(item: item, loc: loc),
                      if (item.durationSecs != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _formatDuration(item.durationSecs!),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                      if (item.category != null) ...[
                        const SizedBox(width: 6),
                        _CategoryChip(category: item.category!, loc: loc),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.recordingStartedAt != null) ...[
                        Icon(Icons.calendar_today_outlined,
                            size: 11, color: AppColors.textTertiary(context)),
                        const SizedBox(width: 3),
                        Text(
                          _formatDate(item.recordingStartedAt!),
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary(context)),
                        ),
                      ],
                      if (item.peakViewerCount != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.remove_red_eye_outlined,
                            size: 11, color: AppColors.textTertiary(context)),
                        const SizedBox(width: 3),
                        Text(
                          '${item.peakViewerCount}',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary(context)),
                        ),
                      ],
                    ],
                  ),
                  if (item.expiresAt != null && item.status.canWatch) ...[
                    const SizedBox(height: 2),
                    _ExpiryRow(expiresAt: item.expiresAt!, loc: loc),
                  ],
                ],
              ),
            ),
            if (item.status.canWatch)
              Icon(Icons.chevron_right, color: AppColors.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d.$mo.${dt.year}, $h:$mi';
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _RecordingFilterBar extends ConsumerStatefulWidget {
  final TranslationPack loc;
  const _RecordingFilterBar({required this.loc});

  @override
  ConsumerState<_RecordingFilterBar> createState() => _RecordingFilterBarState();
}

class _RecordingFilterBarState extends ConsumerState<_RecordingFilterBar> {
  late TextEditingController _searchCtrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final current = ref.read(recordingFilterProvider);
      ref.read(recordingFilterProvider.notifier).state = current.copyWith(
        searchQuery: text.trim().isEmpty ? null : text.trim(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reaktif — filter değişince chip seçimi güncellenir
    final filter = ref.watch(recordingFilterProvider);
    final loc = widget.loc;

    // Mevcut kayıtlardan benzersiz kategorileri çıkar
    final allItems = ref.watch(myRecordingsProvider).valueOrNull ?? [];
    final categories = allItems
        .map((i) => i.category)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    // Search text controller'ı dış reset ile senkronize et
    final externalQuery = filter.searchQuery ?? '';
    if (_searchCtrl.text != externalQuery && externalQuery.isEmpty) {
      _searchCtrl.clear();
    }

    final statusChips = [
      (RecordingFilterStatus.all,       loc.t('recordingFilterAll')),
      (RecordingFilterStatus.available,  loc.t('recordingFilterAvailable')),
      (RecordingFilterStatus.preparing,  loc.t('recordingFilterPreparing')),
      (RecordingFilterStatus.expired,    loc.t('recordingFilterExpired')),
    ];

    return Container(
      color: AppColors.surface(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
              decoration: InputDecoration(
                hintText: loc.t('recordingSearchHint'),
                hintStyle: TextStyle(color: AppColors.textTertiary(context), fontSize: 14),
                prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textTertiary(context)),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 18, color: AppColors.textTertiary(context)),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.card(context),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Durum filtreleri
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: statusChips.map((chip) {
                final (status, label) = chip;
                final selected = filter.statusFilter == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) {
                      ref.read(recordingFilterProvider.notifier).state =
                          filter.copyWith(statusFilter: status);
                    },
                    selectedColor: kPrimary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary(context),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    backgroundColor: AppColors.card(context),
                    side: BorderSide(color: AppColors.border(context)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                );
              }).toList(),
            ),
          ),
          // Kategori filtreleri — birden fazla kategori varsa göster
          if (categories.length > 1) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  // "Tümü" seçeneği
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _CategoryFilterChip(
                      label: loc.t('recordingFilterAll'),
                      selected: filter.categoryFilter == null,
                      onTap: () => ref.read(recordingFilterProvider.notifier).state =
                          filter.copyWith(categoryFilter: null),
                    ),
                  ),
                  ...categories.map((cat) {
                    final selected = filter.categoryFilter == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _CategoryFilterChip(
                        label: CategoryService.localizedLabelFor(loc, cat),
                        selected: selected,
                        onTap: () => ref.read(recordingFilterProvider.notifier).state =
                            filter.copyWith(categoryFilter: selected ? null : cat),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Divider(height: 1, color: AppColors.border(context)),
        ],
      ),
    );
  }
}

// ── Category filter chip (filter bar) ────────────────────────────────────────

class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? kPrimary : AppColors.card(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? kPrimary : AppColors.border(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? Colors.white : AppColors.textSecondary(context),
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  final TranslationPack loc;
  const _CategoryChip({required this.category, required this.loc});

  @override
  Widget build(BuildContext context) {
    final label = CategoryService.localizedLabelFor(loc, category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.textTertiary(context).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: AppColors.textTertiary(context),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final RecordingStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      RecordingStatus.available => (Icons.play_circle_outline, kPrimary),
      RecordingStatus.recording ||
      RecordingStatus.encoding ||
      RecordingStatus.encoded ||
      RecordingStatus.transferring =>
        (Icons.hourglass_bottom_rounded, const Color(0xFFF97316)),
      RecordingStatus.expired ||
      RecordingStatus.archived =>
        (Icons.lock_outline, AppColors.textTertiary(context)),
      RecordingStatus.failed => (Icons.error_outline, Colors.red),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final RecordingItem item;
  final TranslationPack loc;

  const _StatusChip({required this.item, required this.loc});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (item.status) {
      RecordingStatus.available =>
        (loc.t('recordingStatusWatch'), kPrimary),
      RecordingStatus.recording ||
      RecordingStatus.encoding ||
      RecordingStatus.encoded ||
      RecordingStatus.transferring =>
        (loc.t('recordingStatusPreparing'), const Color(0xFFF97316)),
      RecordingStatus.expired ||
      RecordingStatus.archived =>
        (loc.t('recordingStatusExpired'), AppColors.textTertiary(context)),
      RecordingStatus.failed =>
        ('Hata', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ExpiryRow extends StatefulWidget {
  final DateTime expiresAt;
  final TranslationPack loc;

  const _ExpiryRow({required this.expiresAt, required this.loc});

  @override
  State<_ExpiryRow> createState() => _ExpiryRowState();
}

class _ExpiryRowState extends State<_ExpiryRow> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.expiresAt.difference(DateTime.now());
    final String label;
    if (diff.isNegative) {
      label = widget.loc.t('recordingStatusExpired');
    } else if (diff.inMinutes < 60) {
      label = widget.loc.t('recordingStatusExpiresIn')
          .replaceAll('{duration}', '${diff.inMinutes}dk');
    } else {
      // Maksimum 24 saat geçerli — gün gösterme, saat+dakika göster
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      final durationStr = m > 0 ? '${h}s ${m}dk' : '${h}s';
      label = widget.loc.t('recordingStatusExpiresIn')
          .replaceAll('{duration}', durationStr);
    }

    return Row(
      children: [
        Icon(Icons.access_time, size: 12, color: AppColors.textTertiary(context)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary(context)),
        ),
      ],
    );
  }
}
