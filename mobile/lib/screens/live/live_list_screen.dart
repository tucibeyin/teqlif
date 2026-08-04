import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../../services/localization_service.dart";
import '../../config/api.dart';

import '../../config/theme.dart';
import '../../config/app_colors.dart';
import '../../models/stream.dart';
import '../../services/catalog_service.dart';
import '../../services/stream_connection_manager.dart';
import '../../utils/start_stream_helper.dart';
import '../../utils/subcategory_icons.dart';
import '../../providers/story_provider.dart';
import '../../widgets/live/story_tray.dart';
import '../../widgets/network_error_widget.dart';
import '../../widgets/stale_data_banner.dart';
import 'viewmodels/live_list_view_model.dart';
import 'swipe_live_screen.dart';
import '../public_profile_screen.dart';

class LiveListScreen extends ConsumerStatefulWidget {
  const LiveListScreen({super.key});

  @override
  ConsumerState<LiveListScreen> createState() => LiveListScreenState();
}



class LiveListScreenState extends ConsumerState<LiveListScreen> {
  String? _selectedCategory; // null = Tümü
  String? _selectedSubcategory; // null = Tümü

  void triggerStartDialog() => _showStartDialog();

  void refresh({bool bypassCache = true}) {
    ref.read(liveListViewModelProvider.notifier).refresh(bypassCache: bypassCache);
    ref.read(storyGroupsProvider.notifier).refresh();
    ref.read(myStoriesProvider.notifier).refresh();
  }

  Future<void> _showStartDialog() =>
      showStartStreamDialog(context, onStreamStarted: () => refresh(bypassCache: true));

