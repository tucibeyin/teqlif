import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../config/app_colors.dart';
import '../config/theme.dart';
import '../core/error_mapper.dart';
import '../models/replay_event.dart';
import '../services/localization_service.dart';
import 'viewmodels/recording_detail_view_model.dart';
import 'recording_detail/auctions_tab.dart';
import 'recording_detail/direct_sales_tab.dart';
import 'recording_detail/gifts_tab.dart';
import 'recording_detail/overview_tab.dart';
import 'recording_detail/participants_tab.dart';

class RecordingDetailScreen extends ConsumerStatefulWidget {
  final int streamId;
  const RecordingDetailScreen({super.key, required this.streamId});

  @override
  ConsumerState<RecordingDetailScreen> createState() =>
      _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends ConsumerState<RecordingDetailScreen>
    with TickerProviderStateMixin {
  VideoPlayerController? _vpCtrl;
  ChewieController? _chewieCtrl;
  bool _playerInitialized = false;
  String? _currentUrl;
  bool _recovering = false;
  double _replayPosSecs = 0.0;
  late final TabController _tabController;
  late final AnimationController _tabHintPulse;
  late final Animation<double> _tabHintFade;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _tabHintPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _tabHintFade = CurvedAnimation(parent: _tabHintPulse, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _tabHintPulse.dispose();
    _tabController.dispose();
    _vpCtrl?.removeListener(_onPlayerTick);
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    super.dispose();
  }

  void _onPlayerTick() {
    if (!mounted || _vpCtrl == null) return;
    final pos = _vpCtrl!.value.position.inSeconds.toDouble();
    if ((pos - _replayPosSecs).abs() >= 1.0) {
      setState(() => _replayPosSecs = pos);
    }
  }

  void _initPlayer(String url) {
    if (_currentUrl == url) return;
    _currentUrl = url;
    _recovering = false;
    _vpCtrl?.removeListener(_onPlayerTick);
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    setState(() => _playerInitialized = false);
    _vpCtrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _vpCtrl!.initialize().then((_) {
      if (!mounted) return;
      _vpCtrl!.addListener(_onPlayerTick);
      _chewieCtrl = ChewieController(
        videoPlayerController: _vpCtrl!,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        aspectRatio: _vpCtrl!.value.aspectRatio,
      );
      setState(() => _playerInitialized = true);
    }).catchError((_) {
      if (!mounted || _recovering) return;
      _recovering = true;
      ref
          .read(recordingDetailProvider(widget.streamId).notifier)
          .recoverUrl();
    });
  }

  double? _durationSecs(RecordingDetailState s) {
    if (_playerInitialized && _vpCtrl != null) {
      final d = _vpCtrl!.value.duration.inSeconds.toDouble();
      if (d > 0) return d;
    }
    if (s.summary != null) {
      final st = s.summary!.stream;
      if (st.recordingStartedAt != null && st.endedAt != null) {
        return st.endedAt!.difference(st.recordingStartedAt!).inSeconds.toDouble();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(recordingDetailProvider(widget.streamId));

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(ErrorMapper.toMessage(e, loc),
              style: TextStyle(color: AppColors.textSecondary(context))),
        ),
        data: (s) => _buildBody(context, s, loc),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, RecordingDetailState s, TranslationPack loc) {
    if (s.urlError != null && s.urlError == 'RECORDING_EXPIRED') {
      return _FullErrorState(
        message: loc.t('errorRecordingExpired'),
        icon: Icons.lock_outline,
      );
    }
    if (s.urlData != null) {
      _initPlayer(s.urlData!.url);
    }

    final duration = _durationSecs(s);

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          backgroundColor: AppColors.surface(context),
          foregroundColor: AppColors.textPrimary(context),
          elevation: 0,
          title: Text(
            loc.t('recordingDetailTitle'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          floating: true,
          snap: true,
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              // ── Video player ─────────────────────────────────────────
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: _playerInitialized && _vpCtrl != null
                        ? _vpCtrl!.value.aspectRatio
                        : 16 / 9,
                    child: Container(
                      color: Colors.black,
                      child: s.urlData == null
                          ? _playerError(s.urlError, loc)
                          : _playerInitialized && _chewieCtrl != null
                              ? Chewie(controller: _chewieCtrl!)
                              : const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white)),
                    ),
                  ),
                  if (s.replayEnabled)
                    Positioned(
                      left: 8,
                      bottom: 48,
                      right: 60,
                      child: IgnorePointer(
                        child: _ReplayOverlay(
                          timeline: s.timeline,
                          posSecs: _replayPosSecs,
                        ),
                      ),
                    ),
                ],
              ),

