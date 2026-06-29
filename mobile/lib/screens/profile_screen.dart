import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../core/app_exception.dart';
import '../core/logger_service.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../utils/error_helper.dart';
import '../utils/start_stream_helper.dart';
import '../widgets/shimmer_loading.dart';
import 'follow_list_screen.dart';
import 'listing_detail_screen.dart';
import 'create_listing_screen.dart';
import 'pro_hub_screen.dart';
import 'notification_settings_screen.dart';
import 'blocked_users_screen.dart';
import 'purchases_screen.dart';
import 'account_info_screen.dart';
import '../services/wallet_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _listings = [];
  List<dynamic> _purchases = [];
  bool _loading = true;
  bool _purchasesLoading = false;
  int _purchasesPage = 1;
  bool _purchasesHasMore = false;
  int? _tuciBalance;
  List<dynamic> _tuciHistory = [];

  // ── Arama & kategori filtresi ─────────────────────────────────────────────
  String _searchQuery = '';
  String? _selectedCategory;
  final _searchCtrl = TextEditingController();

  List<String> get _categories => _listings
      .map((l) => l['category'] as String?)
      .whereType<String>()
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<dynamic> get _filteredListings {
    var r = _listings;
    if (_selectedCategory != null) {
      r = r.where((l) => l['category'] == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      r = r.where((l) => (l['title'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    return r;
  }

  /// Aktif stream aboneliklerinin takibi — dispose'da iptal edilir.
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadPurchases() async {
    if (_purchasesLoading) return;
    if (mounted) setState(() => _purchasesLoading = true);
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/auth/me/purchases'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as List?;
        if (mounted) setState(() { _purchases = decoded ?? []; });
      }
    } catch (_) {
      // sessizce geç
    } finally {
      if (mounted) setState(() => _purchasesLoading = false);
    }
  }

  /// Cüzdan bakiyesi için hafif yenileme (wallet butonuna basıldığında).
  Future<void> _loadWallet({bool bypassCache = false}) async {
    await for (final data in WalletService.getBalanceStream(
      bypassCache: bypassCache,
    )) {
      if (!mounted) return;
      setState(() {
        _tuciBalance = data['balance'] as int?;
        _tuciHistory = data['transactions'] as List? ?? [];
      });
    }
  }

  /// SWR paralel yükleme: profil, ilanlar ve cüzdan aynı anda başlar.
  /// Her stream hem Hive cache'ten (anlık) hem API'den (taze) emit eder.
  /// [bypassCache]: pull-to-refresh için cache okumayı atlar, cache'i ezar.
  Future<void> _load({bool bypassCache = false}) async {
    // Önceki abonelikleri iptal et (tekrarlı _load çağrıları için)
    for (final sub in _subs) { sub.cancel(); }
    _subs.clear();

    // Kimlik bilgisi: güvenli depodan al (hızlı, bir kez)
    final localInfo = await StorageService.getUserInfo();
    final username = localInfo?['username'] as String?;
    final userId   = localInfo?['id'] as int?;

    if (!mounted) return;
    // Güvenli depodan temel bilgileri anında göster (cache gelene kadar).
    // Avatar URL'si memory'den senkron eklenir — boş avatar gösterilmez.
    if (_user == null && localInfo != null) {
      final avatarUrl = StorageService.cachedAvatarUrl;
      if (avatarUrl != null) localInfo['profile_image_url'] = avatarUrl;
      setState(() { _user = localInfo; _loading = true; });
    }

    if (username == null || userId == null) {
      setState(() => _loading = false);
      return;
    }

    // Her stream bağımsız çalışır — UI her event'te güncellenir
    _subs.add(
      // ── Profil (cache: user_profile_data) ────────────────────────────────
      ApiService.get<Map<String, dynamic>>(
        url: '$kBaseUrl/users/$username',
        cacheKey: StorageService.cacheProfile,
        cacheTtl: const Duration(minutes: 10),
        bypassCache: bypassCache,
        fromJson: (raw) => Map<String, dynamic>.from(raw as Map),
      ).listen(
        (user) {
          // Avatar URL'yi kalıcı kaydet — sonraki açılışta anında gösterilir
          final avatarUrl = user['profile_image_url'] as String?;
          if (avatarUrl != null && avatarUrl.isNotEmpty) {
            StorageService.saveAvatarUrl(avatarUrl);
          }
          
          // Profil bilgisi güncellenince is_premium dahil tüm bilgileri locale kaydet.
          // /users/{username} endpoint'i email döndurmüyor, localInfo'dan alıyoruz.
          if (userId != null) {
            StorageService.saveUserInfo(
              id: user['id'] as int? ?? userId,
              email: localInfo?['email'] as String? ?? '',
              username: user['username'] as String? ?? username ?? '',
              fullName: user['full_name'] as String? ?? '',
              isPremium: user['is_premium'] == true,
              onboardingCompleted: user['onboarding_completed'] == true,
              isVerified: user['is_verified'] == true,
              phoneVerified: user['phone_verified'] == true,
            );
          }
          
          if (mounted) setState(() { _user = user; _loading = false; });
        },
        onError: (e) {
          LoggerService.instance.warning('ProfileScreen', 'Profil yüklenemedi: $e');
          if (mounted) setState(() => _loading = false);
        },
      ),
    );

    _subs.add(
      // ── İlanlar (cache: user_listings_data) ──────────────────────────────
      ApiService.get<List<dynamic>>(
        url: '$kBaseUrl/listings/my',
        cacheKey: StorageService.cacheUserListings,
        cacheTtl: const Duration(minutes: 5),
        bypassCache: bypassCache,
        fromJson: (raw) => raw as List,
      ).listen(
        (listings) {
          if (mounted) setState(() { _listings = listings; _loading = false; });
        },
        onError: (_) { if (mounted) setState(() => _loading = false); },
      ),
    );

    // ── Satın alma geçmişi (fire-and-forget ilk açılışta) ────────────────
    _loadPurchases();

    _subs.add(
      // ── Cüzdan (cache: user_wallet_data) ─────────────────────────────────
      WalletService.getBalanceStream(bypassCache: bypassCache).listen(
        (wallet) {
          if (mounted) {
            setState(() {
              _tuciBalance = wallet['balance'] as int?;
              _tuciHistory = wallet['transactions'] as List? ?? [];
            });
          }
        },
      ),
    );
  }


  String _buildImageUrl(String url) {
    if (url.startsWith('http')) return url;
    final origin = kBaseUrl.replaceFirst(RegExp(r'/api.*'), '');
    return '$origin$url';
  }

  /// Profil fotoğrafı — CachedNetworkImage ile disk'e önbelleğe alınır.
  Widget _buildAvatar({required String? imageUrl, required double radius, required Widget fallback}) {
    final bg = AppColors.primaryBg(context);
    if (imageUrl == null) {
      return CircleAvatar(radius: radius, backgroundColor: bg, child: fallback);
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, __) => CircleAvatar(radius: radius, backgroundColor: bg, child: fallback),
        errorWidget:  (_, __, ___) => CircleAvatar(radius: radius, backgroundColor: bg, child: fallback),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _SettingsScreen(user: _user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Yerel önbellekte hiç veri yoksa (ilk kurulum) tam ekran spinner
    if (_loading && _user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    final fullName = _user?['full_name'] ?? _user?['username'] ?? 'Kullanıcı';
    final username = _user?['username'] ?? '';
    final email = _user?['email'] ?? '';
    final isVerified = _user?['is_verified'] == true;
    final phoneVerified = _user?['phone_verified'] == true;
    final isFullyVerified = isVerified && phoneVerified;
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        leading: PopupMenuButton<String>(
          offset: const Offset(8, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 6,
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kPrimary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kPrimary.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 22),
          ),
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'listing',
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.sell_outlined, color: kPrimary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'İlan Ekle',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'live',
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.videocam_outlined,
                        color: Colors.red, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Canlı Yayın Aç',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
          onSelected: (val) {
            if (val == 'listing') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CreateListingScreen(),
                ),
              );
            } else if (val == 'live') {
              showStartStreamDialog(context);
            }
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '@$username',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            if (isFullyVerified) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.verified,
                color: Colors.blue,
                size: 18,
              ),
            ],
          ],
        ),
        actions: [
          // Cüzdan
          GestureDetector(
            onTap: () {
              _loadWallet(bypassCache: true);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WalletScreen(
                    initialBalance: _tuciBalance,
                    initialHistory: _tuciHistory,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 22),
                  // Sabit yükseklik: text göründüğünde de gösterilmediğinde de
                  // Settings ikonu ile aynı toplam yükseklikte kalsın
                  SizedBox(
                    height: 11,
                    child: _tuciBalance != null
                        ? Text(
                            '$_tuciBalance T',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB8860B),
                              height: 1.1,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
          // Ayarlar — cüzdanla özdeş Column yapısı, alt SizedBox hizayı korur
          GestureDetector(
            key: const Key('profile_btn_ayarlar'),
            onTap: _openSettings,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.settings_outlined, size: 22),
                  SizedBox(height: 11), // cüzdan text alanıyla eşit yükseklik
                ],
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kPrimary,
        onRefresh: () => _load(bypassCache: true),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // ── Profil başlık bölümü ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        _buildAvatar(
                          imageUrl: (_user?['profile_image_url'] as String?)?.isNotEmpty == true
                              ? _buildImageUrl(_user!['profile_image_url'] as String)
                              : null,
                          radius: 40,
                          fallback: Text(
                                  initial,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    color: kPrimary,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 20),
                        // İstatistikler
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatItem(count: _listings.length, label: AppLocalizations.of(context)!.profileListingCount),
                              GestureDetector(
                                key: const Key('profile_stat_takipci'),
                                onTap: _user?['id'] != null
                                    ? () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FollowListScreen(
                                              userId: _user!['id'] as int,
                                              type: FollowListType.followers,
                                              title: AppLocalizations.of(context)!.profileFollowersList,
                                            ),
                                          ),
                                        )
                                    : null,
                                child: _StatItem(
                                  count: (_user?['follower_count'] as int?) ?? 0,
                                  label: AppLocalizations.of(context)!.profileFollowers,
                                ),
                              ),
                              GestureDetector(
                                key: const Key('profile_stat_takip'),
                                onTap: _user?['id'] != null
                                    ? () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FollowListScreen(
                                              userId: _user!['id'] as int,
                                              type: FollowListType.following,
                                              title: AppLocalizations.of(context)!.profileFollowingList,
                                            ),
                                          ),
                                        )
                                    : null,
                                child: _StatItem(
                                  count: (_user?['following_count'] as int?) ?? 0,
                                  label: AppLocalizations.of(context)!.profileFollowing,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Ad ve email
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if (_user?['is_premium'] == true) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0369A1), Color(0xFF0EA5E9)],
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                        if ((_user?['bio'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            _user!['bio'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary(context),
                              height: 1.4,
                            ),
                          ),
                        ],
                        if ((_user?['website_url'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () async {
                              final raw = _user!['website_url'] as String;
                              final uri = Uri.tryParse(raw);
                              if (uri != null && await canLaunchUrl(uri)) {
                                launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.link_rounded, size: 14, color: Color(0xFF0EA5E9)),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    (_user!['website_url'] as String)
                                        .replaceFirst(RegExp(r'^https?://'), ''),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF0EA5E9),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Profili Düzenle butonu
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: OutlinedButton(
                      key: const Key('profile_btn_profil_duzenle'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _EditProfileScreen(user: _user),
                        ),
                      ).then((_) => _load()),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 36),
                        side: BorderSide(color: AppColors.border(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        foregroundColor: AppColors.textPrimary(context),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(AppLocalizations.of(context)!.btnEditProfile),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Separator
                  Divider(height: 1, color: AppColors.divider(context)),
                ],
              ),
            ),

            // ── Arama & Kategori filtresi ──
            if (!_loading || _listings.isNotEmpty)
              SliverToBoxAdapter(
                child: ListingFilter(
                  searchCtrl: _searchCtrl,
                  searchQuery: _searchQuery,
                  selectedCategory: _selectedCategory,
                  categories: _categories,
                  onSearchChanged: (v) => setState(() => _searchQuery = v.trim()),
                  onSearchCleared: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                  onCategorySelected: (cat) =>
                      setState(() => _selectedCategory = cat),
                ),
              ),

            // ── İlanlar grid ──
            if (_loading)
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
                    (_, __) => const ShimmerGridCard(),
                    childCount: 9,
                  ),
                ),
              )
            else if (_listings.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Builder(
                  builder: (context) {
                    final l = AppLocalizations.of(context)!;
                    return Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.grid_off_outlined,
                                size: 52, color: Color(0xFFD1D5DB)),
                            const SizedBox(height: 12),
                            Text(
                              l.emptyListings,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.profileFirstListing,
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else if (_filteredListings.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 52, color: Color(0xFFD1D5DB)),
                        SizedBox(height: 12),
                        Text(
                          'Sonuç bulunamadı',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _ListingGridItem(
                    key: Key('profile_listing_${_filteredListings[i]['id']}'),
                    listing: _filteredListings[i],
                  ),
                  childCount: _filteredListings.length,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Arama + Kategori filtresi widget'ı (ProfileScreen & PublicProfileScreen) ──

class ListingFilter extends StatefulWidget {
  final TextEditingController searchCtrl;
  final String searchQuery;
  final String? selectedCategory;
  final List<String> categories;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final ValueChanged<String?> onCategorySelected;

  const ListingFilter({
    super.key,
    required this.searchCtrl,
    required this.searchQuery,
    required this.selectedCategory,
    required this.categories,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onCategorySelected,
  });

  @override
  State<ListingFilter> createState() => _ListingFilterState();
}

class _ListingFilterState extends State<ListingFilter> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 20, color: Colors.white70),
                const SizedBox(width: 8),
                const Text(
                  'Filtre',
                  style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(height: 0, width: double.infinity),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: widget.searchCtrl,
                  onChanged: widget.onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'İlan başlığı ara...',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary(context)),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: widget.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: widget.onSearchCleared,
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kPrimary),
                    ),
                    filled: true,
                    fillColor: AppColors.surface(context),
                  ),
                ),
              ),
              if (widget.categories.isNotEmpty)
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _CategoryChip(
                        label: 'Tümü',
                        selected: widget.selectedCategory == null,
                        onTap: () => widget.onCategorySelected(null),
                      ),
                      ...widget.categories.map((cat) => _CategoryChip(
                            label: cat,
                            selected: widget.selectedCategory == cat,
                            onTap: () => widget.onCategorySelected(cat),
                          )),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}