  Future<void> _joinStream(StreamOut stream, bool isOffline) async {
    if (!mounted) return;
    if (isOffline) return;

    StreamConnectionManager.instance.prefetchForImmediateJoin(stream.id);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SwipeLiveScreen.fromStream(stream)),
    ).then((_) => refresh(bypassCache: true));
  }

  List<String> _getCategories(List<StreamOut> streams) {
    final seen = <String>{};
    return streams.map((s) => s.category).where(seen.add).toList();
  }

  List<String> _getSubcategories(List<StreamOut> streams) {
    if (_selectedCategory == null) return [];
    final seen = <String>{};
    return streams
        .where((s) => s.category == _selectedCategory && (s.subcategory?.isNotEmpty ?? false))
        .map((s) => s.subcategory!)
        .where(seen.add)
        .toList();
  }

  List<StreamOut> _getFiltered(List<StreamOut> streams) {
    if (_selectedCategory == null) return streams;
    var list = streams.where((s) => s.category == _selectedCategory).toList();
    if (_selectedSubcategory != null) {
      list = list.where((s) => s.subcategory == _selectedSubcategory).toList();
    }
    return list;
  }

  List<StreamOut> _getFilteredRecommended(List<StreamOut> recommended) {
    if (_selectedCategory == null) return recommended;
    var list = recommended.where((s) => s.category == _selectedCategory).toList();
    if (_selectedSubcategory != null) {
      list = list.where((s) => s.subcategory == _selectedSubcategory).toList();
    }
    return list;
  }


  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(liveListViewModelProvider);
    final stateVal = stateAsync.valueOrNull;
    final isOffline = stateVal?.isOffline ?? false;
    final cats = _getCategories(stateVal?.streams ?? []);
    final showFilter = !stateAsync.isLoading && cats.isNotEmpty;
    final filtered = _getFiltered(stateVal?.streams ?? []);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              loc.t("liveStreamsTitle"),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            key: const Key('live_list_btn_yayin_ac'),
            onPressed: _showStartDialog,
            icon: const Icon(
              Icons.videocam_outlined,
              size: 18,
              color: Colors.red,
            ),
            label: Text(
              loc.t("liveStartStream"),
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Video Hikayeler (Story Tray) ────────────────────────
          const StoryTray(),

          // ── Kategori filtre çubuğu ──────────────────────────────
          if (showFilter) ...[
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                children: [
                  _CategoryChip(
                    key: const Key('live_list_chip_tumü'),
                    label: loc.t("liveAllCategory"),
                    active: _selectedCategory == null,
                    onTap: () => setState(() {
                      _selectedCategory = null;
                      _selectedSubcategory = null;
                    }),
                  ),
                  ...cats.map(
                    (c) => _CategoryChip(
                      key: Key('live_list_chip_$c'),
                      label: loc.t('cat_$c'),
                      icon: getCategoryIcon(c),
                      active: _selectedCategory == c,
                      onTap: () => setState(() {
                        _selectedCategory = c;
                        _selectedSubcategory = null;
                      }),
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedCategory != null && _getSubcategories(stateVal?.streams ?? []).isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  children: [
                    _SubcategoryChip(
                      label: loc.t("liveAllCategory"),
                      active: _selectedSubcategory == null,
                      onTap: () => setState(() => _selectedSubcategory = null),
                    ),
                    ..._getSubcategories(stateVal?.streams ?? []).map(
                      (s) {
                         final sub = CatalogService.subcategoryByKey(s);
                         final labelKey = sub?.labelKey ?? 'subcat_$s';
                         return _SubcategoryChip(
                           label: loc.t(labelKey),
                           icon: getSubcategoryIcon(s),
                           active: _selectedSubcategory == s,
                           onTap: () => setState(() => _selectedSubcategory = s),
                         );
                      }
                    ),
                  ],
                ),
              ),
          ],
          if (stateAsync.hasError && (stateVal?.streams.isNotEmpty ?? false))
            StaleDataBanner(onRetry: () => refresh(bypassCache: true)),
          // ── İçerik ──────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: kPrimary,
              onRefresh: () async => refresh(bypassCache: true),
              child: stateAsync.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: kPrimary),
                    )
                  : stateAsync.hasError && filtered.isEmpty
                  ? NetworkErrorWidget(onRetry: () => refresh(bypassCache: true), scrollable: true)
                  : filtered.isEmpty
                  ? const _EmptyState()
                  : _buildContent(loc, filtered),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(TranslationPack loc, List<StreamOut> filtered) {
    final stateAsync = ref.watch(liveListViewModelProvider);
    final stateVal = stateAsync.valueOrNull;
    final isOffline = stateVal?.isOffline ?? false;
    final rec = _getFilteredRecommended(stateVal?.recommended ?? []);
    final hasRec = (stateVal?.isLoggedIn ?? false) && rec.isNotEmpty;
    final hasSuggestedStreamers = (stateVal?.isLoggedIn ?? false) && (stateVal?.suggestedStreamers ?? []).isNotEmpty;
    final cats = _getCategories(stateVal?.streams ?? []);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ── Önerilen Yayıncılar ────────────────────────────────
        if (hasSuggestedStreamers) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.live_tv_rounded,
                    color: Color(0xFFEF4444),
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    loc.t("suggestedStreamers"),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 106,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: (stateVal?.suggestedStreamers ?? []).length,
                itemBuilder: (ctx, i) => _StreamerAvatarCard(
                  streamer: (stateVal?.suggestedStreamers ?? [])[i],
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => PublicProfileScreen(
                        username:
                            (stateVal?.suggestedStreamers ?? [])[i]['username'] as String? ?? '',
                        userId: (stateVal?.suggestedStreamers ?? [])[i]['id'] as int?,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Divider(height: 1, indent: 12, endIndent: 12),
          ),
        ],

        // ── Sana Özel Yayınlar ─────────────────────────────────
        if (hasRec) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: kPrimary, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    loc.t("forYouStreams"),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: rec.length,
                itemBuilder: (_, i) => SizedBox(
                  width: 150,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: _StreamGridTile(
                      stream: rec[i],
                      onTap: () => _joinStream(rec[i], isOffline),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Divider(height: 1, indent: 12, endIndent: 12),
          ),
        ],

        // ── En Son Canlı Yayınlar ──────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _selectedCategory != null
                      ? loc.t("categoryStreams", {"category": loc.t('cat_$_selectedCategory')})
                      : loc.t("latestLiveStreams"),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Düz grid veya section'lı — kategori seçiliyse düz
        if (_selectedCategory != null || cats.length < 2)
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _StreamGridTile(
                  stream: filtered[i],
                  onTap: () => _joinStream(filtered[i], isOffline),
                ),
                childCount: filtered.length,
              ),
            ),
          )
        else
          ..._buildSectionedSlivers(cats, filtered, loc, isOffline),
      ],
    );
  }

  List<Widget> _buildSectionedSlivers(List<String> cats, List<StreamOut> all, TranslationPack loc, bool isOffline) {
    final groups = {
      for (var c in cats) c: all.where((s) => s.category == c).toList(),
    };
    return [
      for (final c in cats)
        if (groups[c]!.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
              child: Text(
                loc.t('cat_$c'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 4),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _StreamGridTile(
                  stream: groups[c]![i],
                  onTap: () => _joinStream(groups[c]![i], isOffline),
                ),
                childCount: groups[c]!.length,
              ),
            ),
          ),
        ],
    ];
  }
}

