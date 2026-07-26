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
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../services/listing_service.dart';
import '../widgets/shimmer_loading.dart';
import '../utils/once.dart';
import 'auth/category_onboarding_screen.dart';
import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';

import '../models/listing_filter_state.dart';
import '../widgets/listing_filter_bar.dart';
import '../widgets/network_error_widget.dart';
import '../widgets/stale_data_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends ConsumerState<HomeScreen> {
  void refresh({bool bypassCache = true}) => _load(bypassCache: bypassCache);
  // En Son Eklenenler — dikey grid, sonsuz scroll
  List<dynamic> _recentListings = [];
  bool _recentLoading = true;
  bool _recentLoadingMore = false;
  bool _recentExhausted = false;
  int _recentPage = 0;

  // "Geri Bak" — tereddüt edilip teklif gönderilmeyen ilanlar
  List<dynamic> _hesitatedListings = [];

  // Filtreli sonuçlar (filtre aktifken _recentListings'in yerine geçer)
  bool _isLoggedIn = false;
  bool _networkError = false;
  ListingFilterState _filter = const ListingFilterState();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  final ScrollController _scrollCtrl = ScrollController();

  bool _showOnboardingBanner = false;
  final _bannerGuard = OnceGuard();

  bool get _hasFilter => !_filter.isEmpty || _searchQuery.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _searchQuery != query) {
        setState(() => _searchQuery = query);
        _load();
      }
    });
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMoreRecent();
    }
  }

  // ── Ana yükleme ────────────────────────────────────────────────────────────

  /// [bypassCache]: pull-to-refresh'te true — Hive okuma atlanır, cache ezilir.
  Future<void> _load({bool bypassCache = false}) async {
    _networkError = false;
    _recentPage = 0;
    _recentExhausted = false;

    final token = await StorageService.getToken();
    final loggedIn = token != null;
    if (mounted) setState(() => _isLoggedIn = loggedIn);

    if (loggedIn) {
      final userInfo = await StorageService.getUserInfo();
      final prefs = await SharedPreferences.getInstance();

      if (userInfo == null) {
        // Profil henüz yüklenemediyse banner'ı gösterme
        if (mounted) setState(() => _showOnboardingBanner = false);
      } else {
        final done =
            (userInfo['onboarding_completed'] == true) ||
            (prefs.getBool('onboarding_done') == true);
        final skipped = prefs.getBool('onboarding_skipped') == true;
        if (mounted) setState(() => _showOnboardingBanner = !(done || skipped));
      }
    }

    if (_hasFilter) {
      await _loadFiltered(token);
    } else {
      // Paralel yükleme: ForYou beklenmeden arka planda başlar
      await _loadRecent(token, bypassCache: bypassCache);
      if (loggedIn) _loadHesitated(token);
    }
  }

  Future<void> _loadHesitated(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/feed/hesitated'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as List;
        setState(() => _hesitatedListings = data);
      }
    } catch (_) {}
  }

  // ── En Son Eklenenler (dikey grid, /api/listings) ─────────────────────────

  /// SWR stream: filtre yoksa Hive cache önce, sonra API. Filtre varsa her zaman API.
  Future<void> _loadRecent(String? token, {bool bypassCache = false}) async {
    if (!mounted) return;
    setState(() {
      _recentLoading = true;
      _recentListings = [];
    });
    try {
      await for (final listings in ApiService.get<List<dynamic>>(
        url: '$kBaseUrl/feed/recent',
        cacheKey: _hasFilter ? null : 'home_feed_recent',
        cacheTtl: const Duration(minutes: 5),
        bypassCache: bypassCache,
        fromJson: (raw) => raw as List,
      )) {
        if (!mounted) return;
        setState(() {
          _recentListings = listings;
          _recentLoading = false;
          _recentPage = 1;
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] _loadRecent: $e');
      if (!mounted) return;
      setState(() {
        _networkError = true;
        _recentLoading = false;
      });
    }
  }

  Future<void> _loadMoreRecent() async {
    if (_recentLoadingMore || _recentExhausted || _hasFilter) return;
    setState(() => _recentLoadingMore = true);
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/feed/recent?page=$_recentPage'),
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final more = jsonDecode(resp.body) as List;
        if (more.isEmpty) {
          setState(() {
            _recentExhausted = true;
            _recentLoadingMore = false;
          });
        } else {
          setState(() {
            _recentListings = [..._recentListings, ...more];
            _recentPage++;
            _recentLoadingMore = false;
          });
        }
      } else {
        setState(() => _recentLoadingMore = false);
      }
    } catch (_) {
      if (mounted) setState(() => _recentLoadingMore = false);
    }
  }

  // ── Filtrelenmiş sonuçlar ──────────────────────────────────────────────────

  Future<void> _loadFiltered(String? token) async {
    if (!mounted) return;
    setState(() {
      _recentLoading = true;
      _recentListings = [];
    });
    try {
      final params = <String, String>{};
      if (_filter.category != null) params['category'] = _filter.category!;
      if (_filter.subcategory != null) params['subcategory'] = _filter.subcategory!;
      if (_filter.city != null) params['location'] = _filter.city!;
      if (_filter.condition != null) params['condition'] = _filter.condition!;
      if (_filter.sortBy != null) params['sort_by'] = _filter.sortBy!;
      if (_filter.minPrice != null) params['min_price'] = _filter.minPrice!.toStringAsFixed(0);
      if (_filter.maxPrice != null) params['max_price'] = _filter.maxPrice!.toStringAsFixed(0);
      if (_searchQuery.isNotEmpty) params['q'] = _searchQuery;
      final uri = Uri.parse(
        '$kBaseUrl/listings',
      ).replace(queryParameters: params);
      final resp = await http.get(
        uri,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() {
          _recentListings = jsonDecode(resp.body) as List;
          _recentLoading = false;
        });
      } else {
        setState(() {
          _recentLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _recentLoading = false);
    }
  }

  void _clearAll() {
    _searchController.clear();
    setState(() {
      _filter = const ListingFilterState();
      _searchQuery = '';
    });
    _load();
  }

  String _filteredHeader(TranslationPack loc) {
    if (_recentLoading) return loc.t("homeSearchingHeader");
    return loc.t("homeResultsCount", {'count': _recentListings.length.toString()});
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.read(localizationProvider);
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
          ListingFilterBar(
            filter: _filter,
            onChanged: (f) {
              setState(() => _filter = f);
              if (!f.isEmpty) {
                AnalyticsService.trackEvent('filter_applied', {
                  if (f.category != null) 'category': f.category!,
                  'source': 'home',
                });
              }
              _load();
            },
            showCategory: true,
            showSubcategory: true,
            showCity: true,
            showCondition: true,
            showSort: true,
            showPriceRange: true,
          ),

          // ── Arama kutusu ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TeqTextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              hintText: loc.t("searchHintTextListing"),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
            ),
          ),

          // ── İLAN LİSTESİ (SADECE BURASI KAYACAK) ────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(bypassCache: true),
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ══════════════════════════════════════════════════════════
                  // FİLTRE MODU: sadece filtrelenmiş grid
                  // ══════════════════════════════════════════════════════════
                  if (_hasFilter) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          _filteredHeader(loc),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (_recentLoading)
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
                    else if (_recentListings.isEmpty)
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
                                'home_listing_filtered_${_recentListings[i]['id']}',
                              ),
                              listing: _recentListings[i],
                              onRemove: () =>
                                  setState(() => _recentListings.removeAt(i)),
                              onTap: () {
                                if (_recentListings[i]['is_sponsored'] ==
                                    true) {
                                  final cid = _recentListings[i]['campaign_id'];
                                  if (cid != null) {
                                    AnalyticsService.trackAdClick(cid as int);
                                  }
                                }
                                Navigator.push(
                                  ctx,
                                  MaterialPageRoute(
                                    builder: (_) => ListingDetailScreen(
                                      listing: Map<String, dynamic>.from(
                                        _recentListings[i],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            childCount: _recentListings.length,
                          ),
                        ),
                      ),
                  ],

                  // ══════════════════════════════════════════════════════════
                  // NORMAL MOD: Sana Özel (yatay) + En Son (dikey grid)
                  // ══════════════════════════════════════════════════════════
                  if (!_hasFilter) ...[
                    // ── Geri Bak shelf ────────────────────────────────────
                    if (_hesitatedListings.isNotEmpty)
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
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                itemCount: _hesitatedListings.length,
                                itemBuilder: (ctx, i) {
                                  final item = _hesitatedListings[i];
                                  final raw = item['image_url'] as String?;
                                  final photo = raw != null ? imgUrl(raw) : null;
                                  final price = item['price'] != null
                                      ? '${(item['price'] as num).toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} ₺'
                                      : '';
                                  return GestureDetector(
                                    onTap: () => Navigator.push(ctx, MaterialPageRoute(
                                      builder: (_) => ListingDetailScreen(
                                        listing: Map<String, dynamic>.from(item),
                                      ),
                                    )),
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
                    if (_recentLoading && _recentListings.isEmpty)
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
                    if (_networkError && _recentListings.isNotEmpty)
                      SliverToBoxAdapter(
                        child: StaleDataBanner(onRetry: _load),
                      )
                    else if (_networkError && _recentListings.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: NetworkErrorWidget(onRetry: _load),
                      )
                    else if (_recentListings.isEmpty)
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
                                'home_listing_item_${_recentListings[i]['id']}',
                              ),
                              listing: _recentListings[i],
                              onRemove: () =>
                                  setState(() => _recentListings.removeAt(i)),
                              onTap: () {
                                final item = _recentListings[i];
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
                            childCount: _recentListings.length,
                          ),
                        ),
                      ),

                    // ── Sonsuz scroll yükleniyor göstergesi ───────────────
                    if (_recentLoadingMore)
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
  late bool _isLiked;

  @override
  void initState() {
    super.initState();
    final id = widget.listing['id'] as int;
    _likesCount = widget.listing['likes_count'] as int? ?? 0;
    _isLiked =
        ListingService.getCachedLike(id) ??
        (widget.listing['is_liked'] as bool? ?? false);
    if (widget.listing['is_sponsored'] == true) {
      final cid = widget.listing['campaign_id'];
      if (cid != null) AnalyticsService.trackAdImpression(cid as int);
    }
  }

  @override
  void didUpdateWidget(_GridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.listing['id'] as int;
    if (oldWidget.listing['id'] != id) {
      // Farklı ilan → tamamen sıfırla
      _likesCount = widget.listing['likes_count'] as int? ?? 0;
      _isLiked =
          ListingService.getCachedLike(id) ??
          (widget.listing['is_liked'] as bool? ?? false);
      if (widget.listing['is_sponsored'] == true) {
        final cid = widget.listing['campaign_id'];
        if (cid != null) AnalyticsService.trackAdImpression(cid as int);
      }
    } else {
      // Aynı ilan → cache'te güncelleme varsa uygula
      final cached = ListingService.getCachedLike(id);
      if (cached != null && cached != _isLiked) _isLiked = cached;
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
    final prevLiked = _isLiked;
    final prevCount = _likesCount;
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });
    try {
      final id = widget.listing['id'] as int;
      final result = await ListingService.toggleLike(id);
      final newCount = result['likes_count'] as int? ?? _likesCount;
      final newLiked = result['is_liked'] as bool? ?? _isLiked;
      widget.listing['likes_count'] = newCount;
      widget.listing['is_liked'] = newLiked;
      // Favorites API ile senkronize et
      final token = await StorageService.getToken();
      if (token != null) {
        if (newLiked) {
          http.post(
            Uri.parse('$kBaseUrl/favorites/$id'),
            headers: {'Authorization': 'Bearer $token'},
          );
        } else {
          http.delete(
            Uri.parse('$kBaseUrl/favorites/$id'),
            headers: {'Authorization': 'Bearer $token'},
          );
        }
      }
      if (mounted) {
        setState(() {
          _likesCount = newCount;
          _isLiked = newLiked;
        });
      }
    } catch (_) {
      // Hata → eski state'e dön
      widget.listing['likes_count'] = prevCount;
      widget.listing['is_liked'] = prevLiked;
      if (mounted) {
        setState(() {
          _isLiked = prevLiked;
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
    final loc = ref.read(localizationProvider);
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