class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? kPrimary : AppColors.surface(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? kPrimary : AppColors.border(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textPrimary(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
        ),
      ],
    );
  }
}

class _ListingGridItem extends StatelessWidget {
  final dynamic listing;
  const _ListingGridItem({super.key, required this.listing});

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
    final imgs = listing['image_urls'] as List? ?? [];
    final _raw = imgs.isNotEmpty
        ? imgs[0] as String
        : listing['image_url'] as String?;
    final imageUrl = _raw != null ? imgUrl(_raw) : null;
    final price = _fmt(listing['price']);

    final isSponsored = listing['is_sponsored'] == true;
    final isPassive = listing['is_active'] == false;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(
              listing: Map<String, dynamic>.from(listing)),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorWidget: (_, __, ___) => _placeholder(context),
                )
              : _placeholder(context),
          // Pasif ilanlar için karartma overlay
          if (isPassive)
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
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
          // Pasif badge — sol üst köşe
          if (isPassive)
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Pasif',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
              ),
            )
          else if (isSponsored)
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Sponsorlu',
                  style: TextStyle(
                    color: Color(0xFF7c5700),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        color: AppColors.surfaceVariant(context),
        child: Center(
          child: Icon(Icons.image_outlined,
              size: 28, color: AppColors.border(context)),
        ),
      );
}