class _CategoryChip extends ConsumerWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  const _CategoryChip({
    super.key,
    required this.label,
    this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsetsDirectional.only(end: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? kPrimary : const Color(0xFFD1D5DB),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: active ? Colors.white : kPrimary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubcategoryChip extends ConsumerWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  const _SubcategoryChip({
    super.key,
    required this.label,
    this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsetsDirectional.only(end: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? kPrimary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? kPrimary : const Color(0xFFE5E7EB),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: active ? kPrimary : const Color(0xFF6B7280)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? kPrimary : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(liveListViewModelProvider);
    final stateVal = stateAsync.valueOrNull;
    final isOffline = stateVal?.isOffline ?? false;
    return ListView(
      children: [
        const SizedBox(height: 120),
        Column(
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              size: 56,
              color: Color(0xFFD1D5DB),
            ),
            const SizedBox(height: 12),
            Text(
              loc.t("liveNoStreams"),
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              loc.t("liveBeFirst"),
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _StreamerAvatarCard extends ConsumerWidget {
  final Map<String, dynamic> streamer;
  final VoidCallback? onTap;
  const _StreamerAvatarCard({required this.streamer, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(liveListViewModelProvider);
    final stateVal = stateAsync.valueOrNull;
    final isOffline = stateVal?.isOffline ?? false;
    final rawUrl = (streamer['profile_image_url'] as String?) ?? '';
    final imageUrl = rawUrl.isNotEmpty ? imgUrl(rawUrl) : null;
    final isVerified = streamer['is_verified'] == true;
    final isPremium = streamer['is_premium'] == true;
    final isLive = streamer['is_live'] == true;
    final username = streamer['username'] as String? ?? '';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Gradient ring + white border + avatar (Story stilinde)
                  Container(
                    width: 62,
                    height: 62,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [kPrimary, kPrimaryLight, Color(0xFF7C3AED)],
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                      ),
                    ),
                    padding: const EdgeInsets.all(2.5),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface(context),
                      ),
                      padding: const EdgeInsets.all(1.5),
                      child: ClipOval(
                        child: imageUrl != null && imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                placeholder: (_, _) => _AvatarInitial(
                                  initial: initial,
                                  context: context,
                                ),
                                errorWidget: (_, _, _) => _AvatarInitial(
                                  initial: initial,
                                  context: context,
                                ),
                              )
                            : _AvatarInitial(
                                initial: initial,
                                context: context,
                              ),
                      ),
                    ),
                  ),
                  // Premium badge
                  if (isPremium)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF59E0B),
                          border: Border.all(
                            color: AppColors.surface(context),
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Text('👑', style: TextStyle(fontSize: 10)),
                        ),
                      ),
                    )
                  // Verified badge
                  else if (isVerified)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2563EB),
                          border: Border.all(
                            color: AppColors.surface(context),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  // CANLI badge (üst kısım)
                  if (isLive)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.surface(context),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          loc.t("liveBadgeLabel"),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '@$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarInitial extends ConsumerWidget {
  final String initial;
  final BuildContext context;
  const _AvatarInitial({required this.initial, required this.context});

  @override
  Widget build(BuildContext _, WidgetRef ref) {
    return Container(
      color: AppColors.primaryBg(context),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: kPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
    );
  }
}

class _StreamGridTile extends ConsumerWidget {
  final StreamOut stream;
  final VoidCallback onTap;

  const _StreamGridTile({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(liveListViewModelProvider);
    final stateVal = stateAsync.valueOrNull;
    final isOffline = stateVal?.isOffline ?? false;
    final hasThumbnail =
        stream.thumbnailUrl != null && stream.thumbnailUrl!.isNotEmpty;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Square thumbnail area
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background
                    if (hasThumbnail)
                      CachedNetworkImage(
                        imageUrl: imgUrl(stream.thumbnailUrl),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (_, _, _) => _gradientBox(),
                      )
                    else
                      _gradientBox(),
                    // CANLI badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          loc.t("liveBadgeLabel"),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    // Viewer badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '👁 ${stream.viewerCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Info section
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 7, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stream.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: AppColors.textPrimary(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${stream.host.username}',
                      style: const TextStyle(
                        color: kPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradientBox() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryDark, kPrimaryLight],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      child: const Center(
        child: Icon(Icons.videocam_rounded, color: Colors.white30, size: 36),
      ),
    );
  }
}
