import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/city_service.dart';

import '../services/listing_service.dart';
import '../services/storage_service.dart';
import '../widgets/shimmer_loading.dart';
import '../utils/once.dart';
import 'auth/category_onboarding_screen.dart';
import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';

import '../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  void refresh({bool bypassCache = true}) => _load(bypassCache: bypassCache);
  // En Son Eklenenler — dikey grid, sonsuz scroll
  List<dynamic> _recentListings = [];
  bool _recentLoading = true;
  bool _recentLoadingMore = false;
  bool _recentExhausted = false;
  int _recentPage = 0;

  // Filtreli sonuçlar (filtre aktifken _recentListings'in yerine geçer)
  bool _isLoggedIn = false;
  String? _error;
  String? _selectedCategory;
  String? _selectedCity;
  List<String> _cities = [];
  final ScrollController _scrollCtrl = ScrollController();

  bool _showOnboardingBanner = false;
  final _bannerGuard = OnceGuard();

  List<Map<String, dynamic>> _buildCategories(AppLocalizations l) => [
    {
      'slug': 'elektronik',
      'label': l.catElectronics,
      'icon': Icons.devices_outlined,
    },
    {
      'slug': 'vasita',
      'label': l.catVehicles,
      'icon': Icons.directions_car_outlined,
    },
    {
      'slug': 'emlak',
      'label': l.catRealEstate,
      'icon': Icons.home_work_outlined,
    },
    {'slug': 'giyim', 'label': l.catClothing, 'icon': Icons.checkroom_outlined},
    {
      'slug': 'spor',
      'label': l.catSports,
      'icon': Icons.sports_soccer_outlined,
    },
    {'slug': 'kitap', 'label': l.catBooks, 'icon': Icons.menu_book_outlined},
    {'slug': 'ev', 'label': l.catHomeLife, 'icon': Icons.home_outlined},
    {'slug': 'diger', 'label': l.catOther, 'icon': Icons.more_horiz},
  ];

  bool get _hasFilter => _selectedCategory != null || _selectedCity != null;

  @override
  void initState() {
    super.initState();
    _load();
    CityService.getCities().then((c) {
      if (mounted) setState(() => _cities = c);
    });
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
      _loadMoreRecent();
    }
  }

  // ── Ana yükleme ────────────────────────────────────────────────────────────

  /// [bypassCache]: pull-to-refresh'te true — Hive okuma atlanır, cache ezilir.
  Future<void> _load({bool bypassCache = false}) async {
    _error = null;
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
    }
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
      if (_recentListings.isEmpty) {
        final l = AppLocalizations.of(context)!;
        setState(() {
          _error = l.errorConnection;
          _recentLoading = false;
        });
      } else {
        setState(() => _recentLoading = false);
      }
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
      if (_selectedCategory != null) params['category'] = _selectedCategory!;
      if (_selectedCity != null) params['location'] = _selectedCity!;
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
    setState(() {
      _selectedCategory = null;
      _selectedCity = null;
    });
    _load();
  }

  String _filteredHeader(AppLocalizations l) {
    if (_recentLoading) return l.homeSearchingHeader;
    return l.homeResultsCount(_recentListings.length);
  }

  void _showCityPicker() {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                l.citySelectTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
            ListTile(
              title: Text(l.cityAll),
              leading: Icon(
                _selectedCity == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: kPrimary,
                size: 20,
              ),
              onTap: () {
                setState(() => _selectedCity = null);
                Navigator.pop(ctx);
                _load();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: controller,
                itemCount: _cities.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final city = _cities[i];
                  final selected = _selectedCity == city;
                  return ListTile(
                    title: Text(
                      city,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: selected
                            ? kPrimary
                            : AppColors.textPrimary(context),
                      ),
                    ),
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: kPrimary,
                      size: 20,
                    ),
                    onTap: () {
                      setState(() => _selectedCity = city);
                      Navigator.pop(ctx);
                      _load();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final categories = _buildCategories(l);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.homeAppBarTitle,
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
              l.btnCreateListing,
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
          // ── Kategori ikonları ────────────────────────────
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                final slug = cat['slug'] as String;
                final isSelected = _selectedCategory == slug;
                return GestureDetector(
                  key: Key('home_cat_$slug'),
                  onTap: () {
                    setState(
                      () => _selectedCategory = isSelected ? null : slug,
                    );
                    _load();
                  },
                  child: Container(
                    width: 68,
                    margin: const EdgeInsets.only(right: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? kPrimary
                                : AppColors.primaryBg(context),
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(color: kPrimaryDark, width: 1.5)
                                : null,
                          ),
                          child: Icon(
                            cat['icon'] as IconData,
                            color: isSelected ? Colors.white : kPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cat['label'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? kPrimary
                                : AppColors.textSecondary(context),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Filtre chip'leri satırı ──────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Şehir seçici chip
                  GestureDetector(
                    key: const Key('home_chip_sehir_sec'),
                    onTap: _cities.isEmpty ? null : _showCityPicker,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedCity != null
                            ? kPrimary.withValues(alpha: 0.1)
                            : AppColors.surface(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedCity != null
                              ? kPrimary
                              : AppColors.border(context),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: _selectedCity != null
                                ? kPrimary
                                : AppColors.textSecondary(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _selectedCity ?? l.fieldCity,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _selectedCity != null
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: _selectedCity != null
                                  ? kPrimary
                                  : AppColors.textSecondary(context),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: _selectedCity != null
                                ? kPrimary
                                : AppColors.textSecondary(context),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Aktif kategori chip
                  if (_selectedCategory != null) ...[
                    const SizedBox(width: 8),
                    _ActiveFilterChip(
                      label:
                          categories.firstWhere(
                                (c) => c['slug'] == _selectedCategory,
                              )['label']
                              as String,
                      onRemove: () {
                        setState(() => _selectedCategory = null);
                        _load();
                      },
                    ),
                  ],

                  // Aktif şehir chip
                  if (_selectedCity != null) ...[
                    const SizedBox(width: 8),
                    _ActiveFilterChip(
                      label: _selectedCity!,
                      onRemove: () {
                        setState(() => _selectedCity = null);
                        _load();
                      },
                    ),
                  ],

                  // Filtreleri Temizle
                  if (_hasFilter) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      key: const Key('home_btn_filtreleri_temizle'),
                      onTap: _clearAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.close,
                              size: 13,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l.btnClearFilters,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

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
                          _filteredHeader(l),
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
                                l.emptyFilteredListings,
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                key: const Key(
                                  'home_btn_filtreleri_temizle_bos',
                                ),
                                onPressed: _clearAll,
                                child: Text(l.btnClearFilters),
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
                              l.homeRecentListings,
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
                      )
                    else if (_error != null && _recentListings.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                key: const Key('home_btn_tekrar_dene'),
                                onPressed: _load,
                                child: Text(l.btnRetry),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_recentListings.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              l.emptyListings,
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

// ── Aktif filtre chip'i ─────────────────────────────────────────────────────
class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: kPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            key: Key('home_chip_kaldir_$label'),
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: kPrimary),
          ),
        ],
      ),
    );
  }
}

// ── İlan grid tile ──────────────────────────────────────────────────────────
class _GridItem extends StatefulWidget {
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
  State<_GridItem> createState() => _GridItemState();
}

class _GridItemState extends State<_GridItem> {
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
    final l = AppLocalizations.of(context)!;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.notInterestedConfirmed),
            duration: const Duration(seconds: 2),
          ),
        );
        widget.onRemove?.call();
      }
    } catch (_) {}
  }

  Future<void> _showLongPressMenu() async {
    final l = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.thumb_down_alt_outlined),
              title: Text(l.notInterested),
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
                  child: const Text(
                    'Sponsorlu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            // Seller badge — sol alt (sponsorlu yokken sol üst)
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
                    AppLocalizations.of(context)!.badgeTrustedSeller,
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
                    AppLocalizations.of(context)!.badgeActiveSeller,
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
                  child: const Text('🔥', style: TextStyle(fontSize: 10)),
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

class _OnboardingBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _OnboardingBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
                    l.onboardingBannerTitle,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF06B6D4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.onboardingBannerSubtitle,
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
              l.onboardingBannerCta,
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