// ── Ayarlar ekranı ────────────────────────────────────────────────────────────

class _SettingsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? user;

  const _SettingsScreen({this.user});

  @override
  ConsumerState<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<_SettingsScreen> {
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  // widget.user stale olabilir — StorageService'ten güncel değer okunur
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    // widget.user'dan ön değer al (anlık gösterim için)
    _isPremium = widget.user?['is_premium'] == true;
    _loadBiometricState();
    _loadPremiumStatus();
  }

  Future<void> _loadBiometricState() async {
    final available = await BiometricService.isAvailable();
    final enabled = await StorageService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  /// StorageService'ten güncel PRO statüsünü çeker.
  /// Admin panelinden yapılan değişiklikler profil açılışında
  /// saveUserInfo ile kaydedildiğinden burada güncel değer okunur.
  Future<void> _loadPremiumStatus() async {
    final info = await StorageService.getUserInfo();
    if (mounted && info != null) {
      setState(() => _isPremium = info['is_premium'] == true);
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Açarken bir kez doğrula
      final ok = await BiometricService.authenticate(
        reason: 'Face ID\'yi etkinleştirmek için doğrulayın',
      );
      if (!ok) return;
    }
    await StorageService.setBiometricEnabled(value);
    if (mounted) setState(() => _biometricEnabled = value);
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    bool codeSent = false;
    bool loading = false;
    String? error;

    final token = await StorageService.getToken();
    if (token == null || !mounted) return;

    final l = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card(ctx),
          title: Text(
            l.profileChangePassword,
            style: TextStyle(
                color: AppColors.textPrimary(ctx),
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: currentPassCtrl,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: l.fieldCurrentPassword,
                    labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: l.fieldNewPassword,
                    labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: l.fieldNewPasswordConfirm,
                    labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                  ),
                ),
                if (codeSent) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: l.fieldEmailCode,
                      labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                      counterText: '',
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: Color(0xFFEF4444), fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text(l.btnCancel,
                  style: TextStyle(color: AppColors.textSecondary(ctx))),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      setS(() {
                        error = null;
                        loading = true;
                      });

                      // Temel validasyon
                      if (currentPassCtrl.text.isEmpty ||
                          newPassCtrl.text.isEmpty ||
                          confirmPassCtrl.text.isEmpty) {
                        setS(() {
                          error = l.validAllFields;
                          loading = false;
                        });
                        return;
                      }
                      if (newPassCtrl.text.length < 8) {
                        setS(() {
                          error = l.validNewPasswordMin;
                          loading = false;
                        });
                        return;
                      }
                      if (newPassCtrl.text != confirmPassCtrl.text) {
                        setS(() {
                          error = l.validPasswordsMatch;
                          loading = false;
                        });
                        return;
                      }

                      if (!codeSent) {
                        // Doğrulama kodunu gönder
                        try {
                          await apiCall(
                            () => http.post(
                              Uri.parse('$kBaseUrl/auth/change-password/send-code'),
                              headers: {'Authorization': 'Bearer $token'},
                            ),
                          );
                          setS(() {
                            codeSent = true;
                            loading = false;
                          });
                        } on AppException catch (e) {
                          setS(() {
                            error = e.message;
                            loading = false;
                          });
                        } catch (e) {
                          LoggerService.instance.warning('ProfileScreen', 'Şifre kodu gönderilemedi: $e');
                          setS(() {
                            error = l.errorConnection;
                            loading = false;
                          });
                        }
                      } else {
                        // Kodu doğrula ve şifreyi değiştir
                        if (codeCtrl.text.trim().length != 6) {
                          setS(() {
                            error = l.validVerificationCode;
                            loading = false;
                          });
                          return;
                        }
                        try {
                          await apiCall(
                            () => http.post(
                              Uri.parse('$kBaseUrl/auth/change-password/confirm'),
                              headers: {
                                'Content-Type': 'application/json',
                                'Authorization': 'Bearer $token',
                              },
                              body: jsonEncode({
                                'current_password': currentPassCtrl.text,
                                'new_password': newPassCtrl.text,
                                'code': codeCtrl.text.trim(),
                              }),
                            ),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.msgPasswordChanged)),
                            );
                          }
                        } on AppException catch (e) {
                          setS(() {
                            error = e.message;
                            loading = false;
                          });
                        } catch (e) {
                          LoggerService.instance.warning('ProfileScreen', 'Şifre değiştirme başarısız: $e');
                          setS(() {
                            error = l.errorConnection;
                            loading = false;
                          });
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      codeSent ? l.btnChangePassword : l.btnSendCode,
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final passCtrl = TextEditingController();
    String? error;

    final l = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            l.profileDeleteAccount,
            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.profileDeleteAccountDesc,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passCtrl,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                decoration: InputDecoration(
                  labelText: l.fieldPassword,
                  hintText: l.fieldPasswordConfirmHint,
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.btnCancel, style: const TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(0, 38),
              ),
              onPressed: () async {
                if (passCtrl.text.isEmpty) {
                  setS(() => error = l.fieldPassword);
                  return;
                }
                try {
                  await AuthService.deleteAccount(passCtrl.text);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
                  }
                } on AppException catch (e) {
                  setS(() => error = e.message);
                } catch (e) {
                  LoggerService.instance.warning('ProfileScreen', 'Hesap silinemedi: $e');
                  setS(() => error = l.errorConnection);
                }
              },
              child: Text(l.btnDeleteAccount, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    passCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final currentLocale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      backgroundColor: AppColors.bg(context),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // ── Pro Araçlar ───────────────────────────────────────────────────
          _SettingsSection(
            title: l.settingsProTools,
            items: [
              _SettingsTile(
                icon: Icons.workspace_premium_outlined,
                iconColor: const Color(0xFF06B6D4),
                label: '👑 ${l.proHubTitle}',
                trailing: _isPremium
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF1E1B4B), Color(0xFF4338CA)]),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(l.settingsProActive, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0891B2), Color(0xFF06B6D4)]),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                onTap: () async {
                  // StorageService'ten güncel is_premium oku — widget.user stale olabilir
                  final freshInfo = await StorageService.getUserInfo();
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProHubScreen(isPremium: freshInfo?['is_premium'] == true),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: l.profileMyListings,
            items: [
              _SettingsTile(
                icon: Icons.list_alt_outlined,
                label: l.profileActiveListings,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const _MyListingsScreen(active: true))),
              ),
              _SettingsTile(
                icon: Icons.archive_outlined,
                label: l.profilePassiveListings,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const _MyListingsScreen(active: false))),
              ),
              _SettingsTile(
                icon: Icons.favorite_outline,
                label: l.profileFavorites,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const _FavoritesScreen())),
              ),
              _SettingsTile(
                icon: Icons.shopping_bag_outlined,
                label: l.settingsMyPurchases,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PurchasesScreen())),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: l.profileAccountSection,
            items: [
              _SettingsTile(
                icon: Icons.manage_accounts_outlined,
                label: l.accountInfoMenuLabel,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountInfoScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                label: l.profileChangePassword,
                onTap: () => _showChangePasswordDialog(context),
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                label: l.profileNotificationSettings,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotificationSettingsScreen(
                      isPremium: _isPremium,
                    ),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.block_outlined,
                label: l.profileBlockedUsers,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BlockedUsersScreen(),
                  ),
                ),
              ),
              if (_biometricAvailable)
                SwitchListTile(
                  key: const Key('settings_switch_face_id'),
                  secondary: Icon(Icons.face_outlined,
                      color: AppColors.iconColor(context)),
                  title: Text(l.profileFaceId,
                      style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context))),
                  subtitle: Text(
                    _biometricEnabled ? l.statusOn : l.statusOff,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary(context)),
                  ),
                  value: _biometricEnabled,
                  activeColor: kPrimary,
                  onChanged: _toggleBiometric,
                ),
              SwitchListTile(
                key: const Key('settings_switch_karanlik_mod'),
                secondary: Icon(Icons.dark_mode_outlined, color: AppColors.iconColor(context)),
                title: Text(l.profileDarkMode, style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context))),
                subtitle: Text(
                  ThemeProvider.instance.isDark ? l.statusOn : l.statusOff,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                ),
                value: ThemeProvider.instance.isDark,
                activeColor: kPrimary,
                onChanged: (_) async {
                  await ThemeProvider.instance.toggle();
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                key: const Key('settings_tile_dil'),
                leading: Icon(Icons.language_outlined, color: AppColors.iconColor(context)),
                title: Text(l.settingsLanguage,
                    style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context))),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'tr', label: Text('TR')),
                    ButtonSegment(value: 'en', label: Text('EN')),
                    ButtonSegment(value: 'ar', label: Text('AR')),
                  ],
                  selected: {currentLocale.languageCode},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (selection) {
                    ref.read(localeProvider.notifier).setLocale(Locale(selection.first));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: l.profileSupportSection,
            items: [
              _SettingsTile(
                icon: Icons.help_outline,
                label: l.profileSupportCenter,
                onTap: () async {
                  final uri = Uri.parse('https://www.teqlif.com/support.html');
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                label: l.profileTerms,
                onTap: () async {
                  final uri = Uri.parse('https://www.teqlif.com/kullanim-sartlari.html');
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                label: l.profilePrivacy,
                onTap: () async {
                  final uri = Uri.parse('https://www.teqlif.com/gizlilik-politikasi');
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            color: AppColors.surface(context),
            child: Column(
              children: [
                ListTile(
                  key: const Key('settings_tile_hesabi_sil'),
                  leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                  title: Text(
                    l.btnDeleteAccount,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => _showDeleteAccountDialog(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  key: const Key('settings_tile_cikis_yap'),
                  leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
                  title: Text(
                    l.btnLogout,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    await AuthService.logout();
                    nav.pushNamedAndRemoveUntil('/login', (_) => false);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary(context),
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...items,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? labelColor;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.iconColor(context)),
      title: Text(label, style: TextStyle(fontSize: 14, color: labelColor ?? AppColors.textPrimary(context))),
      trailing: trailing ?? Icon(Icons.chevron_right, color: AppColors.border(context), size: 20),
      onTap: onTap,
    );
  }
}

// ── Profil düzenle ekranı ──────────────────────────────────────────────────

class _EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? user;
  const _EditProfileScreen({required this.user});

  @override
  State<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<_EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _linkCtrl;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _profileImageUrl;

  // Username availability check
  String? _usernameStatus; // null | 'checking' | 'available' | 'taken'
  Timer? _usernameDebounce;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user?['full_name'] ?? '');
    _usernameCtrl = TextEditingController(text: widget.user?['username'] ?? '');
    _bioCtrl = TextEditingController(text: widget.user?['bio'] as String? ?? '');
    _linkCtrl = TextEditingController(text: widget.user?['website_url'] as String? ?? '');
    _profileImageUrl = widget.user?['profile_image_url'] as String?;
    _usernameCtrl.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final val = _usernameCtrl.text.trim();
    _usernameDebounce?.cancel();
    if (val == (widget.user?['username'] ?? '')) {
      setState(() => _usernameStatus = null);
      return;
    }
    if (val.length < 3 || !RegExp(r'^[a-z0-9_]+$').hasMatch(val)) {
      setState(() => _usernameStatus = null);
      return;
    }
    setState(() => _usernameStatus = 'checking');
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () => _checkUsername(val));
  }

  Future<void> _checkUsername(String val) async {
    try {
      final excludeId = widget.user?['id'] as int?;
      final params = {'username': val};
      if (excludeId != null) params['exclude_id'] = excludeId.toString();
      final data = await apiCall(
        () => http.get(
          Uri.parse('$kBaseUrl/auth/check-username').replace(queryParameters: params),
        ),
      );
      if (!mounted) return;
      setState(() => _usernameStatus = (data['available'] as bool) ? 'available' : 'taken');
    } catch (e) {
      LoggerService.instance.warning('EditProfileScreen', 'Kullanıcı adı kontrolü başarısız: $e');
      if (mounted) setState(() => _usernameStatus = null);
    }
  }

  String _buildImageUrl(String url) {
    if (url.startsWith('http')) return url;
    final origin = kBaseUrl.replaceFirst(RegExp(r'/api.*'), '');
    return '$origin$url';
  }

  Future<void> _pickAndUploadAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden Seç'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Kameradan Çek'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    final token = await StorageService.getToken();
    if (token == null) return;

    setState(() { _saving = true; _uploadingAvatar = true; });
    try {
      final file = File(picked.path);
      final upload = await UploadService.uploadFile(file);

      final patchBody = <String, dynamic>{'profile_image_url': upload.url};
      if (upload.thumbUrl != null) {
        patchBody['profile_image_thumb_url'] = upload.thumbUrl;
      }

      final patchResp = await http.patch(
        Uri.parse('$kBaseUrl/auth/me'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode(patchBody),
      );
      if (patchResp.statusCode != 200) throw Exception('Patch failed');
      final updatedUser = jsonDecode(patchResp.body) as Map<String, dynamic>;
      await StorageService.saveUserInfo(
        id: updatedUser['id'] as int,
        email: updatedUser['email'] as String,
        username: updatedUser['username'] as String,
        fullName: updatedUser['full_name'] as String,
        isPremium: updatedUser['is_premium'] as bool? ?? false,
        onboardingCompleted: updatedUser['onboarding_completed'] as bool? ?? false,
        isVerified: updatedUser['is_verified'] as bool? ?? false,
        phoneVerified: updatedUser['phone_verified'] as bool? ?? false,
      );
      if (mounted) setState(() => _profileImageUrl = upload.url);
    } catch (e) {
      LoggerService.instance.warning('EditProfileScreen', 'Avatar yüklenemedi: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf yüklenemedi. Tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() { _saving = false; _uploadingAvatar = false; });
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    if (name.isEmpty || username.isEmpty) {
      showErrorSnackbar(context, Exception('Tüm alanları doldurun'));
      return;
    }
    if (username.length < 3 || !RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      showErrorSnackbar(context, Exception('Kullanıcı adı geçersiz. Sadece küçük harf, rakam ve _ kullanılabilir.'));
      return;
    }
    if (_usernameStatus == 'taken') {
      showErrorSnackbar(context, Exception('Bu kullanıcı adı zaten alınmış'));
      return;
    }
    if (_usernameStatus == 'checking') {
      showErrorSnackbar(context, Exception('Kullanıcı adı kontrol ediliyor, lütfen bekleyin...'));
      return;
    }
    setState(() { _saving = true; });
    try {
      final token = await StorageService.getToken();
      if (token == null) throw Exception('No token');
      final bio = _bioCtrl.text.trim();
      final link = _linkCtrl.text.trim();
      if (link.isNotEmpty && !link.startsWith('http://') && !link.startsWith('https://')) {
        showErrorSnackbar(context, Exception(AppLocalizations.of(context)!.editProfileLinkError));
        setState(() => _saving = false);
        return;
      }
      final updatedUser = await apiCall(
        () => http.patch(
          Uri.parse('$kBaseUrl/auth/me'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({
            'full_name': name,
            'username': username,
            'bio': bio.isEmpty ? null : bio,
            'website_url': link.isEmpty ? null : link,
          }),
        ),
      );
      await StorageService.saveUserInfo(
        id: updatedUser['id'] as int,
        email: updatedUser['email'] as String,
        username: updatedUser['username'] as String,
        fullName: updatedUser['full_name'] as String,
        isPremium: updatedUser['is_premium'] as bool? ?? false,
        onboardingCompleted: updatedUser['onboarding_completed'] as bool? ?? false,
        isVerified: updatedUser['is_verified'] as bool? ?? false,
        phoneVerified: updatedUser['phone_verified'] as bool? ?? false,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = (_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0] : '?').toUpperCase();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profili Düzenle'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              'Kaydet',
              style: TextStyle(
                color: _saving ? Colors.grey : kPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar
            GestureDetector(
              onTap: _saving ? null : _pickAndUploadAvatar,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primaryBg(context),
                    backgroundImage: (_profileImageUrl?.isNotEmpty == true)
                        ? NetworkImage(_buildImageUrl(_profileImageUrl!))
                        : null,
                    child: (_profileImageUrl?.isNotEmpty == true)
                        ? null
                        : Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: kPrimary,
                            ),
                          ),
                  ),
                  if (_uploadingAvatar)
                    ClipOval(
                      child: Container(
                        width: 88,
                        height: 88,
                        color: Colors.black.withValues(alpha: 0.50),
                        child: const Center(
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: kPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Ad Soyad'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _usernameCtrl,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Kullanıcı Adı',
                helperText: 'Küçük harf, rakam ve _ kullanılabilir',
                helperStyle: const TextStyle(fontSize: 11),
                suffixIcon: _usernameStatus == 'checking'
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _usernameStatus == 'available'
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                        : _usernameStatus == 'taken'
                            ? const Icon(Icons.cancel, color: Colors.red, size: 20)
                            : null,
              ),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _bioCtrl,
              builder: (_, val, __) {
                final l = AppLocalizations.of(context)!;
                return TextField(
                  controller: _bioCtrl,
                  maxLength: 60,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l.editProfileBio,
                    hintText: l.editProfileBioHint,
                    helperText: l.editProfileBioHelper,
                    helperStyle: const TextStyle(fontSize: 11),
                    counterText: '${val.text.length}/60',
                    counterStyle: TextStyle(
                      fontSize: 11,
                      color: val.text.length >= 60
                          ? Colors.red
                          : AppColors.textTertiary(context),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Builder(
              builder: (context) {
                final l = AppLocalizations.of(context)!;
                return TextField(
                  controller: _linkCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.editProfileLink,
                    hintText: l.editProfileLinkHint,
                    prefixIcon: const Icon(Icons.link_rounded, size: 20),
                    helperText: l.editProfileLinkHelper,
                    helperStyle: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Aktif / Pasif ilanlarım ekranı ────────────────────────────────────────────

class _MyListingsScreen extends StatefulWidget {
  final bool active;
  const _MyListingsScreen({required this.active});

  @override
  State<_MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<_MyListingsScreen> {
  List<dynamic> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final activeParam = widget.active ? 'true' : 'false';
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/my?active=$activeParam'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() => _listings = jsonDecode(resp.body) as List);
      }
    } catch (e) {
      LoggerService.instance.warning('MyListingsScreen', 'İlanlar yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(dynamic listing) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = listing['id'];
    try {
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/listings/$id/toggle'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) await _load();
    } catch (e) {
      LoggerService.instance.warning('MyListingsScreen', 'İlan durumu değiştirilemedi: $e');
    }
  }

  Future<void> _delete(dynamic listing) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('İlanı Sil'),
        content: const Text('Bu ilanı kalıcı olarak silmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = listing['id'];
    try {
      final resp = await http.delete(
        Uri.parse('$kBaseUrl/listings/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) await _load();
    } catch (e) {
      LoggerService.instance.warning('MyListingsScreen', 'İlan silinemedi: $e');
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.active ? 'Aktif İlanlarım' : 'Pasif İlanlarım')),
      backgroundColor: AppColors.bg(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _listings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.active ? Icons.list_alt_outlined : Icons.archive_outlined,
                          size: 52, color: const Color(0xFFD1D5DB)),
                      const SizedBox(height: 12),
                      Text(
                        widget.active ? 'Aktif ilan yok' : 'Pasif ilan yok',
                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _listings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final l = _listings[i];
                      final imgs = l['image_urls'] as List? ?? [];
                      final rawImg = imgs.isNotEmpty ? imgs[0] as String : l['image_url'] as String?;
                      final imageUrl = rawImg != null ? imgUrl(rawImg) : null;
                      return Card(
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    width: 60, height: 60, fit: BoxFit.cover,
                                    placeholder: (_, __) => const SizedBox(
                                      width: 60, height: 60,
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
                                    ),
                                    errorWidget: (_, __, ___) => _imgPlaceholder())
                                : _imgPlaceholder(),
                          ),
                          title: Text(l['title'] ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(_fmt(l['price']),
                              style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  widget.active ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: widget.active ? const Color(0xFF6B7280) : kPrimary,
                                  size: 22,
                                ),
                                tooltip: widget.active ? 'Pasife Al' : 'Aktif Yap',
                                onPressed: () => _toggle(l),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 22),
                                tooltip: 'Sil',
                                onPressed: () => _delete(l),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListingDetailScreen(
                                  listing: Map<String, dynamic>.from(l)),
                            ),
                          ).then((_) => _load()),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _imgPlaceholder() => Builder(
        builder: (context) => Container(
          width: 60, height: 60,
          color: AppColors.surfaceVariant(context),
          child: Icon(Icons.image_outlined, color: AppColors.border(context)),
        ),
      );
}

// ── Favorilerim ekranı ─────────────────────────────────────────────────────────

class _FavoritesScreen extends StatefulWidget {
  const _FavoritesScreen();

  @override
  State<_FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<_FavoritesScreen> {
  List<dynamic> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() => _listings = jsonDecode(resp.body) as List);
      }
    } catch (e) {
      LoggerService.instance.warning('FavoritesScreen', 'Favoriler yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFavorite(dynamic listing) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.delete(
        Uri.parse('$kBaseUrl/favorites/${listing['id']}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      await _load();
    } catch (e) {
      LoggerService.instance.warning('FavoritesScreen', 'Favori kaldırılamadı: $e');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Favorilerim')),
      backgroundColor: AppColors.bg(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _listings.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border, size: 52, color: Color(0xFFD1D5DB)),
                      SizedBox(height: 12),
                      Text('Henüz favori ilan yok',
                          style: TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _listings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final l = _listings[i];
                      final imgs = l['image_urls'] as List? ?? [];
                      final rawImg = imgs.isNotEmpty ? imgs[0] as String : l['image_url'] as String?;
                      final imageUrl = rawImg != null ? imgUrl(rawImg) : null;
                      return Card(
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    width: 60, height: 60, fit: BoxFit.cover,
                                    placeholder: (_, __) => const SizedBox(
                                      width: 60, height: 60,
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
                                    ),
                                    errorWidget: (_, __, ___) => _imgPlaceholder())
                                : _imgPlaceholder(),
                          ),
                          title: Text(l['title'] ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_fmt(l['price']),
                                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                              Text('@${(l['user'] as Map?)?['username'] ?? ''}',
                                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.favorite, color: Colors.red, size: 22),
                            tooltip: 'Favoriden Çıkar',
                            onPressed: () => _removeFavorite(l),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListingDetailScreen(
                                  listing: Map<String, dynamic>.from(l)),
                            ),
                          ).then((_) => _load()),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _imgPlaceholder() => Container(
        width: 60, height: 60,
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.image_outlined, color: Color(0xFFD1D5DB)),
      );
}

// ── TUCi Cüzdan Kartı ───────────────────────────────────────────────────────

class _TuciWalletCard extends StatefulWidget {
  final int? balance;
  final List<dynamic> history;
  final Future<void> Function() onRefresh;

  const _TuciWalletCard({
    required this.balance,
    required this.history,
    required this.onRefresh,
  });

  @override
  State<_TuciWalletCard> createState() => _TuciWalletCardState();
}

class _TuciWalletCardState extends State<_TuciWalletCard> {
  bool _refreshing = false;

  void _openSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TuciWalletSheet(balance: widget.balance ?? 0, history: widget.history),
    );
  }

  Future<void> _handleRefresh() async {
    setState(() => _refreshing = true);
    await widget.onRefresh();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openSheet,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB8860B), Color(0xFFFFD700), Color(0xFFFFA500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('T', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TUCi Cüzdan',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  widget.balance == null
                      ? const SizedBox(
                          width: 80, height: 20,
                          child: LinearProgressIndicator(color: Colors.white54, backgroundColor: Colors.white24),
                        )
                      : Text(
                          '${widget.balance} TUCi',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                ],
              ),
            ),
            // Yenile ikonu
            GestureDetector(
              onTap: _handleRefresh,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _refreshing
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 26),
          ],
        ),
      ),
    );
  }
}

class _TuciWalletSheet extends StatelessWidget {
  final int balance;
  final List<dynamic> history;

  const _TuciWalletSheet({required this.balance, required this.history});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tutamaç
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          // Bakiye
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB8860B), Color(0xFFFFD700), Color(0xFFFFA500)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(AppLocalizations.of(context)!.walletBalance, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  '$balance TUCi',
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Son işlemler
          if (history.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(AppLocalizations.of(context)!.walletRecentTxns, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(height: 8),
            ...history.map((t) {
              final amount = t['amount'] as int? ?? 0;
              final label = t['label'] as String? ?? t['transaction_type'] as String? ?? '';
              final isPositive = amount > 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPositive ? Icons.add_rounded : Icons.remove_rounded,
                        color: isPositive ? Colors.green : Colors.red,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label, style: const TextStyle(fontSize: 13)),
                    ),
                    Text(
                      '${isPositive ? '+' : ''}$amount TUCi',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
          // Satın Al butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.schedule_rounded),
              label: Text(l.walletBuyBtn),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFEF3C7),
                foregroundColor: const Color(0xFF92400E),
                disabledBackgroundColor: const Color(0xFFFEF3C7),
                disabledForegroundColor: const Color(0xFF92400E),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tam Cüzdan Ekranı ────────────────────────────────────────────────────────

class WalletScreen extends StatefulWidget {
  final int? initialBalance;
  final List<dynamic> initialHistory;

  const WalletScreen({
    super.key,
    this.initialBalance,
    this.initialHistory = const [],
  });

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  int? _balance;
  List<dynamic> _txns = [];
  bool _loading = false;

  Map<String, String> _typeLabels(AppLocalizations l) => {
    'airdrop':           l.walletTxnAirdrop,
    'receive_gift':      l.walletTxnReceiveGift,
    'spend_lead_gen':    l.walletTxnSpendLeadGen,
    'spend_ad_campaign': l.walletTxnSpendAdCampaign,
    'spend_ai':          l.walletTxnSpendAi,
    'web_topup':         l.walletTxnWebTopup,
  };

  @override
  void initState() {
    super.initState();
    _balance = widget.initialBalance;
    _txns = List.from(widget.initialHistory);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await WalletService.getBalance(limit: 50);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data != null) {
        _balance = data['balance'] as int?;
        _txns = data['transactions'] as List? ?? [];
      }
    });
  }

  // Harcama özeti: spend_* türlerini topla
  Map<String, int> get _spendingSummary {
    final map = <String, int>{};
    for (final t in _txns) {
      final type = t['transaction_type'] as String? ?? '';
      final amount = (t['amount'] as int? ?? 0).abs();
      if (type.startsWith('spend_')) {
        map[type] = (map[type] ?? 0) + amount;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final summary = _spendingSummary;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.walletTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            const SizedBox(height: 16),

            // ── Bakiye kartı ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB8860B), Color(0xFFFFD700), Color(0xFFFFA500)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(l.walletBalance,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    _balance != null ? '$_balance TUCi' : '—',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Harcama özeti ─────────────────────────────────────────
            if (summary.isNotEmpty) ...[
              Text(l.walletSpendingSummary,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 10),
              ...summary.entries.map((e) => _SummaryRow(
                    label: _typeLabels(l)[e.key] ?? e.key,
                    amount: e.value,
                  )),
              const SizedBox(height: 20),
            ],

            // ── İşlem geçmişi ─────────────────────────────────────────
            if (_txns.isNotEmpty) ...[
              Text(l.walletTxnHistory,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 10),
              ..._txns.map((t) {
                final amount = t['amount'] as int? ?? 0;
                final label = _typeLabels(l)[t['transaction_type']] ??
                    (t['label'] as String? ?? '');
                final isPos = amount > 0;
                final dateStr = t['created_at'] as String? ?? '';
                String formattedDate = '';
                try {
                  final d = DateTime.parse(dateStr).toLocal();
                  formattedDate =
                      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                } catch (_) {}
                return _TxnRow(
                  label: label,
                  amount: amount,
                  isPositive: isPos,
                  date: formattedDate,
                );
              }),
              const SizedBox(height: 24),
            ] else if (!_loading) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(l.walletNoTxns,
                    style: const TextStyle(color: Colors.grey)),
              ),
            ],

            // ── Yakında bildirimi ─────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Text('🔔', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    l.walletComingSoonLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.walletComingSoonDesc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int amount;
  const _SummaryRow({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFFFD700),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
          Text('$amount TUCi',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB8860B))),
        ],
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  final String label;
  final int amount;
  final bool isPositive;
  final String date;
  const _TxnRow(
      {required this.label,
      required this.amount,
      required this.isPositive,
      required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPositive ? Icons.add_rounded : Icons.remove_rounded,
              color: isPositive ? Colors.green : Colors.red,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                if (date.isNotEmpty)
                  Text(date,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}$amount TUCi',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

