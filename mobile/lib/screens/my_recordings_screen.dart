import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/recording.dart';
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
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            e.toString(),
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: Text(
                  loc.tOr('recordingEmptyState', 'Henüz kayıt yok'),
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.read(myRecordingsProvider.notifier).reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _RecordingCard(
                    item: items[index],
                    loc: loc,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RecordingDetailScreen(streamId: items[index].streamId),
                      ),
                    ),
                  ),
                ),
              ),
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
                    ],
                  ),
                  if (item.expiresAt != null && item.status.canWatch) ...[
                    const SizedBox(height: 4),
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
    } else if (diff.inHours < 1) {
      label = widget.loc.t('recordingStatusExpiresIn')
          .replaceAll('{duration}', '${diff.inMinutes}dk');
    } else if (diff.inDays < 1) {
      label = widget.loc.t('recordingStatusExpiresIn')
          .replaceAll('{duration}', '${diff.inHours}s');
    } else {
      label = widget.loc.t('recordingStatusExpiresIn')
          .replaceAll('{duration}', '${diff.inDays}g');
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
