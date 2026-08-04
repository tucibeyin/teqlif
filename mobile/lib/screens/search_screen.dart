import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/stream.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/feed_telemetry_service.dart';
import '../services/image_cache_manager.dart';
import '../services/storage_service.dart';
import '../ui_library/components/buttons/teq_button.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../services/stream_service.dart';
import '../widgets/network_error_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/stale_data_banner.dart';
import '../widgets/streamer_avatar_card.dart';
import '../widgets/listing_badge_overlay.dart';
import '../widgets/seller_avatar_card.dart';
import 'public_profile_screen.dart';
import 'listing_detail_screen.dart';
import 'live/swipe_live_screen.dart';

import 'viewmodels/search_view_model.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  final ScrollController _scrollCtrl = ScrollController();
  final ScrollController _forYouScrollCtrl = ScrollController();
  static const double _cardWidth = 130.0;
  
  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _scrollCtrl.addListener(_onScroll);
    _forYouScrollCtrl.addListener(_onForYouScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _debounce?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _forYouScrollCtrl.removeListener(_onForYouScroll);
    _forYouScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAlertSheet(BuildContext context) async {
    final query = _controller.text.trim();
    final loc = ref.read(localizationProvider);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.t("searchAlertTitle"),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              loc.t("searchAlertBody", {"query": query}),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TeqButton.outline(
                    onPressed: () => Navigator.pop(context, false),
                    text: MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TeqButton(
                    onPressed: () => Navigator.pop(context, true),
                    text: loc.t("searchAlertCreate"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    
    final success = await ref.read(searchViewModelProvider.notifier).createSearchAlert(query);
    if (mounted) {
      if (success) {
        TeqSnackBar.show(message: loc.t("searchAlertCreated"), type: TeqSnackBarType.success);
      } else {
        TeqSnackBar.show(message: loc.t("searchAlertFailed"), type: TeqSnackBarType.error);
      }
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      ref.read(searchViewModelProvider.notifier).loadMoreRecentListings();
    }
  }

  void _onForYouScroll() {
    if (!_forYouScrollCtrl.hasClients) return;
    final pos = _forYouScrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - _cardWidth * 3) {
      ref.read(searchViewModelProvider.notifier).loadMoreForYou();
    }
  }

  void _onQueryChanged() {
    final q = _controller.text.trim();
    ref.read(searchViewModelProvider.notifier).onQueryChanged(q);
    
    _debounce?.cancel();
    if (q.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 500), () {
        ref.read(searchViewModelProvider.notifier).search(q);
      });
    }
  }

  Future<void> _showNotInterestedMenu(int listingId, String section) async {
    final loc = ref.read(localizationProvider);
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.thumb_down_alt_outlined),
              title: Text(loc.t("notInterested")),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(searchViewModelProvider.notifier).markNotInterested(listingId, section);
                if (mounted) {
                  TeqSnackBar.show(message: loc.t("notInterestedConfirmed"), type: TeqSnackBarType.info);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _trackInteraction(int itemId, int? ownerId) {
    StorageService.getToken().then((token) async {
      if (token == null) return;
      if (ownerId != null) {
        final myUserId = await StorageService.getCurrentUserId();
        if (myUserId == ownerId) return;
      }
      http
          .post(
            Uri.parse('$kBaseUrl/analytics/interaction'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'item_id': itemId,
              'item_type': 'listing',
              'interaction_type': 'click',
            }),
          )
          .catchError((_) => http.Response('', 200));
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final searchStateAsync = ref.watch(searchViewModelProvider);
    final state = searchStateAsync.value ?? const SearchState();
    
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // ── Arama kutusu ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
              child: TeqTextField(
                key: const Key('search_input_arama'),
                controller: _controller,
                hintText: loc.t("searchAiHint"),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: state.hasQuery
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: state.isAlertCreating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.notifications_none,
                                    size: 20,
                                  ),
                            tooltip: loc.t("searchAlertTooltip"),
                            onPressed: state.isAlertCreating
                                ? null
                                : () => _showAlertSheet(context),
                          ),
                          IconButton(
                            key: const Key('search_btn_arama_temizle'),
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _controller.clear,
                          ),
                        ],
                      )
                    : null,
              ),
            ),
            // ── İçerik ───────────────────────────────────────────────
            Expanded(
              child: state.hasQuery ? _buildSearchResults(loc, state) : _buildExplore(loc, state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(TranslationPack loc, SearchState state) {
    if (state.isSearching) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    final hasUsers = state.userResults.isNotEmpty;
    final hasListings = state.listingResults.isNotEmpty;
    final hasStreams = state.streamResults.isNotEmpty;

    if (!hasUsers && !hasListings && !hasStreams) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_outlined,
              size: 56,
              color: Color(0xFFD1D5DB),
            ),
            const SizedBox(height: 12),
            Text(
              loc.t("searchNoResults"),
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                loc.t("searchNoSupplyHint"),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: state.isAlertCreating ? null : () => _showAlertSheet(context),
              icon: state.isAlertCreating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_none_outlined, size: 16),
              label: Text(loc.t("searchCreateAlertBtn")),
            ),
          ],
        ),
      );
    }

    // Max 5 kullanıcı göster; fazlası için "Hepsini gör" satırı
    final visibleUsers = state.showAllUsers
        ? state.userResults
        : state.userResults.take(5).toList();
    final hasMoreUsers = !state.showAllUsers && state.userResults.length > 5;

    return CustomScrollView(
      slivers: [
        // ── Akıllı Sonuçlar rozeti ──────────────────────────────────
        if (state.isSemanticSearch)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: kPrimary.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: kPrimary,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          loc.t("searchSmartResultsLabel"),
                          style: TextStyle(
                            color: kPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── 1. Kullanıcılar ──────────────────────────────────────────
        if (hasUsers) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              icon: Icons.person_outline_rounded,
              label: loc.t("searchFilterUsers"),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((ctx, i) {
              final u = visibleUsers[i];
              final imgRaw = u['profile_image_url'] as String?;
              final img = imgRaw != null && imgRaw.isNotEmpty
                  ? imgUrl(imgRaw)
                  : null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: kPrimary,
                      backgroundImage: img != null ? NetworkImage(img) : null,
                      child: img == null
                          ? Text(
                              (u['full_name'] as String? ?? '?')[0]
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      u['full_name'] as String? ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '@${u['username']}',
                      style: const TextStyle(color: kPrimary, fontSize: 12),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PublicProfileScreen(
                          username: u['username'] as String,
                        ),
                      ),
                    ),
                  ),
                  if (i < visibleUsers.length - 1)
                    const Divider(height: 1, indent: 72),
                ],
              );
            }, childCount: visibleUsers.length),
          ),
          // "Tüm hesapları gör" satırı
          if (hasMoreUsers)
            SliverToBoxAdapter(
              child: InkWell(
                onTap: () => ref.read(searchViewModelProvider.notifier).setShowAllUsers(true),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(72, 4, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        loc.t("searchShowAllAccounts", {"count": state.userResults.length.toString()}),
                        style: TextStyle(
                          color: kPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: kPrimary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],

        // ── 2. İlanlar ───────────────────────────────────────────────
        if (hasListings) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              icon: state.isSemanticSearch
                  ? Icons.auto_awesome_rounded
                  : Icons.grid_view_rounded,
              label: loc.t("searchFilterListings"),
              iconColor: state.isSemanticSearch ? kPrimary : null,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate((ctx, i) {
                final listing = state.listingResults[i];
                return _ListingTile(
                  listing: listing,
                  onTap: () {
                    final id = listing['id'] as int?;
                    final ownerId = (listing['user'] as Map?)?['id'] as int?;
                    if (id != null && state.isLoggedIn) {
                      _trackInteraction(id, ownerId);
                    }
                    AnalyticsService.trackEvent('search_result_tap', {
                      'item_type': 'listing',
                      'item_id': id,
                      'position': i,
                    });
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listing: listing),
                      ),
                    );
                  },
                );
              }, childCount: state.listingResults.length),
            ),
          ),
        ],

        // ── 3. Canlı Yayınlar ────────────────────────────────────────
        if (hasStreams) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              icon: Icons.fiber_manual_record,
              label: loc.t("searchFilterStreams"),
              iconColor: Colors.red,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 168,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: state.streamResults.length,
                itemBuilder: (_, i) => _StreamCard(
                  stream: state.streamResults[i],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SwipeLiveScreen.single(
                        streamId: state.streamResults[i].id,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildExplore(TranslationPack loc, SearchState state) {
    if (state.exploreLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        ref.read(searchViewModelProvider.notifier).refreshExplore(bypassCache: true);
      },
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Canlı Yayınlar ────────────────────────────────────────
          if (state.exploreStreams.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fiber_manual_record,
                      color: Colors.red,
                      size: 10,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      loc.t("searchLiveStreams"),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 168,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.exploreStreams.length,
                  itemBuilder: (_, i) => _StreamCard(
                    stream: state.exploreStreams[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SwipeLiveScreen.single(
                          streamId: state.exploreStreams[i].id,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          // ── Önerilen Yayıncılar ────────────────────────────────
          if (state.suggestedStreamers.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
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
                height: 106,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.suggestedStreamers.length,
                  itemBuilder: (ctx, i) => StreamerAvatarCard(
                    streamer: state.suggestedStreamers[i],
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => PublicProfileScreen(
                          username:
                              state.suggestedStreamers[i]['username'] as String? ??
                              '',
                          userId: state.suggestedStreamers[i]['id'] as int?,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ── Önerilen Satıcılar ─────────────────────────────────
          if (state.suggestedSellers.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.store_rounded, color: kPrimary, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      loc.t("suggestedSellers"),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 96,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.suggestedSellers.length,
                  itemBuilder: (ctx, i) => SellerAvatarCard(
                    seller: state.suggestedSellers[i],
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => PublicProfileScreen(
                          username:
                              state.suggestedSellers[i]['username'] as String? ?? '',
                          userId: state.suggestedSellers[i]['id'] as int?,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ── Sana Özel / Sizin İçin Seçilen İlanlar ──────────────────────────────
          if (state.exploreListings.isNotEmpty ||
              (state.exploreLoading && state.isLoggedIn)) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: kPrimary, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      state.isLoggedIn ? loc.t("forYouLabel") : loc.t("listingsSelectedForYou"),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (state.forYouLoadingMore)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kPrimary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: state.exploreLoading && state.exploreListings.isEmpty
                  ? SizedBox(
                      height: 190,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: 4,
                        itemBuilder: (_, _) => Container(
                          width: 120,
                          margin: const EdgeInsetsDirectional.only(end: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.grey.withValues(alpha: 0.15),
                          ),
                          child: const ShimmerBox(),
                        ),
                      ),
                    )
                  : state.exploreListings.isEmpty
                  ? const SizedBox.shrink()
                  : SizedBox(
                      height: 190,
                      child: ListView.builder(
                        controller: _forYouScrollCtrl,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount:
                            state.exploreListings.length +
                            (state.forYouLoadingMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == state.exploreListings.length) {
                            return const SizedBox(
                              width: 60,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          final listing =
                              state.exploreListings[i] as Map<String, dynamic>;
                          return _HorizontalListingCard(
                            listing: listing,
                            onLongPress: () {
                              final id = listing['id'] as int?;
                              if (id != null && state.isLoggedIn) {
                                _showNotInterestedMenu(id, 'for_you');
                              }
                            },
                            onTap: () {
                              final id = listing['id'] as int?;
                              final ownerId =
                                  (listing['user'] as Map?)?['id'] as int?;
                              if (id != null && state.isLoggedIn) {
                                _trackInteraction(id, ownerId);
                              }
                              if (listing['is_highlight'] == true) {
                                final rawRoomId = listing['active_room_id'];
                                if (rawRoomId != null) {
                                  final roomId = rawRoomId is int
                                      ? rawRoomId
                                      : int.tryParse(rawRoomId.toString());
                                  if (roomId != null) {
                                    Navigator.push(
                                      ctx,
                                      MaterialPageRoute(
                                        builder: (_) => SwipeLiveScreen.single(
                                          streamId: roomId,
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                }
                              }
                              Navigator.push(
                                ctx,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ListingDetailScreen(listing: listing),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],

          // ── Sizin İçin Seçilen İlanlar (login, /api/listings) ─────────────────
          if (state.isLoggedIn && state.recentListings.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Divider(height: 1, indent: 16, endIndent: 16),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.grid_view_rounded,
                      size: 15,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      loc.t("listingsSelectedForYou"),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final listing = state.recentListings[i] as Map<String, dynamic>;
                  return _ListingTile(
                    listing: listing,
                    onLongPress: () {
                      final id = listing['id'] as int?;
                      if (id != null && state.isLoggedIn) {
                        _showNotInterestedMenu(id, 'recent');
                      }
                    },
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listing: listing),
                      ),
                    ),
                  );
                }, childCount: state.recentListings.length),
              ),
            ),
            if (state.recentLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary),
                    ),
                  ),
                ),
              ),
          ],

          // ── Boş durum ────────────────────────────────────────────
          if (!state.exploreLoading &&
              state.exploreStreams.isEmpty &&
              state.exploreListings.isEmpty &&
              state.recentListings.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: state.exploreNetworkError
                  ? NetworkErrorWidget(onRetry: () => ref.read(searchViewModelProvider.notifier).refreshExplore(bypassCache: true))
                  : Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              state.isLoggedIn
                                  ? Icons.auto_awesome_outlined
                                  : Icons.explore_outlined,
                              size: 56,
                              color: const Color(0xFFD1D5DB),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              state.isLoggedIn
                                  ? loc.t("explorePersonalizedHint")
                                  : loc.t("searchNoContent"),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          if (!state.exploreLoading && state.exploreNetworkError &&
              (state.exploreListings.isNotEmpty || state.recentListings.isNotEmpty))
            SliverToBoxAdapter(child: StaleDataBanner(onRetry: () => ref.read(searchViewModelProvider.notifier).refreshExplore(bypassCache: true))),
        ],
      ),
    );
  }
}

// ── Bölüm başlığı ──────────────────────────────────────────────────────────
class _SectionHeader extends ConsumerWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor ?? const Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Yatay stream kartı ──────────────────────────────────────────────────────
class _StreamCard extends ConsumerWidget {
  final StreamOut stream;
  final VoidCallback onTap;

  const _StreamCard({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final hasThumbnail =
        stream.thumbnailUrl != null && stream.thumbnailUrl!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsetsDirectional.only(end: 10),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasThumbnail)
              CachedNetworkImage(
                  cacheManager: TeqlifCacheManager(),
                imageUrl: imgUrl(stream.thumbnailUrl),
                fit: BoxFit.cover,
                placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (_, _, _) => _gradient(),
              )
            else
              _gradient(),
            // CANLI badge
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
            // İsim ve başlık
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 20, 8, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stream.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${stream.host.username}',
                      style: const TextStyle(color: kPrimary, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradient() => Container(
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

// ── Yatay ilan kartı (Sana Özel) ────────────────────────────────────────────
class _HorizontalListingCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> listing;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _HorizontalListingCard({required this.listing, required this.onTap, this.onLongPress});

  @override
  ConsumerState<_HorizontalListingCard> createState() => _HorizontalListingCardState();
}

class _HorizontalListingCardState extends ConsumerState<_HorizontalListingCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  @override
  void initState() {
    super.initState();
    if (widget.listing['is_highlight'] == true) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);
      _pulseAnim = Tween<double>(
        begin: 0.6,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut));
    }
    if (widget.listing['is_sponsored'] == true) {
      final cid = widget.listing['campaign_id'];
      if (cid != null) AnalyticsService.trackAdImpression(cid as int);
    }
    final lid = widget.listing['id'];
    if (lid != null) {
      final ownerId = (widget.listing['user'] as Map?)?['id'] as int?;
      FeedTelemetryService.instance.logEvent(
        listingId: lid.toString(),
        eventType: 'impression',
        ownerId: ownerId,
        dwellTimeMs: 0,
        contentType: (widget.listing['video_url'] as String?) != null
            ? 'video'
            : 'photo',
        listingSubcategory: (widget.listing['subcategory'] as String?) ?? '',
      );
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  String _fmt(dynamic price) {
    if (price == null) return '';
    final s = (price as num).toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final imgs = widget.listing['image_urls'] as List? ?? [];
    final raw = imgs.isNotEmpty
        ? imgs[0] as String
        : widget.listing['image_url'] as String?;
    final photo = raw != null ? imgUrl(raw) : null;
    final price = _fmt(widget.listing['price']);

    return GestureDetector(
      onLongPress: widget.onLongPress,
      onTap: () {
        final lid = widget.listing['id'];
        if (lid != null) {
          final ownerId = (widget.listing['user'] as Map?)?['id'] as int?;
          FeedTelemetryService.instance.logEvent(
            listingId: lid.toString(),
            eventType: 'click',
            ownerId: ownerId,
            dwellTimeMs: 0,
            contentType: (widget.listing['video_url'] as String?) != null
                ? 'video'
                : 'photo',
            listingSubcategory: (widget.listing['subcategory'] as String?) ?? '',
          );
        }
        widget.onTap();
      },
      child: Container(
        width: 120,
        margin: const EdgeInsetsDirectional.only(end: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: AppColors.card(context),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photo != null
                      ? CachedNetworkImage(
                  cacheManager: TeqlifCacheManager(),
                          imageUrl: photo,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : Container(
                          color: AppColors.surfaceVariant(context),
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              color: AppColors.border(context),
                            ),
                          ),
                        ),
                  if (widget.listing['is_sponsored'] == true)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          loc.t("badgeSponsored"),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: ListingBadgeOverlay(listing: widget.listing),
                  ),
                  if (widget.listing['is_highlight'] == true)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.red.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_pulseAnim != null)
                              AnimatedBuilder(
                                animation: _pulseAnim!,
                                builder: (_, _) => Opacity(
                                  opacity: _pulseAnim!.value,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(bottom: 4),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            const Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(4, 0, 4, 6),
                              child: Text(
                                '🔴 Alev\nAlev!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.listing['is_highlight'] == true)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                color: Colors.red,
                child: Text(
                  loc.t("joinLiveStreamBanner"),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(6, 5, 6, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.listing['title'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (price.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        price,
                        style: const TextStyle(
                          fontSize: 11,
                          color: kPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── İlan grid tile ──────────────────────────────────────────────────────────
class _ListingTile extends ConsumerWidget {
  final Map<String, dynamic> listing;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ListingTile({required this.listing, required this.onTap, this.onLongPress});

  String _fmt(dynamic price) {
    if (price == null) return '';
    final s = (price as num).toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final imgs = listing['image_urls'] as List? ?? [];
    final raw = imgs.isNotEmpty
        ? imgs[0] as String
        : (listing['image_url'] as String?);
    final photo = raw != null ? imgUrl(raw) : null;
    final price = _fmt(listing['price']);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            photo != null
                ? CachedNetworkImage(
                  cacheManager: TeqlifCacheManager(),
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (_, _, _) => _placeholder(context),
                  )
                : _placeholder(context),
            if (price.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(5, 14, 5, 5),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Text(
                    price,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            // ── Sol üst: Sponsorlu ──────────────────────────────────────────
            if (listing['is_sponsored'] == true)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    loc.t("badgeSponsored"),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: ListingBadgeOverlay(listing: listing, badgeSize: 8, pad: 4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    color: AppColors.surfaceVariant(context),
    child: Center(
      child: Icon(
        Icons.image_outlined,
        size: 28,
        color: AppColors.border(context),
      ),
    ),
  );
}
