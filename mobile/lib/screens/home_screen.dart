import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/material.dart";
import "../services/localization_service.dart";
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/image_cache_manager.dart';

import '../services/storage_service.dart';
import '../ui_library/components/buttons/teq_button.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/overlays/teq_toast.dart';
import '../services/listing_service.dart';
import '../providers/listing_interaction_provider.dart';
import '../widgets/shimmer_loading.dart';
import '../utils/once.dart';
import '../utils/error_helper.dart';
import '../utils/number_formatter.dart';
import 'auth/category_onboarding_screen.dart';
import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';

import '../models/listing_filter_state.dart';
import '../ui_library/components/filters/teq_filter_bar.dart';
import '../widgets/network_error_widget.dart';
import '../widgets/stale_data_banner.dart';
import 'viewmodels/home_view_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends ConsumerState<HomeScreen> {
  void refresh({bool bypassCache = true}) => ref.read(homeViewModelProvider.notifier).refresh(bypassCache: bypassCache);

  bool _isLoggedIn = false;
  final ScrollController _scrollCtrl = ScrollController();

  bool _showOnboardingBanner = false;
  final _bannerGuard = OnceGuard();

  @override
  void initState() {
    super.initState();
    _checkAuthAndOnboarding();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(homeViewModelProvider.notifier).loadMore();
    }
  }

  Future<void> _checkAuthAndOnboarding() async {
    final token = await StorageService.getToken();
    final loggedIn = token != null;
    if (mounted) setState(() => _isLoggedIn = loggedIn);

    if (loggedIn) {
      final userInfo = await StorageService.getUserInfo();
      final prefs = await SharedPreferences.getInstance();

      if (userInfo == null) {
        if (mounted) setState(() => _showOnboardingBanner = false);
      } else {
        final done =
            (userInfo['onboarding_completed'] == true) ||
            (prefs.getBool('onboarding_done') == true);
        final skipped = prefs.getBool('onboarding_skipped') == true;
        if (mounted) setState(() => _showOnboardingBanner = !(done || skipped));
      }
    }
  }

  void _clearAll() {
    ref.read(homeViewModelProvider.notifier).clearFilters();
  }

  String _filteredHeader(TranslationPack loc, HomeState state) {
    if (state.isLoading) return loc.t("homeSearchingHeader");
    return loc.t("homeResultsCount", {'count': state.recentListings.length.toString()});
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final homeStateAsync = ref.watch(homeViewModelProvider);
    final state = homeStateAsync.value ?? const HomeState();
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc.t("homeAppBarTitle"),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton.icon(
            key: const Key('home_btn_ilan_ver'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateListingScreen()),
            ),
            icon: const Icon(Icons.add, size: 18, color: kPrimary),
            label: Text(
              loc.t("btnCreateListing"),
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Onboarding banner ────────────────────────────
          if (_showOnboardingBanner)
            _OnboardingBanner(
              onTap: () => _bannerGuard.run(() async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const CategoryOnboardingScreen(fromBanner: true),
                  ),
                );
                if (mounted) {
                  setState(() => _showOnboardingBanner = false);
                }
              }),
            ),
          // ── Filtre bar ───────────────────────────────────
          TeqFilterBar(
            filter: state.filter,
            onChanged: (f) {
              ref.read(homeViewModelProvider.notifier).applyFilter(f);
            },
            showCategory: true,
            showSubcategory: true,
            showCity: true,
            showCondition: true,
            showSort: true,
            showPriceRange: true,
          ),

          // ── İLAN LİSTESİ (SADECE BURASI KAYACAK) ────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(homeViewModelProvider.notifier).refresh(bypassCache: true),
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ══════════════════════════════════════════════════════════
                  // FİLTRE MODU: sadece filtrelenmiş grid
                  // ══════════════════════════════════════════════════════════
                  if (state.hasFilter) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          _filteredHeader(loc, state),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (state.isLoading)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                                childAspectRatio: 0.78,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (_, _) => const ShimmerGridCard(),
                            childCount: 9,
                          ),
                        ),
                      )
                    else if (state.recentListings.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_outlined,
                                size: 56,
                                color: AppColors.border(context),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                loc.t("emptyFilteredListings"),
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              TeqButton.text(
                                key: const Key(
                                  'home_btn_filtreleri_temizle_bos',
                                ),
                                text: loc.t("btnClearFilters"),
                                onPressed: _clearAll,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _GridItem(
                              key: Key(
                                'home_listing_filtered_${state.recentListings[i]['id']}',
                              ),
                              listing: state.recentListings[i],
                              onRemove: () => ref.read(homeViewModelProvider.notifier).removeRecent(i),
                              onTap: () {
                                if (state.recentListings[i]['is_sponsored'] ==
                                    true) {
                                  final cid = state.recentListings[i]['campaign_id'];
                                  if (cid != null) {
                                    AnalyticsService.trackAdClick(cid as int);
                                  }
                                }
                                Navigator.push(
                                  ctx,
                                  MaterialPageRoute(
                                    builder: (_) => ListingDetailScreen(
                                      listing: Map<String, dynamic>.from(
                                        state.recentListings[i],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            childCount: state.recentListings.length,
                          ),
                        ),
                      ),
                  ],

                  // ══════════════════════════════════════════════════════════
                  // NORMAL MOD: Sana Özel (yatay) + En Son (dikey grid)
                  // ══════════════════════════════════════════════════════════
                  if (!state.hasFilter) ...[
                    // ── Geri Bak shelf ────────────────────────────────────
                    if (state.isHesitatedLoading || state.hesitatedListings.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.history, size: 16, color: Colors.orange),
                                  const SizedBox(width: 6),
                                  Text(
                                    loc.t("hesitatedSectionTitle"),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '— ${loc.t("hesitatedSectionSubtitle")}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 130,
                              child: state.isHesitatedLoading && state.hesitatedListings.isEmpty
                                  ? ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      itemCount: 4,
                                      itemBuilder: (_, __) => Container(
                                        width: 100,
                                        margin: const EdgeInsets.only(right: 8),
                                        child: ShimmerBox(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                itemCount: state.hesitatedListings.length,
                                itemBuilder: (ctx, i) {
                                  final item = state.hesitatedListings[i] as Map<String, dynamic>;
                                  final lid = item['id'] as int?;
                                  final raw = item['image_url'] as String?;
                                  final photo = raw != null ? imgUrl(raw) : null;
                                  final price = item['price'] != null
                                      ? TeqNumberFormatter.format(item['price'], fieldKey: 'price', unit: '₺')
                                      : '';
                                  final priceDrop = item['price_dropped'] == true;
                                  final nearOffer = item['price_near_offer'] == true;
                                  final offerCount = (item['offer_count'] as num?)?.toInt() ?? 0;
                                  return GestureDetector(
                                    onTap: () {
                                      if (lid != null) {
                                        AnalyticsService.logInteraction(
                                          itemId: lid,
                                          itemType: 'listing',
                                          interactionType: 'hesitated_shelf_tap',
                                        );
                                      }
                                      Navigator.push(ctx, MaterialPageRoute(
                                        builder: (_) => ListingDetailScreen(
                                          listing: Map<String, dynamic>.from(item),
                                        ),
                                      ));
                                    },
                                    onLongPress: () async {
                                      if (lid == null) return;
                                      ref.read(homeViewModelProvider.notifier).removeHesitated(lid);
                                      TeqToast.success(loc.t('hesitatedDismissed'));
                                    },
                                    child: Container(
                                      width: 100,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: AppColors.card(context),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          if (photo != null)
                                            CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover, cacheManager: TeqlifCacheManager())
                                          else
                                            Container(color: AppColors.surfaceVariant(context)),
                                          if (price.isNotEmpty)
                                            Positioned(
                                              left: 0, right: 0, bottom: 0,
                                              child: Container(
                                                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                                                decoration: const BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [Colors.transparent, Colors.black54],
                                                  ),
                                                ),
                                                child: Text(price,
                                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          // Fiyat düştü badge
                                          if (priceDrop)
                                            Positioned(
                                              top: 4, left: 4,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade600,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text('↓', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                              ),
                                            )
                                          // Teklife yaklaştı badge
                                          else if (nearOffer)
                                            Positioned(
                                              top: 4, left: 4,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade600,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text('✓', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                              ),
                                            ),
                                          // Teklif sayısı badge
                                          if (offerCount > 0)
                                            Positioned(
                                              top: 4, right: 4,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.gavel, color: Colors.white, size: 9),
                                                    const SizedBox(width: 2),
                                                    Text('$offerCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    // ── En Son Eklenenler ──────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.access_time_outlined,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              loc.t("homeRecentListings"),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (state.isLoading && state.recentListings.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                                childAspectRatio: 0.78,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (_, _) => const ShimmerGridCard(),
                            childCount: 9,
                          ),
                        ),
                      ),
                    if (state.hasError && state.recentListings.isNotEmpty)
                      SliverToBoxAdapter(
                        child: StaleDataBanner(onRetry: () => refresh(bypassCache: true)),
                      )
                    else if (state.hasError && state.recentListings.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: NetworkErrorWidget(onRetry: () => refresh(bypassCache: true)),
                      )
                    else if (state.recentListings.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              loc.t("emptyListings"),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _GridItem(
                              key: Key(
                                'home_listing_item_${state.recentListings[i]['id']}',
                              ),
                              listing: state.recentListings[i],
                              onRemove: () => ref.read(homeViewModelProvider.notifier).removeRecent(i),
                              onTap: () {
                                final item = state.recentListings[i];
                                if (item['is_sponsored'] == true) {
                                  final cid = item['campaign_id'];
                                  if (cid != null) {
                                    AnalyticsService.trackAdClick(cid as int);
                                  }
                                } else if (_isLoggedIn) {
                                  final id = item['id'] as int?;
                                  if (id != null) {
                                    final ownerId =
                                        (item['user'] as Map?)?['id'] as int?;
                                    unawaited(
                                      AnalyticsService.logInteraction(
                                        itemId: id,
                                        itemType: 'listing',
                                        interactionType: 'click',
                                        ownerId: ownerId,
                                        pricePoint: item['price'] != null
                                            ? (item['price'] as num).toDouble()
                                            : null,
                                      ),
                                    );
                                  }
                                }
                                Navigator.push(
                                  ctx,
                                  MaterialPageRoute(
                                    builder: (_) => ListingDetailScreen(
                                      listing: Map<String, dynamic>.from(item),
                                    ),
                                  ),
                                );
                              },
                            ),
                            childCount: state.recentListings.length,
                          ),
                        ),
                      ),

                    // ── Sonsuz scroll yükleniyor göstergesi ───────────────
                    if (state.isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── İlan grid tile ──────────────────────────────────────────────────────────
class _GridItem extends ConsumerStatefulWidget {
  final Map<String, dynamic> listing;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _GridItem({
    super.key,
    required this.listing,
    required this.onTap,
    this.onRemove,
  });

  @override
  ConsumerState<_GridItem> createState() => _GridItemState();
}

class _GridItemState extends ConsumerState<_GridItem> {
  late int _likesCount;

  bool get _isLiked {
    final id = widget.listing['id'] as int;
    final map = ref.watch(listingInteractionCacheProvider);
    return map[id] ?? ListingService.getCachedLike(id) ?? (widget.listing['is_liked'] as bool? ?? false);
  }

  @override
  void initState() {
    super.initState();
    _likesCount = widget.listing['likes_count'] as int? ?? 0;
    if (widget.listing['is_sponsored'] == true) {
      final cid = widget.listing['campaign_id'];
      if (cid != null) AnalyticsService.trackAdImpression(cid as int);
    }
  }

  @override
  void didUpdateWidget(_GridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listing['id'] != widget.listing['id']) {
      _likesCount = widget.listing['likes_count'] as int? ?? 0;
      if (widget.listing['is_sponsored'] == true) {
        final cid = widget.listing['campaign_id'];
        if (cid != null) AnalyticsService.trackAdImpression(cid as int);
      }
    }
  }

  Future<void> _markNotInterested() async {
    final loc = ref.read(localizationProvider);
    final listingId = widget.listing['id'] as int?;
    if (listingId == null) return;
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final http.Response resp = await http.post(
        Uri.parse('$kBaseUrl/feed/not-interested/$listingId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 204 && mounted) {
        TeqSnackBar.show(message: loc.t("notInterestedConfirmed"),
          type: TeqSnackBarType.info,
        );
        widget.onRemove?.call();
      }
    } catch (_) {}
  }

  Future<void> _showLongPressMenu() async {
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
              onTap: () {
                Navigator.pop(context);
                _markNotInterested();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike() async {
    // Optimistic UI
    HapticFeedback.lightImpact();
    final id = widget.listing['id'] as int;
    final prevLiked = _isLiked;
    final prevCount = _likesCount;
    setState(() {
      _likesCount += prevLiked ? -1 : 1;
    });
    try {
      final result = await ListingService.toggleFavoriteAndLike(id, prevLiked);
      final newCount = result['likes_count'] as int? ?? _likesCount;
      final newLiked = result['is_liked'] as bool? ?? result['is_favorited'] as bool? ?? !prevLiked;
      widget.listing['likes_count'] = newCount;
      widget.listing['is_liked'] = newLiked;
      if (mounted) {
        setState(() {
          _likesCount = newCount;
        });
      }
    } catch (_) {
      // Hata → eski state'e dön
      widget.listing['likes_count'] = prevCount;
      widget.listing['is_liked'] = prevLiked;
      if (mounted) {
        setState(() {
          _likesCount = prevCount;
        });
      }
    }
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
        : (widget.listing['image_url'] as String?);
    final photo = raw != null ? imgUrl(raw) : null;
    final price = _fmt(widget.listing['price']);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: _showLongPressMenu,
        child: Stack(
          fit: StackFit.expand,
          children: [
            photo != null
                ? CachedNetworkImage(
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    cacheManager: TeqlifCacheManager(),
                    placeholder: (_, _) => const ShimmerBox(),
                    errorWidget: (_, _, _) => _placeholder(context),
                  )
                : _placeholder(context),
            if (price.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(5, 14, 5, 5),
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
            // Sponsorlu rozeti — sol üst köşe
            if (widget.listing['is_sponsored'] == true)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
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
            // PRO rozeti — sağ üst (kalp butonunun altı)
            if (widget.listing['seller_is_premium'] == true)
              Positioned(
                top: 36,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const FaIcon(FontAwesomeIcons.crown, size: 7, color: Colors.white),
                ),
              ),
            // Seller badge — sol alt
            if (widget.listing['seller_badge'] == 'trusted_seller')
              Positioned(
                bottom: price.isNotEmpty ? 26 : 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    loc.t("badgeTrustedSeller"),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else if (widget.listing['seller_badge'] == 'active_seller')
              Positioned(
                bottom: price.isNotEmpty ? 26 : 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    loc.t("badgeActiveSeller"),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            // Trend rozeti — sağ alt
            if (widget.listing['is_trending'] == true)
              Positioned(
                bottom: price.isNotEmpty ? 26 : 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const FaIcon(FontAwesomeIcons.fire, size: 10, color: Colors.white),
                ),
              ),
            // Kalp butonu — sağ üst köşe
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleLike,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.red : Colors.white,
                        size: 16,
                      ),
                      if (_likesCount > 0) ...[
                        const SizedBox(width: 3),
                        Text(
                          '$_likesCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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

class _OnboardingBanner extends ConsumerWidget {
  final VoidCallback onTap;

  const _OnboardingBanner({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF06B6D4).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF06B6D4).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: Color(0xFF06B6D4), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.t("onboardingBannerTitle"),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF06B6D4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.t("onboardingBannerSubtitle"),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTap,
            child: Text(
              loc.t("onboardingBannerCta"),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF06B6D4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