              // ── 403 recovery banner ──────────────────────────────────
              if (s.urlError != null &&
                  s.urlError != 'RECORDING_EXPIRED' &&
                  s.urlError != 'RECORDING_NOT_AVAILABLE' &&
                  s.urlError != 'RECORDING_NOT_FOUND' &&
                  s.urlData == null)
                _RecoveryBanner(streamId: widget.streamId, loc: loc),
            ],
          ),
        ),
        // ── Tab bar ──────────────────────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            child: _TabBarWithHint(
              controller: _tabController,
              hintFade: _tabHintFade,
              surfaceColor: AppColors.surface(context),
              tabs: [
                Tab(text: loc.t('recordingParticipantTabOverall')),
                Tab(text: loc.t('recordingDetailAuctions')),
                Tab(text: loc.t('recordingDetailDirectSales')),
                Tab(text: loc.t('recordingDetailGifts')),
                Tab(text: loc.t('recordingTabParticipants')),
              ],
            ),
            color: AppColors.surface(context),
          ),
        ),
      ],
      body: s.summaryLoading
          ? const Center(child: CircularProgressIndicator())
          : s.summaryFailed
              ? _SummaryFailedState(streamId: widget.streamId, loc: loc)
              : s.summary == null
                  ? const SizedBox.shrink()
                  : TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        OverviewTab(
                          detail: s.summary!,
                          participants: s.participants,
                          loc: loc,
                        ),
                        AuctionsTab(
                          auctions: s.summary!.auctions,
                          loc: loc,
                          durationSecs: duration,
                        ),
                        DirectSalesTab(
                          directSales: s.summary!.directSales,
                          loc: loc,
                        ),
                        GiftsTab(
                          gifts: s.summary!.gifts,
                          loc: loc,
                        ),
                        ParticipantsTab(
                          participants: s.participants,
                          loc: loc,
                          durationSecs: duration,
                        ),
                      ],
                    ),
    );
  }

  Widget _playerError(String? code, TranslationPack loc) {
    final msg = code == null
        ? loc.t('recordingLoading')
        : loc.t('errorRecordingNotAvailable');
    return Center(
      child: Text(msg,
          style: const TextStyle(color: Colors.white70, fontSize: 14)),
    );
  }
}

// ── Tab bar delegate ──────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final Color color;

  _TabBarDelegate({required this.child, required this.color});

  static const double _kTabBarHeight = 46.0;

  @override
  double get minExtent => _kTabBarHeight + 1;
  @override
  double get maxExtent => _kTabBarHeight + 1;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: color,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: _kTabBarHeight, child: child),
          Divider(height: 1, color: AppColors.border(context)),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      old.child != child || old.color != color;
}

// ── Scrollable tab bar with "more" hint ───────────────────────────────────────

class _TabBarWithHint extends StatelessWidget {
  final TabController controller;
  final List<Tab> tabs;
  final Animation<double> hintFade;
  final Color surfaceColor;

  const _TabBarWithHint({
    required this.controller,
    required this.tabs,
    required this.hintFade,
    required this.surfaceColor,
  });

  bool get _hasMoreRight => controller.index < tabs.length - 1;

  @override
  Widget build(BuildContext context) {
    final tabBar = TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: kPrimary,
      labelColor: kPrimary,
      unselectedLabelColor: AppColors.textSecondary(context),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13),
      indicatorSize: TabBarIndicatorSize.label,
      padding: EdgeInsets.zero,
      tabs: tabs,
    );

    if (!_hasMoreRight) return tabBar;

    return Stack(
      children: [
        tabBar,
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: FadeTransition(
              opacity: hintFade,
              child: Container(
                width: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      surfaceColor.withAlpha(0),
                      surfaceColor.withAlpha(230),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Recovery banner ───────────────────────────────────────────────────────────

class _RecoveryBanner extends ConsumerWidget {
  final int streamId;
  final TranslationPack loc;

  const _RecoveryBanner({required this.streamId, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withAlpha(77)),
      ),
      child: Row(
        children: [
          const Icon(Icons.refresh, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc.t('recordingUrlExpiredRetry'),
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(recordingDetailProvider(streamId).notifier)
                .recoverUrl(),
            child: Text(loc.t('retry'),
                style: const TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }
}

// ── Summary failed state ──────────────────────────────────────────────────────

class _SummaryFailedState extends ConsumerWidget {
  final int streamId;
  final TranslationPack loc;

  const _SummaryFailedState({required this.streamId, required this.loc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              color: AppColors.textTertiary(context), size: 32),
          const SizedBox(height: 8),
          Text(
            loc.t('errorGeneric'),
            style: TextStyle(color: AppColors.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => ref
                .read(recordingDetailProvider(streamId).notifier)
                .retrySummary(),
            child: Text(loc.t('retry')),
          ),
        ],
      ),
    );
  }
}

// ── Full error state ──────────────────────────────────────────────────────────

class _FullErrorState extends StatelessWidget {
  final String message;
  final IconData icon;

  const _FullErrorState({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary(context)),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
                color: AppColors.textSecondary(context), fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Replay overlay ────────────────────────────────────────────────────────────

int _upperBound(List<ReplayEvent> timeline, double pos) {
  int lo = 0, hi = timeline.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    timeline[mid].offsetSecs <= pos ? lo = mid + 1 : hi = mid;
  }
  return lo;
}

class _ReplayOverlay extends StatelessWidget {
  final List<ReplayEvent> timeline;
  final double posSecs;

  const _ReplayOverlay({required this.timeline, required this.posSecs});

  @override
  Widget build(BuildContext context) {
    final end = _upperBound(timeline, posSecs);
    final count = end.clamp(0, 5);
    final visible = timeline.sublist(end - count, end);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: visible.asMap().entries.map((e) {
        final opacity = ((e.key + 1) / count).clamp(0.3, 1.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Opacity(
            opacity: opacity,
            child: _ReplayBubble(event: e.value),
          ),
        );
      }).toList(),
    );
  }
}

class _ReplayBubble extends StatelessWidget {
  final ReplayEvent event;

  const _ReplayBubble({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (event.type) {
      ReplayEventType.bid      => (Icons.gavel,                 AppColors.replayBid(context)),
      ReplayEventType.gift     => (Icons.card_giftcard,         AppColors.replayGift(context)),
      ReplayEventType.purchase => (Icons.shopping_bag_outlined, AppColors.replayPurchase(context)),
      ReplayEventType.chat     => (Icons.chat_bubble_outline,   Colors.white70),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(115),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              event.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
