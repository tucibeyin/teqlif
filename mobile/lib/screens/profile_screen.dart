import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/overlays/teq_toast.dart';
import '../services/localization_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../core/app_exception.dart';
import '../core/logger_service.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';

import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/image_cache_manager.dart';
import '../services/listing_service.dart';
import '../providers/listing_interaction_provider.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/buttons/teq_button.dart';
import '../ui_library/components/cards/teq_card.dart';
import '../utils/error_helper.dart';

import 'my_ratings_screen.dart';
import '../utils/start_stream_helper.dart';
import '../widgets/language_switch_overlay.dart';
import '../widgets/network_error_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/stale_data_banner.dart';
import '../utils/once.dart';
import '../models/listing_filter_state.dart';
import '../ui_library/components/filters/teq_filter_bar.dart';
import 'follow_list_screen.dart';
import 'listing_detail_screen.dart';
import 'live_stream_analytics_screen.dart';
import 'public_profile_screen.dart';
import 'create_listing_screen.dart';
import 'pro_hub_screen.dart';
import 'notification_settings_screen.dart';
import 'blocked_users_screen.dart';
import 'account_info_screen.dart';
import 'follow_requests_screen.dart';
import 'purchases_screen.dart';
import 'sales_screen.dart';
import '../services/share_service.dart';
import '../services/wallet_service.dart';
import '../models/enums.dart';
import 'faq_screen.dart';
import 'call_history_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'viewmodels/profile_view_model.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/consent_notice_modal.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _websiteGuard = OnceGuard(); // Çift tıklama engeli

  @override
  void initState() {
    super.initState();
    // Load is handled inside build of view model automatically
  }

  void refresh({bool bypassCache = false}) {
    ref.read(profileViewModelProvider.notifier).load(bypassCache: bypassCache);
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadWallet({bool bypassCache = false}) async {
    await ref.read(profileViewModelProvider.notifier).loadWallet(bypassCache: bypassCache);
  }



  String _buildImageUrl(String url) {
    if (url.startsWith('http')) return url;
    final origin = kBaseUrl.replaceFirst(RegExp(r'/api.*'), '');
    return '$origin$url';
  }

  /// Profil fotoğrafı — CachedNetworkImage ile disk'e önbelleğe alınır.
  Widget _buildAvatar({
    required String? imageUrl,
    required double radius,
    required Widget fallback,
  }) {
    final bg = AppColors.primaryBg(context);
    if (imageUrl == null) {
      return CircleAvatar(radius: radius, backgroundColor: bg, child: fallback);
    }
    return ClipOval(
      child: CachedNetworkImage(
        cacheManager: TeqlifCacheManager(),
        imageUrl: imageUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, _) =>
            CircleAvatar(radius: radius, backgroundColor: bg, child: fallback),
        errorWidget: (_, _, _) =>
            CircleAvatar(radius: radius, backgroundColor: bg, child: fallback),
      ),
    );
  }

  void _openSettings(Map<String, dynamic>? user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _SettingsScreen(user: user)),
    );
  }


  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(profileViewModelProvider);
    final state = stateAsync.value ?? const ProfileUiState();
    final user = state.user;

    // Yerel önbellekte hiç veri yoksa (ilk kurulum) tam ekran spinner
    if (state.loading && user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    final loc = ref.watch(localizationProvider);
    final fullName =
        user?['full_name'] ??
        user?['username'] ??
        loc.t('defaultUserFallback');
    final username = user?['username'] ?? '';
    final email = user?['email'] ?? '';
    final isVerified = user?['is_verified'] == true;

    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        leading: PopupMenuButton<String>(
          offset: const Offset(8, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
                  Text(
                    ref.read(localizationProvider).t('btnAddListing'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
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
                    child: const Icon(
                      Icons.videocam_outlined,
                      color: Colors.red,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    ref.read(localizationProvider).t('startLiveStreamOption'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
          onSelected: (val) {
            if (val == 'listing') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateListingScreen()),
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
            if (isVerified) ...[
              const SizedBox(width: 4),
              const FaIcon(
                FontAwesomeIcons.circleCheck,
                color: Colors.blue,
                size: 16,
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
                    initialBalance: state.tuciBalance,
                    initialHistory: state.tuciHistory,
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
                    child: state.tuciBalance != null
                        ? Text(
                            '${state.tuciBalance} T',
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
            onTap: () => _openSettings(user),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 12, 0),
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
        onRefresh: () async => ref.read(profileViewModelProvider.notifier).load(bypassCache: true),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // ── Profil başlık bölümü ──
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildAvatar(
                              imageUrl:
                                  (user?['profile_image_url'] as String?)
                                          ?.isNotEmpty ==
                                      true
                                  ? _buildImageUrl(
                                      user!['profile_image_url'] as String,
                                    )
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
                            if (user?['is_premium'] == true)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF0891B2),
                                        Color(0xFF06B6D4),
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.surface(context),
                                      width: 2,
                                    ),
                                  ),
                                  child: const FaIcon(
                                    FontAwesomeIcons.crown,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        // İstatistikler
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatItem(
                                count: state.listings.length,
                                label: loc.t("profileListingCount"),
                              ),
                              GestureDetector(
                                key: const Key('profile_stat_takipci'),
                                onTap: user?['id'] != null
                                    ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FollowListScreen(
                                            userId: user!['id'] as int,
                                            type: FollowListType.followers,
                                            title: loc.t("profileFollowersList"),
                                          ),
                                        ),
                                      )
                                    : null,
                                child: _StatItem(
                                  count:
                                      (user?['follower_count'] as int?) ?? 0,
                                  label: loc.t("profileFollowers"),
                                ),
                              ),
                              GestureDetector(
                                key: const Key('profile_stat_takip'),
                                onTap: user?['id'] != null
                                    ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FollowListScreen(
                                            userId: user!['id'] as int,
                                            type: FollowListType.following,
                                            title: loc.t("profileFollowingList"),
                                          ),
                                        ),
                                      )
                                    : null,
                                child: _StatItem(
                                  count:
                                      (user?['following_count'] as int?) ?? 0,
                                  label: loc.t("profileFollowing"),
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
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 0),
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
                            if (user?['influence_rank'] != null &&
                                (user!['influence_rank'] as int) > 0) ...[
                              const SizedBox(width: 6),
                              _ScoreBadge(
                                icon: FontAwesomeIcons.rankingStar,
                                title: loc.t("influenceRankLabel"),
                                value: '${user!['influence_rank']}',
                                hint: loc.t("influenceRankHint"),
                                color: const Color(0xFF8B5CF6),
                              ),
                            ],
                            if (user?['trust_score'] != null) ...[
                              const SizedBox(width: 6),
                              Builder(
                                builder: (ctx) {
                                  final ts = (user!['trust_score'] as num)
                                      .toInt();
                                  return _ScoreBadge(
                                    icon: FontAwesomeIcons.shieldHalved,
                                    title: loc.t('trustScoreLabel'),
                                    value: '$ts / 100',
                                    hint: loc.t('trustScoreHint'),
                                    color: ts >= 70
                                        ? const Color(0xFF10B981)
                                        : ts >= 35
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF9CA3AF),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),

                        if ((user?['bio'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            user!['bio'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary(context),
                              height: 1.4,
                            ),
                          ),
                        ],
                        if ((user?['website_url'] as String?)?.isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _websiteGuard.run(() async {
                              final raw = user!['website_url'] as String;
                              final uri = Uri.tryParse(raw);
                              if (uri != null && await canLaunchUrl(uri)) {
                                launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            }),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.link_rounded,
                                  size: 14,
                                  color: Color(0xFF0EA5E9),
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    (user!['website_url'] as String)
                                        .replaceFirst(
                                          RegExp(r'^https?://'),
                                          '',
                                        ),
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
                        const SizedBox(height: 10),
                        _SocialLinksRow(
                          user: user,
                          userId: user?['id'] as int?,
                        ),
                      ],
                    ),
                  ),
                  // Profili Düzenle butonu
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                    child: TeqButton.outline(
                      key: const Key('profile_btn_profil_duzenle'),
                      text: ref.read(localizationProvider).t('btnEditProfile'),
                      size: TeqButtonSize.small,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _EditProfileScreen(user: user),
                        ),
                      ).then((_) => ref.read(profileViewModelProvider.notifier).load(bypassCache: true)),
                    ),
                  ),
                  // Separator
                  Divider(height: 1, color: AppColors.divider(context)),
                ],
              ),
            ),

            // ── Stale veri uyarısı ──
            if (state.listingsError && state.listings.isNotEmpty)
              SliverToBoxAdapter(
                child: StaleDataBanner(onRetry: () => ref.read(profileViewModelProvider.notifier).load(bypassCache: true)),
              ),

            // ── Arama & Kategori filtresi ──
            if (!state.loading || state.listings.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TeqFilterBar(
                      filter: state.filter,
                      onChanged: (f) => ref.read(profileViewModelProvider.notifier).updateFilter(f),
                      showSubcategory: true,
                      showCity: false,
                      showCondition: false,
                      showSort: false,
                      showPriceRange: false,
                    ),
                  ],
                ),
              ),

            // ── İlanlar grid ──
            if (state.loading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
            else if (state.listingsError && state.listings.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: NetworkErrorWidget(
                  scrollable: true,
                  onRetry: () => ref.read(profileViewModelProvider.notifier).load(bypassCache: true),
                ),
              )
            else if (state.listings.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Builder(
                  builder: (context) {
                    final loc = ref.read(localizationProvider);
                    return Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.grid_off_outlined,
                              size: 52,
                              color: Color(0xFFD1D5DB),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              loc.t('emptyListings'),
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              loc.t('profileFirstListing'),
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
            else if (state.filteredListings.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Builder(
                  builder: (ctx) => Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.search_off_rounded,
                            size: 52,
                            color: Color(0xFFD1D5DB),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            loc.t("noResultsFound"),
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _ListingGridItem(
                    key: Key('profile_listing_${state.filteredListings[i]['id']}'),
                    listing: state.filteredListings[i],
                  ),
                  childCount: state.filteredListings.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _ListingGridItem extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final imgs = listing['image_urls'] as List? ?? [];
    final raw = imgs.isNotEmpty
        ? imgs[0] as String
        : listing['image_url'] as String?;
    final imageUrl = raw != null ? imgUrl(raw) : null;
    final price = _fmt(listing['price']);

    final isSponsored = listing['is_sponsored'] == true;
    final status = ListingStatusExtension.fromJson(listing);
    final isPassive = status == ListingStatus.passive;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ListingDetailScreen(listing: Map<String, dynamic>.from(listing)),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageUrl != null
              ? CachedNetworkImage(
                  cacheManager: TeqlifCacheManager(),
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (_, _, _) => _placeholder(context),
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
                child: Text(
                  ref.read(localizationProvider).t('badgePassive'),
                  style: const TextStyle(
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
                child: Text(
                  ref.read(localizationProvider).t('badgeSponsored'),
                  style: const TextStyle(
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
      child: Icon(
        Icons.image_outlined,
        size: 28,
        color: AppColors.border(context),
      ),
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
  bool _isPrivate = false;
  late String _displayedLang;
  bool _isSwitching = false;
  bool _consentGiven = false;
  DateTime? _consentAt;

  @override
  void initState() {
    super.initState();
    // widget.user'dan ön değer al (anlık gösterim için)
    _isPremium = widget.user?['is_premium'] == true;
    _isPrivate = widget.user?['is_private'] == true;
    _displayedLang = ref.read(localeProvider).languageCode;
    _loadBiometricState();
    _loadPremiumStatus();
    _loadPendingRequests();
    _loadUnreadRatings();
    _loadConsentStatus();
  }

  Future<void> _loadConsentStatus() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final body = await apiCall(
        () => http.get(
          Uri.parse('$kBaseUrl/auth/me/consent'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      if (!mounted) return;
      setState(() {
        _consentGiven = body['given'] == true;
        final atStr = body['at'] as String?;
        _consentAt = atStr != null ? DateTime.tryParse(atStr) : null;
      });
    } catch (e) {
      // sessiz hata — consent durumu boş kalır
    }
  }

  Future<void> _onLangChange(String newLang) async {
    if (_isSwitching || newLang == _displayedLang) return;
    final prevLang = _displayedLang;
    setState(() {
      _isSwitching = true;
      _displayedLang = newLang;
    });
    final ok = await ref.read(localizationProvider.notifier).switchLanguage(newLang);
    if (!mounted) return;
    if (ok) {
      await ref.read(localeProvider.notifier).setLocale(Locale(newLang));
      if (!mounted) return;
      setState(() => _isSwitching = false);
      TeqToast.success(ref.read(localizationProvider).t('langSwitchSuccess'));
    } else {
      setState(() {
        _isSwitching = false;
        _displayedLang = prevLang;
      });
      TeqToast.error(ref.read(localizationProvider).t('langSwitchFailed'));
    }
  }

  int _pendingRequestCount = 0;
  int _unreadRatingCount = 0;

  Future<void> _loadUnreadRatings() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/ratings/me/unread-count'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (mounted) {
          setState(() => _unreadRatingCount = data['unread_count'] ?? 0);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadPendingRequests() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/follows/requests'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final List data = jsonDecode(resp.body);
        if (mounted) {
          setState(() => _pendingRequestCount = data.length);
        }
      }
    } catch (_) {}
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
      setState(() {
        _isPremium = info['is_premium'] == true;
        _isPrivate = info['is_private'] == true;
      });
    }
  }

  Future<void> _togglePrivateAccount(bool val) async {
    setState(() => _isPrivate = val);
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/auth/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'is_private': val}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        await StorageService.saveUserInfo(
          id: data['id'] as int,
          email: data['email'] as String,
          username: data['username'] as String,
          fullName: data['full_name'] as String,
          isPremium: data['is_premium'] == true,
          planType: data['plan_type'] as String?,
          onboardingCompleted: data['onboarding_completed'] == true,
          isVerified: data['is_verified'] == true,
          phoneVerified: data['phone_verified'] == true,
          isPrivate: data['is_private'] == true,
        );
      } else {
        setState(() => _isPrivate = !val);
        if (mounted) {
          TeqSnackBar.show(message: ref.read(localizationProvider).t('errorGenericRetry'), type: TeqSnackBarType.info);
        }
      }
    } catch (_) {
      setState(() => _isPrivate = !val);
      if (mounted) {
        TeqSnackBar.show(message: ref.read(localizationProvider).t('errNetworkRetry'), type: TeqSnackBarType.info);
      }
    }
  }

  bool _shareLoading = false;
  final GlobalKey _shareTileKey = GlobalKey();

  // Çift tıklama guard'ları
  final _logoutGuard = OnceGuard();
  final _proHubGuard = OnceGuard();
  final _urlGuard = OnceGuard();

  Future<void> _shareInvite() async {
    if (_shareLoading) return;
    final token = await StorageService.getToken();
    if (token == null || !mounted) return;
    setState(() => _shareLoading = true);
    String? code;
    String? expiresAt;
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/users/my-referral'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        code = data['referral_code'] as String?;
        expiresAt = data['expires_at'] as String?;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _shareLoading = false);
    if (code == null) {
      TeqSnackBar.show(message: ref.read(localizationProvider).t('profileInviteCodeError'), type: TeqSnackBarType.info);
      return;
    }

    // Kalan süreyi hesapla
    final loc = ref.read(localizationProvider);
    String expiryText = loc.t('profileInviteExpiryDays', {'days': '3'});
    if (expiresAt != null) {
      try {
        final expiry = DateTime.parse(expiresAt);
        final diff = expiry.difference(DateTime.now().toUtc());
        if (diff.inHours >= 24) {
          expiryText = loc.t('profileInviteExpiryDays', {'days': diff.inDays.toString()});
        } else if (diff.inHours > 0) {
          expiryText = loc.t('profileInviteExpiryHours', {'hours': diff.inHours.toString()});
        } else {
          expiryText = loc.t('profileInviteExpirySoon');
        }
      } catch (_) {}
    }

    final shareText = loc.t('profileInviteShareText', {'code': code, 'expiry': expiryText});

    // iOS 26+ sharePositionOrigin zorunlu — tile'ın ekran konumunu kullan
    final box = _shareTileKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromCenter(
            center: MediaQuery.sizeOf(context).center(Offset.zero),
            width: 1,
            height: 1,
          );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 6,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Icon(
                Icons.card_giftcard_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                loc.t('profileInviteTitle'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('profileInviteSubtitle'),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      code!,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code!));

                        // Show overlay toast instead of snackbar so it appears in front of the modal
                        final overlay = Overlay.of(ctx);
                        late OverlayEntry entry;
                        entry = OverlayEntry(
                          builder: (context) => Positioned(
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 120,
                            left: 32,
                            right: 32,
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.inverseSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  loc.t('profileInviteCodeCopied'),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onInverseSurface,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        );
                        overlay.insert(entry);
                        Future.delayed(const Duration(seconds: 2), () {
                          if (entry.mounted) entry.remove();
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.copy_rounded,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                loc.t('profileInviteModalExpiry', {'expiry': expiryText}),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.red.shade400,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: TeqButton(
                  text: loc.t('profileInviteShareBtn'),
                  icon: Icons.share_rounded,
                  size: TeqButtonSize.large,
                  onPressed: () {
                    Navigator.pop(ctx);
                    ShareService.show(context, text: shareText, origin: origin);
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
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

    final loc = ref.read(localizationProvider);
    final token = await StorageService.getToken();
    if (token == null || !mounted) return;

    await showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card(ctx),
          title: Text(
            loc.t('profileChangePassword'),
            style: TextStyle(
              color: AppColors.textPrimary(ctx),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TeqTextField(
                  controller: currentPassCtrl,
                  obscureText: true,
                  labelText: loc.t('fieldCurrentPassword'),
                ),
                const SizedBox(height: 10),
                TeqTextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  labelText: loc.t('fieldNewPassword'),
                ),
                const SizedBox(height: 10),
                TeqTextField(
                  controller: confirmPassCtrl,
                  obscureText: true,
                  labelText: loc.t('fieldNewPasswordConfirm'),
                ),
                if (codeSent) ...[
                  const SizedBox(height: 10),
                  TeqTextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    labelText: loc.t('fieldEmailCode'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TeqButton.outline(
                    text: loc.t('btnCancel'),
                    onPressed: loading ? null : () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TeqButton(
                    text: codeSent ? loc.t('btnChangePassword') : loc.t('btnSendCode'),
                    isLoading: loading,
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
                          error = loc.t('validAllFields');
                          loading = false;
                        });
                        return;
                      }
                      if (newPassCtrl.text.length < 8) {
                        setS(() {
                          error = loc.t('validNewPasswordMin');
                          loading = false;
                        });
                        return;
                      }
                      if (newPassCtrl.text != confirmPassCtrl.text) {
                        setS(() {
                          error = loc.t('validPasswordsMatch');
                          loading = false;
                        });
                        return;
                      }

                      if (!codeSent) {
                        // Doğrulama kodunu gönder
                        try {
                          await apiCall(
                            () => http.post(
                              Uri.parse(
                                '$kBaseUrl/auth/change-password/send-code',
                              ),
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
                          LoggerService.instance.warning(
                            'ProfileScreen',
                            'Şifre kodu gönderilemedi: $e',
                          );
                          setS(() {
                            error = loc.t('errorNetworkMessage');
                            loading = false;
                          });
                        }
                      } else {
                        // Kodu doğrula ve şifreyi değiştir
                        if (codeCtrl.text.trim().length != 6) {
                          setS(() {
                            error = loc.t('validVerificationCode');
                            loading = false;
                          });
                          return;
                        }
                        try {
                          await apiCall(
                            () => http.post(
                              Uri.parse(
                                '$kBaseUrl/auth/change-password/confirm',
                              ),
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
                            TeqSnackBar.show(message: loc.t('msgPasswordChanged'),
                              type: TeqSnackBarType.success,
                            );
                          }
                        } on AppException catch (e) {
                          setS(() {
                            error = e.message;
                            loading = false;
                          });
                        } catch (e) {
                          LoggerService.instance.warning(
                            'ProfileScreen',
                            'Şifre değiştirme başarısız: $e',
                          );
                          setS(() {
                            error = loc.t('errorNetworkMessage');
                            loading = false;
                          });
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final passCtrl = TextEditingController();
    String? error;

    final loc = ref.read(localizationProvider);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card(ctx),
          title: Text(
            loc.t('profileDeleteAccount'),
            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 16, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.t('profileDeleteAccountDesc'),
                style: TextStyle(color: AppColors.textSecondary(ctx), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TeqTextField(
                controller: passCtrl,
                obscureText: true,
                labelText: loc.t('fieldPassword'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TeqButton.outline(
                    text: loc.t('btnCancel'),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TeqButton(
                    text: loc.t('btnDeleteAccount'),
                    customColor: const Color(0xFFEF4444),
                    onPressed: () async {
                if (passCtrl.text.isEmpty) {
                  setS(() => error = loc.t('fieldPassword'));
                  return;
                }
                try {
                  await AuthService.deleteAccount(passCtrl.text);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/login', (_) => false);
                  }
                } on AppException catch (e) {
                  setS(() => error = e.message);
                } catch (e) {
                  LoggerService.instance.warning(
                    'ProfileScreen',
                    'Hesap silinemedi: $e',
                  );
                  setS(() => error = loc.t('errorNetworkMessage'));
                }
              },
            ),
          ),
        ],
      ),
    ],
        ),
      ),
    );
    passCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('navSettings'))),
      backgroundColor: AppColors.bg(context),
      body: LanguageSwitchOverlay(
        isVisible: _isSwitching,
        child: ListView(
        children: [
          const SizedBox(height: 8),

          // ── Pro Araçlar ───────────────────────────────────────────────────
          _SettingsSection(
            title: loc.t('settingsProTools'),
            items: [
              _SettingsTile(
                icon: Icons.workspace_premium_outlined,
                leadingWidget: const FaIcon(
                  FontAwesomeIcons.crown,
                  color: Color(0xFF06B6D4),
                  size: 22,
                ),
                iconColor: const Color(0xFF06B6D4),
                label: loc.t('proHubTitle'),
                trailing: _isPremium
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E1B4B), Color(0xFF4338CA)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          loc.t('settingsProActive'),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
                          ),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          ref.read(localizationProvider).t('pro'),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                onTap: () => _proHubGuard.run(() async {
                  // StorageService'ten güncel is_premium oku — widget.user stale olabilir
                  final freshInfo = await StorageService.getUserInfo();
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProHubScreen(
                        isPremium: freshInfo?['is_premium'] == true,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: loc.t('profileInviteAndEarn'),
            items: [
              ListTile(
                key: _shareTileKey,
                leading: const Icon(
                  Icons.card_giftcard_outlined,
                  color: Color(0xFF16A34A),
                ),
                title: Text(
                  ref.read(localizationProvider).t('profileInviteTitle'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  ref.read(localizationProvider).t('profileInviteSubtitle'),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: _shareLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.chevron_right,
                        color: AppColors.border(context),
                        size: 20,
                      ),
                onTap: _shareInvite,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: loc.t('profileMyListings'),
            items: [
              _SettingsTile(
                icon: Icons.list_alt_outlined,
                label: loc.t('profileActiveListings'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _MyListingsScreen(active: true),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.archive_outlined,
                label: loc.t('profilePassiveListings'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _MyListingsScreen(active: false),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.favorite_outline,
                label: loc.t('profileFavorites'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _FavoritesScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.shopping_bag_outlined,
                label: loc.t('settingsMyPurchases'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PurchasesScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.sell_outlined,
                label: loc.t('settingsMySales'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SalesScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: loc.t('profileActivitySection'),
            items: [
              _SettingsTile(
                icon: Icons.person_add_outlined,
                label: loc.t('followRequests'),
                trailing: _pendingRequestCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _pendingRequestCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FollowRequestsScreen(),
                  ),
                ).then((_) => _loadPendingRequests()),
              ),
              _SettingsTile(
                icon: Icons.call_outlined,
                label: loc.t('callHistoryTitle'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CallHistoryScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.star_outline,
                label: loc.t('settingsMyRatings'),
                trailing: _unreadRatingCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _unreadRatingCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyRatingsScreen()),
                  );
                  // Dönüşte rozeti temizle/güncelle
                  _loadUnreadRatings();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: loc.t('profilePrivacySection'),
            items: [
              ListTile(
                leading: Icon(
                  Icons.lock_outline,
                  color: AppColors.iconColor(context),
                ),
                title: Row(
                  children: [
                    Text(
                      loc.t('privateAccount'),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: AppColors.surface(context),
                            title: Text(
                              loc.t('privateAccount'),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            content: Text(
                              loc.t('privateAccountDesc'),
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                            actions: [
                              TeqButton.text(
                                text: loc.t('btnOk'),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Icon(
                        Icons.help_outline,
                        size: 16,
                        color: AppColors.iconColor(context),
                      ),
                    ),
                  ],
                ),
                trailing: Switch(
                  value: _isPrivate,
                  activeColor: kPrimary,
                  onChanged: _togglePrivateAccount,
                ),
              ),
              _SettingsTile(
                icon: Icons.block_outlined,
                label: loc.t('profileBlockedUsers'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.language_outlined,
                  color: AppColors.iconColor(context),
                ),
                title: Text(
                  loc.t('consentPrivacyNoticeTitle'),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                subtitle: Text(
                  _consentGiven
                      ? loc.t('consentStatusActive').replaceFirst(
                          '{date}',
                          _consentAt != null
                              ? '${_consentAt!.day.toString().padLeft(2, '0')}.${_consentAt!.month.toString().padLeft(2, '0')}.${_consentAt!.year}'
                              : '',
                        )
                      : loc.t('consentStatusNone'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _consentGiven
                        ? Colors.green.shade600
                        : AppColors.textSecondary(context),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ConsentNoticeModal.show(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: loc.t('profileAccountSection'),
            items: [
              _SettingsTile(
                icon: Icons.manage_accounts_outlined,
                label: loc.t('accountInfoMenuLabel'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountInfoScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                label: loc.t('profileChangePassword'),
                onTap: () => _showChangePasswordDialog(context),
              ),
              if (_biometricAvailable)
                ListTile(
                  key: const Key('settings_switch_face_id'),
                  leading: Icon(
                    Icons.face_outlined,
                    color: AppColors.iconColor(context),
                  ),
                  title: Text(
                    loc.t('profileFaceId'),
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  subtitle: Text(
                    _biometricEnabled ? loc.t('statusOn') : loc.t('statusOff'),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  trailing: Switch(
                    value: _biometricEnabled,
                    activeColor: kPrimary,
                    onChanged: _toggleBiometric,
                  ),
                ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                label: loc.t('profileNotificationSettings'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        NotificationSettingsScreen(isPremium: _isPremium),
                  ),
                ),
              ),
              ListTile(
                key: const Key('settings_switch_karanlik_mod'),
                leading: Icon(
                  Icons.dark_mode_outlined,
                  color: AppColors.iconColor(context),
                ),
                title: Text(
                  loc.t('profileDarkMode'),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                subtitle: Text(
                  ThemeProvider.instance.isDark ? loc.t('statusOn') : loc.t('statusOff'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                trailing: Switch(
                  value: ThemeProvider.instance.isDark,
                  activeColor: kPrimary,
                  onChanged: (_) async {
                    await ThemeProvider.instance.toggle();
                    if (mounted) setState(() {});
                  },
                ),
              ),
              ListTile(
                key: const Key('settings_tile_dil'),
                leading: Icon(
                  Icons.language_outlined,
                  color: AppColors.iconColor(context),
                ),
                title: Text(
                  loc.t('settingsLanguage'),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                trailing: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'tr',
                      label: Text(ref.read(localizationProvider).t('langTR')),
                    ),
                    ButtonSegment(
                      value: 'en',
                      label: Text(ref.read(localizationProvider).t('langEN')),
                    ),
                    ButtonSegment(
                      value: 'ru',
                      label: Text(ref.read(localizationProvider).t('langRU')),
                    ),
                    ButtonSegment(
                      value: 'ar',
                      label: Text(ref.read(localizationProvider).t('langAR')),
                    ),
                  ],
                  selected: {_displayedLang},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (selection) => _onLangChange(selection.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: loc.t('profileSupportSection'),
            items: [
              _SettingsTile(
                icon: Icons.help_outline,
                label: loc.t('profileSupportCenter'),
                onTap: () => _urlGuard.run(() async {
                  final uri = Uri.parse('https://www.teqlif.com/support.html');
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }),
              ),
              _SettingsTile(
                icon: Icons.question_answer_outlined,
                label: loc.t('profileFaq'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FaqScreen()),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                label: loc.t('profileTerms'),
                onTap: () => _urlGuard.run(() async {
                  final uri = Uri.parse(
                    'https://www.teqlif.com/kullanim-sartlari.html',
                  );
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }),
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                label: loc.t('profilePrivacy'),
                onTap: () => _urlGuard.run(() async {
                  final uri = Uri.parse(
                    'https://www.teqlif.com/gizlilik-politikasi',
                  );
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }),
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
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFEF4444),
                  ),
                  title: Text(
                    loc.t('btnDeleteAccount'),
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
                    loc.t('btnLogout'),
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => _logoutGuard.run(() async {
                    final nav = Navigator.of(context);
                    await AuthService.logout();
                    nav.pushNamedAndRemoveUntil('/login', (_) => false);
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
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
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
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
  final Widget? leadingWidget;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.iconColor,
    this.leadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          leadingWidget ??
          Icon(icon, color: iconColor ?? AppColors.iconColor(context)),
      title: Text(
        label,
        style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
      ),
      trailing:
          trailing ??
          Icon(Icons.chevron_right, color: AppColors.border(context), size: 20),
      onTap: onTap,
    );
  }
}

// ── Profil düzenle ekranı ──────────────────────────────────────────────────

class _EditProfileScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? user;
  const _EditProfileScreen({required this.user});

  @override
  ConsumerState<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<_EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _linkCtrl;
  late final TextEditingController _instagramCtrl;
  late final TextEditingController _kickCtrl;
  late final TextEditingController _twitchCtrl;
  late final TextEditingController _facebookCtrl;
  late final TextEditingController _youtubeCtrl;
  late final TextEditingController _tiktokCtrl;
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
    _bioCtrl = TextEditingController(
      text: widget.user?['bio'] as String? ?? '',
    );
    _linkCtrl = TextEditingController(
      text: widget.user?['website_url'] as String? ?? '',
    );
    _instagramCtrl = TextEditingController(
      text: _stripPrefix(
        widget.user?['instagram_url'] as String? ?? '',
        'https://instagram.com/',
      ),
    );
    _kickCtrl = TextEditingController(
      text: _stripPrefix(
        widget.user?['kick_url'] as String? ?? '',
        'https://kick.com/',
      ),
    );
    _twitchCtrl = TextEditingController(
      text: _stripPrefix(
        widget.user?['twitch_url'] as String? ?? '',
        'https://twitch.tv/',
      ),
    );
    _facebookCtrl = TextEditingController(
      text: _stripPrefix(
        widget.user?['facebook_url'] as String? ?? '',
        'https://facebook.com/',
      ),
    );
    _youtubeCtrl = TextEditingController(
      text: _stripPrefix(
        widget.user?['youtube_url'] as String? ?? '',
        'https://youtube.com/@',
      ),
    );
    _tiktokCtrl = TextEditingController(
      text: _stripPrefix(
        widget.user?['tiktok_url'] as String? ?? '',
        'https://tiktok.com/@',
      ),
    );
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
    _instagramCtrl.dispose();
    _kickCtrl.dispose();
    _twitchCtrl.dispose();
    _facebookCtrl.dispose();
    _youtubeCtrl.dispose();
    _tiktokCtrl.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final val = _usernameCtrl.text.trim();
    _usernameDebounce?.cancel();
    if (val == (widget.user?['username'] ?? '')) {
      setState(() => _usernameStatus = null);
      return;
    }
    if (val.length < 3) {
      setState(() => _usernameStatus = null);
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(val)) {
      setState(() => _usernameStatus = 'invalid');
      return;
    }
    setState(() => _usernameStatus = 'checking');
    _usernameDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkUsername(val),
    );
  }

  Future<void> _checkUsername(String val) async {
    try {
      final excludeId = widget.user?['id'] as int?;
      final params = {'username': val};
      if (excludeId != null) params['exclude_id'] = excludeId.toString();
      final data = await apiCall(
        () => http.get(
          Uri.parse(
            '$kBaseUrl/auth/check-username',
          ).replace(queryParameters: params),
        ),
      );
      if (!mounted || _usernameCtrl.text.trim() != val) return;
      setState(
        () => _usernameStatus = (data['available'] as bool)
            ? 'available'
            : 'taken',
      );
    } catch (e) {
      LoggerService.instance.warning(
        'EditProfileScreen',
        'Kullanıcı adı kontrolü başarısız: $e',
      );
      if (mounted) setState(() => _usernameStatus = null);
    }
  }

  String _buildImageUrl(String url) {
    if (url.startsWith('http')) return url;
    final origin = kBaseUrl.replaceFirst(RegExp(r'/api.*'), '');
    return '$origin$url';
  }

  Future<void> _pickAndUploadAvatar() async {
    final loc = ref.read(localizationProvider);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(loc.t("profilePickGallery")),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(loc.t("profilePickCamera")),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    // T-HC-09: Kamera seçiminde izni önceden kontrol et
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        final loc = ref.read(localizationProvider);
        showPermissionDeniedDialog(context, title: loc.t('attachCameraPermission'), message: loc.t('permPermanentlyDenied'), openSettingsLabel: loc.t('permOpenSettings'), cancelLabel: loc.t('btnCancel'));
        return;
      }
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    final token = await StorageService.getToken();
    if (token == null) return;

    setState(() {
      _saving = true;
      _uploadingAvatar = true;
    });
    try {
      final file = File(picked.path);
      final upload = await UploadService.uploadFile(file);

      final patchBody = <String, dynamic>{'profile_image_url': upload.url};
      if (upload.thumbUrl != null) {
        patchBody['profile_image_thumb_url'] = upload.thumbUrl;
      }

      final patchResp = await http.patch(
        Uri.parse('$kBaseUrl/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
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
        onboardingCompleted:
            updatedUser['onboarding_completed'] as bool? ?? false,
        isVerified: updatedUser['is_verified'] as bool? ?? false,
        phoneVerified: updatedUser['phone_verified'] as bool? ?? false,
      );
      if (mounted) setState(() => _profileImageUrl = upload.url);
    } catch (e) {
      LoggerService.instance.warning(
        'EditProfileScreen',
        'Avatar yüklenemedi: $e',
      );
      if (!mounted) return;
      TeqSnackBar.show(message: ref.read(localizationProvider).t('profilePhotoUploadError'), type: TeqSnackBarType.info);
    } finally {
      if (mounted)
        setState(() {
          _saving = false;
          _uploadingAvatar = false;
        });
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final loc = ref.read(localizationProvider);
    if (name.isEmpty || username.isEmpty) {
      TeqToast.error(loc.t('editProfileFillAll'));
      return;
    }
    if (username.length < 3 || !RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      TeqToast.error(loc.t('validUsernameInvalid'));
      return;
    }
    if (_usernameStatus == 'taken') {
      TeqToast.error(loc.t('validUsernameTaken'));
      return;
    }
    if (_usernameStatus == 'checking') {
      TeqToast.error(loc.t('usernameCheckingWait'));
      return;
    }
    setState(() {
      _saving = true;
    });
    final linkErrorMsg = ref.read(localizationProvider).t('editProfileLinkError');
    try {
      final token = await StorageService.getToken();
      if (token == null) throw Exception('No token');
      final bio = _bioCtrl.text.trim();
      final link = _linkCtrl.text.trim();
      if (link.isNotEmpty &&
          !link.startsWith('http://') &&
          !link.startsWith('https://')) {
        TeqSnackBar.show(message: linkErrorMsg,
          type: TeqSnackBarType.error,
        );
        setState(() => _saving = false);
        return;
      }
      String? normLink(String v) => v.isEmpty ? null : v;
      String? buildSocial(String prefix, String username) {
        final u = username.replaceAll('@', '').trim();
        return u.isEmpty ? null : '$prefix$u';
      }

      final updatedUser = await apiCall(
        () => http.patch(
          Uri.parse('$kBaseUrl/auth/me'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'full_name': name,
            'username': username,
            'bio': bio.isEmpty ? null : bio,
            'website_url': normLink(link),
            'instagram_url': buildSocial(
              'https://instagram.com/',
              _instagramCtrl.text,
            ),
            'kick_url': buildSocial('https://kick.com/', _kickCtrl.text),
            'twitch_url': buildSocial('https://twitch.tv/', _twitchCtrl.text),
            'facebook_url': buildSocial(
              'https://facebook.com/',
              _facebookCtrl.text,
            ),
            'youtube_url': buildSocial(
              'https://youtube.com/@',
              _youtubeCtrl.text,
            ),
            'tiktok_url': buildSocial('https://tiktok.com/@', _tiktokCtrl.text),
          }),
        ),
      );
      await StorageService.saveUserInfo(
        id: updatedUser['id'] as int,
        email: updatedUser['email'] as String,
        username: updatedUser['username'] as String,
        fullName: updatedUser['full_name'] as String,
        isPremium: updatedUser['is_premium'] as bool? ?? false,
        onboardingCompleted:
            updatedUser['onboarding_completed'] as bool? ?? false,
        isVerified: updatedUser['is_verified'] as bool? ?? false,
        phoneVerified: updatedUser['phone_verified'] as bool? ?? false,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      handleError(e, ref.read(localizationProvider));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final initial = (_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0] : '?')
        .toUpperCase();
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('btnEditProfile')),
        actions: [
          TeqButton.text(
            text: loc.t('btnSave'),
            onPressed: _saving ? null : _save,
            isExpanded: false,
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Builder(
              builder: (ctx) {
                return TeqTextField(
                  controller: _nameCtrl,
                  labelText: loc.t('editProfileFullName'),
                );
              },
            ),
            const SizedBox(height: 14),
            Builder(
              builder: (ctx) {
                return TeqTextField(
                  controller: _usernameCtrl,
                  autocorrect: false,
                  labelText: loc.t('editProfileUsername'),
                  helperText: loc.t('fieldUsernameSubtitle'),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                    TextInputFormatter.withFunction((old, val) => val.copyWith(
                          text: val.text.toLowerCase(),
                          selection: val.selection,
                        )),
                  ],
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
                      ? const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        )
                      : _usernameStatus == 'taken'
                      ? const Icon(Icons.cancel, color: Colors.red, size: 20)
                      : null,
                );
              },
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _bioCtrl,
              builder: (_, val, _) {
                final loc = ref.read(localizationProvider);
                return TeqTextField(
                  controller: _bioCtrl,
                  maxLength: 60,
                  maxLines: 2,
                  labelText: loc.t('editProfileBio'),
                  hintText: loc.t('editProfileBioHint'),
                  helperText: loc.t('editProfileBioHelper'),
                );
              },
            ),
            const SizedBox(height: 14),
            Builder(
              builder: (context) {
                final loc = ref.read(localizationProvider);
                return TeqTextField(
                  controller: _linkCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  labelText: loc.t('editProfileLink'),
                  hintText: loc.t('editProfileLinkHint'),
                  helperText: loc.t('editProfileLinkHelper'),
                );
              },
            ),
            const SizedBox(height: 20),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'Sosyal Medya',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _socialField(_instagramCtrl, 'Instagram', 'instagram.com/'),
            const SizedBox(height: 12),
            _socialField(_kickCtrl, 'Kick', 'kick.com/'),
            const SizedBox(height: 12),
            _socialField(_twitchCtrl, 'Twitch', 'twitch.tv/'),
            const SizedBox(height: 12),
            _socialField(_facebookCtrl, 'Facebook', 'facebook.com/'),
            const SizedBox(height: 12),
            _socialField(_youtubeCtrl, 'YouTube', 'youtube.com/@'),
            const SizedBox(height: 12),
            _socialField(_tiktokCtrl, 'TikTok', 'tiktok.com/@'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _stripPrefix(String url, String prefix) {
    if (url.startsWith(prefix)) return url.substring(prefix.length);
    // legacy: tam URL girişlerini de temizle
    final uri = Uri.tryParse(url);
    if (uri != null && url.startsWith('http'))
      return uri.pathSegments
          .where((s) => s.isNotEmpty)
          .join('/')
          .replaceAll('@', '');
    return url;
  }

  Widget _socialField(
    TextEditingController ctrl,
    String label,
    String urlPrefix,
  ) {
    return TeqTextField(
      controller: ctrl,
      keyboardType: TextInputType.text,
      autocorrect: false,
      labelText: label,
      hintText: 'kullaniciadi',
    );
  }
}

// ── Aktif / Pasif ilanlarım ekranı ────────────────────────────────────────────

class _MyListingsScreen extends ConsumerStatefulWidget {
  final bool active;
  const _MyListingsScreen({required this.active});

  @override
  ConsumerState<_MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<_MyListingsScreen> {
  final List<dynamic> _listings = [];
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  final ScrollController _scrollController = ScrollController();

  ListingFilterState _filter = const ListingFilterState();

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 50) {
        if (!_loading && !_isLoadingMore && _hasMore) {
          _load(loadMore: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _loading = true;
        _listings.clear();
        _offset = 0;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final activeParam = widget.active ? 'true' : 'false';
      final q = _filter.searchQuery ?? '';
      final cat = _filter.category ?? '';
      var listingsUrl =
          '$kBaseUrl/listings/my?active=$activeParam&limit=20&offset=$_offset';
      if (q.isNotEmpty) listingsUrl += '&q=${Uri.encodeComponent(q)}';
      if (cat.isNotEmpty) {
        listingsUrl += '&category=${Uri.encodeComponent(cat)}';
      }
      if (_filter.dateFrom != null && _filter.dateTo != null) {
        listingsUrl +=
            '&date_from=${_filter.dateFrom!.toIso8601String().substring(0, 10)}';
        listingsUrl +=
            '&date_to=${_filter.dateTo!.toIso8601String().substring(0, 10)}';
      }
      final resp = await http.get(
        Uri.parse(listingsUrl),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final newItems = jsonDecode(resp.body) as List;
        setState(() {
          if (newItems.isNotEmpty) {
            _listings.addAll(newItems);
            _offset += newItems.length;
          }
          if (newItems.length < 20) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      LoggerService.instance.warning(
        'MyListingsScreen',
        'İlanlar yüklenemedi: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _toggle(dynamic listing) async {
    if (!mounted) return;
    final loc = ref.read(localizationProvider);
    final id = listing['id'] as int;
    final status = ListingStatusExtension.fromJson(listing);
    final isActive = status == ListingStatus.active;

    final costData = await ListingService.getReactivationCost(id);
    if (!mounted) return;

    final isPremium = costData?['is_premium'] as bool? ?? false;
    final remaining = costData?['free_remaining'] as int? ?? 0;
    final cost = costData?['cost'] as int? ?? 10;
    final balance = costData?['balance'] as int? ?? 0;
    final canAfford = costData?['can_afford'] as bool? ?? false;
    final withinWindow = costData?['within_window'] as bool? ?? false;

    if (isActive) {
      // Aktif → Pasif
      if (!withinWindow) {
        final hintText = (isPremium && remaining > 0)
            ? loc.t('listingDeactivateFreeCreditHint')
            : loc.t('listingDeactivateCostHint', {'cost': cost.toString()});

        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(loc.t('listingDeactivateTitle')),
            content: Text('${loc.t('listingDeactivateWarning')}\n\n$hintText'),
            actions: [
              TeqButton.text(
                text: loc.t('btnDismiss'),
                onPressed: () => Navigator.pop(context, false),
              ),
              TeqButton.text(
                text: loc.t('listingDeactivateConfirm'),
                customColor: const Color(0xFFDC2626),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }
    } else {
      // Pasif → Aktif
      if (!withinWindow) {
        String subtitle;
        if (isPremium && remaining > 0) {
          subtitle = loc.t('listingReactivateFreeCredit', {'remaining': remaining.toString()});
        } else if (isPremium) {
          subtitle = loc.t('listingReactivatePaidPro', {'cost': cost.toString()});
        } else {
          subtitle = loc.t('listingReactivatePaidNormal', {'cost': cost.toString(), 'balance': balance.toString()});
        }

        if (!canAfford) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(loc.t('listingReactivateTitle')),
              content: Text(loc.t('listingReactivateInsufficientBalance')),
              actions: [
                TeqButton.text(
                  text: loc.t('btnDismiss'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );
          return;
        }

        String extraHint = '';
        if (!isPremium) extraHint = '\n\n${loc.t('listingReactivateProUpsell')}';

        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(loc.t('listingReactivateTitle')),
            content: Text(subtitle + extraHint),
            actions: [
              TeqButton.text(
                text: loc.t('btnDismiss'),
                onPressed: () => Navigator.pop(context, false),
              ),
              TeqButton.text(
                text: loc.t('listingReactivateConfirm'),
                customColor: const Color(0xFF6366F1),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }
    }

    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/listings/$id/toggle'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        await _load();
      } else if (resp.statusCode == 402 && mounted) {
        TeqSnackBar.show(message: ref.read(localizationProvider).t('listingReactivateInsufficientBalance'), type: TeqSnackBarType.info);
      }
    } catch (e) {
      LoggerService.instance.warning(
        'MyListingsScreen',
        'İlan durumu değiştirilemedi: $e',
      );
      handleError(e, ref.read(localizationProvider));
    }
  }

  Future<void> _delete(dynamic listing) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ref.read(localizationProvider).t('listingDeleteDialogTitle')),
        content: Text(ref.read(localizationProvider).t('listingDeleteDialogBody')),
        actions: [
          TeqButton.text(
            text: ref.read(localizationProvider).t('btnDismiss'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TeqButton.text(
            text: ref.read(localizationProvider).t('btnDeleteConfirm'),
            customColor: const Color(0xFFDC2626),
            onPressed: () => Navigator.pop(context, true),
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
      handleError(e, ref.read(localizationProvider));
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
    final bool hasFilter = !_filter.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.active ? loc.t('profileActiveListings') : loc.t('profilePassiveListings'),
        ),
      ),
      backgroundColor: AppColors.bg(context),
      body: Column(
        children: [
          TeqFilterBar(
            filter: _filter,
            onChanged: (f) {
              setState(() => _filter = f);
              _load();
            },
            showSubcategory: false,
            showCity: false,
            showCondition: false,
            showSort: false,
            showPriceRange: false,
          ),
          Expanded(
            child: _loading && _listings.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  )
                : _listings.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          hasFilter
                              ? Icons.search_off
                              : (widget.active
                                    ? Icons.list_alt_outlined
                                    : Icons.archive_outlined),
                          size: 52,
                          color: const Color(0xFFD1D5DB),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          hasFilter
                              ? loc.t('searchNoResults')
                              : (widget.active
                                    ? loc.t('emptyActiveListings')
                                    : loc.t('emptyPassiveListings')),
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: kPrimary,
                    onRefresh: () => _load(),
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _listings.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        if (i == _listings.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final l = _listings[i];
                        final imgs = l['image_urls'] as List? ?? [];
                        final rawImg = imgs.isNotEmpty
                            ? imgs[0] as String
                            : l['image_url'] as String?;
                        final imageUrl = rawImg != null ? imgUrl(rawImg) : null;
                        return TeqCard(
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: imageUrl != null
                                  ? CachedNetworkImage(
                                      cacheManager: TeqlifCacheManager(),
                                      imageUrl: imageUrl,
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) => const SizedBox(
                                        width: 60,
                                        height: 60,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_, _, _) =>
                                          _imgPlaceholder(),
                                    )
                                  : _imgPlaceholder(),
                            ),
                            title: Text(
                              l['title'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              _fmt(l['price']),
                              style: const TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    widget.active
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: widget.active
                                        ? const Color(0xFF6B7280)
                                        : kPrimary,
                                    size: 22,
                                  ),
                                  tooltip: widget.active
                                      ? 'Pasife Al'
                                      : 'Aktif Yap',
                                  onPressed: () => _toggle(l),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFDC2626),
                                    size: 22,
                                  ),
                                  tooltip: 'Sil',
                                  onPressed: () => _delete(l),
                                ),
                              ],
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ListingDetailScreen(
                                  listing: Map<String, dynamic>.from(l),
                                ),
                              ),
                            ).then((_) => _load()),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() => Builder(
    builder: (context) => Container(
      width: 60,
      height: 60,
      color: AppColors.surfaceVariant(context),
      child: Icon(Icons.image_outlined, color: AppColors.border(context)),
    ),
  );
}

// ── Favorilerim ekranı ─────────────────────────────────────────────────────────

class _FavoritesScreen extends ConsumerStatefulWidget {
  const _FavoritesScreen();

  @override
  ConsumerState<_FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<_FavoritesScreen> {
  List<dynamic> _listings = [];
  bool _loading = true;
  bool _hasError = false;

  ListingFilterState _filter = const ListingFilterState();

  List<dynamic> get _filteredListings {
    final cacheMap = ref.watch(listingInteractionCacheProvider);
    var result = _listings.where((item) {
      final id = item['id'] as int;
      final cached = cacheMap[id] ?? ListingService.getCachedLike(id);
      if (cached == false) return false;
      return true;
    }).toList();
    if (_filter.searchQuery != null && _filter.searchQuery!.isNotEmpty) {
      final q = _filter.searchQuery!.toLowerCase();
      result = result.where((item) {
        final title = (item['title'] as String? ?? '').toLowerCase();
        final desc = (item['description'] as String? ?? '').toLowerCase();
        return title.contains(q) || desc.contains(q);
      }).toList();
    }
    if (_filter.category != null && _filter.category!.isNotEmpty) {
      result = result
          .where((item) => (item['category'] as String?) == _filter.category)
          .toList();
    }
    if (_filter.dateFrom != null && _filter.dateTo != null) {
      final start = _filter.dateFrom!;
      final end = _filter.dateTo!.add(const Duration(days: 1));
      result = result.where((item) {
        final raw = item['created_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    final cached = CacheService.getData('user_favorites');
    if (cached != null) {
      if (mounted)
        setState(() {
          _listings = List.from(cached as List);
          _loading = false;
          _hasError = false;
        });
    } else {
      if (mounted)
        setState(() {
          _loading = true;
          _hasError = false;
        });
    }
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as List;
        await CacheService.saveData(
          'user_favorites',
          data,
          ttl: const Duration(minutes: 10),
        );
        if (mounted)
          setState(() {
            _listings = data;
            _hasError = false;
          });
      }
    } catch (e) {
      LoggerService.instance.warning(
        'FavoritesScreen',
        'Favoriler yüklenemedi: $e',
      );
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFavorite(dynamic listing) async {
    final id = listing['id'] as int;
    // Optimistic: anında listeden kaldır; cache'i hemen güncelle
    ListingService.setLikeCache(id, false);
    setState(() => _listings.removeWhere((l) => l['id'] == id));
    try {
      await ListingService.toggleFavoriteAndLike(id, true);
    } catch (e) {
      LoggerService.instance.warning(
        'FavoritesScreen',
        'Favori kaldırılamadı: $e',
      );
      ListingService.setLikeCache(id, true);
      await _load();
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
    final filtered = _filteredListings;
    final bool hasFilter = !_filter.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(loc.t('profileFavorites'))),
      backgroundColor: AppColors.bg(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _hasError && _listings.isEmpty
          ? NetworkErrorWidget(onRetry: _load)
          : _listings.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.favorite_border,
                    size: 52,
                    color: Color(0xFFD1D5DB),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    loc.t('favoritesEmpty'),
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_hasError) StaleDataBanner(onRetry: _load),
                TeqFilterBar(
                  filter: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                  showSubcategory: false,
                  showCity: false,
                  showCondition: false,
                  showSort: false,
                  showPriceRange: false,
                ),
                if (hasFilter && filtered.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        loc.t('searchNoResults'),
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: RefreshIndicator(
                      color: kPrimary,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final l = filtered[i];
                          final imgs = l['image_urls'] as List? ?? [];
                          final rawImg = imgs.isNotEmpty
                              ? imgs[0] as String
                              : l['image_url'] as String?;
                          final imageUrl = rawImg != null
                              ? imgUrl(rawImg)
                              : null;
                          return TeqCard(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imageUrl != null
                                    ? CachedNetworkImage(
                                        cacheManager: TeqlifCacheManager(),
                                        imageUrl: imageUrl,
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => const SizedBox(
                                          width: 60,
                                          height: 60,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                            ),
                                          ),
                                        ),
                                        errorWidget: (_, _, _) =>
                                            _imgPlaceholder(),
                                      )
                                    : _imgPlaceholder(),
                              ),
                              title: Text(
                                l['title'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fmt(l['price']),
                                    style: const TextStyle(
                                      color: kPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '@${(l['user'] as Map?)?['username'] ?? ''}',
                                    style: const TextStyle(
                                      color: Color(0xFF9CA3AF),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.favorite,
                                  color: Colors.red,
                                  size: 22,
                                ),
                                tooltip: loc.t("removeFromFavoritesTooltip"),
                                onPressed: () => _removeFavorite(l),
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ListingDetailScreen(
                                    listing: Map<String, dynamic>.from(l),
                                  ),
                                ),
                              ).then((_) => _load()),
                            ),
                          );
                        },
                      ),
                    ),
                  ), // ListView.separated + RefreshIndicator + Expanded
              ],
            ), // Column
    );
  }

  Widget _imgPlaceholder() => Container(
    width: 60,
    height: 60,
    color: const Color(0xFFF3F4F6),
    child: const Icon(Icons.image_outlined, color: Color(0xFFD1D5DB)),
  );
}

// ── TUCi Cüzdan Kartı ───────────────────────────────────────────────────────

class _TuciWalletCard extends ConsumerStatefulWidget {
  final int? balance;
  final List<dynamic> history;
  final Future<void> Function() onRefresh;

  const _TuciWalletCard({
    required this.balance,
    required this.history,
    required this.onRefresh,
  });

  @override
  ConsumerState<_TuciWalletCard> createState() => _TuciWalletCardState();
}

class _TuciWalletCardState extends ConsumerState<_TuciWalletCard> {
  bool _refreshing = false;

  void _openSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TuciWalletSheet(
        balance: widget.balance ?? 0,
        history: widget.history,
      ),
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
        margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB8860B), Color(0xFFFFD700), Color(0xFFFFA500)],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
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
                child: Text(
                  'T',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.read(localizationProvider).t('lblTuciWallet'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  widget.balance == null
                      ? const SizedBox(
                          width: 80,
                          height: 20,
                          child: LinearProgressIndicator(
                            color: Colors.white54,
                            backgroundColor: Colors.white24,
                          ),
                        )
                      : Text(
                          '${widget.balance} TUCi',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                ],
              ),
            ),
            // Yenile ikonu
            GestureDetector(
              onTap: _handleRefresh,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white70,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

class _TuciWalletSheet extends ConsumerWidget {
  final int balance;
  final List<dynamic> history;

  const _TuciWalletSheet({required this.balance, required this.history});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tutamaç
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Bakiye
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFB8860B),
                  Color(0xFFFFD700),
                  Color(0xFFFFA500),
                ],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
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
                Text(
                  ref.read(localizationProvider).t('walletBalance'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '$balance TUCi',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Son işlemler
          if (history.isNotEmpty) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                ref.read(localizationProvider).t('walletRecentTxns'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...history.map((t) {
              final amount = t['amount'] as int? ?? 0;
              final label =
                  t['label'] as String? ??
                  t['transaction_type'] as String? ??
                  '';
              final isPositive = amount > 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isPositive
                            ? Colors.green.shade50
                            : Colors.red.shade50,
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
                        color: isPositive
                            ? Colors.green.shade700
                            : Colors.red.shade700,
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
            child: TeqButton(
              text: loc.t('walletBuyBtn'),
              icon: Icons.schedule_rounded,
              isDisabled: true, // onPressed is null
              onPressed: null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tam Cüzdan Ekranı ────────────────────────────────────────────────────────

class WalletScreen extends ConsumerStatefulWidget {
  final int? initialBalance;
  final List<dynamic> initialHistory;

  const WalletScreen({
    super.key,
    this.initialBalance,
    this.initialHistory = const [],
  });

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  int? _balance;
  List<dynamic> _txns = [];
  bool _loading = false;

  Map<String, String> _typeLabels(TranslationPack loc) => {
    'airdrop': loc.t('walletTxnAirdrop'),
    'churn_airdrop': loc.t('walletTxnChurnAirdrop'),
    'receive_gift': loc.t('walletTxnReceiveGift'),
    'send_gift': loc.t('walletTxnSendGift'),
    'spend_lead_gen': loc.t('walletTxnSpendLeadGen'),
    'spend_ad_campaign': loc.t('walletTxnSpendAdCampaign'),
    'spend_ai': loc.t('walletTxnSpendAi'),
    'spend_ai_desc': loc.t('walletTxnSpendAiDesc'),
    'spend_retargeting': loc.t('walletTxnSpendRetargeting'),
    'spend_boost': loc.t('walletTxnSpendBoost'),
    'spend_boost_paid': loc.t('walletTxnSpendBoostPaid'),
    'spend_reactivation': loc.t('walletTxnSpendReactivation'),
    'web_topup': loc.t('walletTxnWebTopup'),
    'referral_bonus': loc.t('walletTxnReferralBonus'),
    'welcome_bonus': loc.t('walletTxnWelcomeBonus'),
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

  Widget _buildTxnRow(dynamic t, TranslationPack loc) {
    final amount = t['amount'] as int? ?? 0;
    final label =
        _typeLabels(loc)[t['transaction_type'] as String? ?? ''] ??
        (t['label'] as String? ?? t['transaction_type'] as String? ?? '');
    final isPos = amount > 0;
    final dateStr = t['created_at'] as String? ?? '';
    String formattedDate = '';
    try {
      final d = DateTime.parse(dateStr).toLocal();
      formattedDate =
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {}
    return InkWell(
      onTap: () => _showTxnDetailSheet(context, t, loc),
      borderRadius: BorderRadius.circular(8),
      child: _TxnRow(
        label: label,
        amount: amount,
        isPositive: isPos,
        date: formattedDate,
      ),
    );
  }

  void _showTxnDetailSheet(
    BuildContext context,
    dynamic t,
    TranslationPack loc,
  ) {
    final txnId = t['id'] as int?;
    final amount = t['amount'] as int? ?? 0;
    final label =
        _typeLabels(loc)[t['transaction_type'] as String? ?? ''] ??
        (t['label'] as String? ?? t['transaction_type'] as String? ?? '');
    final isPos = amount > 0;
    final dateStr = t['created_at'] as String? ?? '';
    String formattedDate = '';
    try {
      final d = DateTime.parse(dateStr).toLocal();
      formattedDate =
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {}
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TxnDetailSheet(
        txnId: txnId,
        label: label,
        amount: amount,
        isPositive: isPos,
        formattedDate: formattedDate,
        loc: loc,
      ),
    );
  }

  void _showAllTxnsModal(BuildContext context, TranslationPack loc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            // Tutamaç
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Başlık
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 8, 8),
              child: Row(
                children: [
                  Text(
                    loc.t('walletAllTxnsTitle'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // İşlem listesi
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 32),
                itemCount: _txns.length,
                itemBuilder: (_, i) => _buildTxnRow(_txns[i], loc),
              ),
            ),
          ],
        ),
      ),
    );
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
    final loc = ref.watch(localizationProvider);
    final summary = _spendingSummary;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ref.read(localizationProvider).t('walletTitle'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
          children: [
            const SizedBox(height: 16),

            // ── Bakiye kartı ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFB8860B),
                    Color(0xFFFFD700),
                    Color(0xFFFFA500),
                  ],
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
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
                  Text(
                    loc.t('walletBalance'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
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
              Text(
                loc.t('walletSpendingSummary'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              ...summary.entries.map(
                (e) => _SummaryRow(
                  label: _typeLabels(loc)[e.key] ?? e.key,
                  amount: e.value,
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── İşlem geçmişi ─────────────────────────────────────────
            if (_txns.isNotEmpty) ...[
              Text(
                loc.t('walletTxnHistory'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              ..._txns.take(20).map((t) => _buildTxnRow(t, loc)),
              if (_txns.length > 20) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showAllTxnsModal(context, loc),
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text(loc.t('walletSeeAllTxns', {'n': _txns.length.toString()})),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ] else if (!_loading) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  loc.t('walletNoTxns'),
                  style: const TextStyle(color: Colors.grey),
                ),
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
                    loc.t('walletComingSoonLabel'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loc.t('walletComingSoonDesc'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF78350F),
                      height: 1.5,
                    ),
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
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFFFD700),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            '$amount TUCi',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB8860B),
            ),
          ),
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
  const _TxnRow({
    required this.label,
    required this.amount,
    required this.isPositive,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isPositive
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.red.withValues(alpha: 0.15),
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
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (date.isNotEmpty)
                  Text(
                    date,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
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

// ─── Transaction Detail Bottom Sheet ─────────────────────────────────────────

class _TxnDetailSheet extends ConsumerStatefulWidget {
  final int? txnId;
  final String label;
  final int amount;
  final bool isPositive;
  final String formattedDate;
  final TranslationPack loc;

  const _TxnDetailSheet({
    required this.txnId,
    required this.label,
    required this.amount,
    required this.isPositive,
    required this.formattedDate,
    required this.loc,
  });

  @override
  ConsumerState<_TxnDetailSheet> createState() => _TxnDetailSheetState();
}

class _TxnDetailSheetState extends ConsumerState<_TxnDetailSheet> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    if (widget.txnId == null) {
      setState(() => _loading = false);
      return;
    }
    final data = await WalletService.getTransactionDetail(widget.txnId!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = data;
      _error = data == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final listing = _detail?['listing'] as Map<String, dynamic>?;
    final stream = _detail?['stream'] as Map<String, dynamic>?;
    final giftEvent = _detail?['gift_event'] as Map<String, dynamic>?;
    final imageUrl = listing?['image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.90,
      minChildSize: 0.35,
      expand: false,
      builder: (ctx, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: EdgeInsets.zero,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // Header row
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 8, 8),
            child: Row(
              children: [
                Text(
                  loc.t('walletDetailTitle'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                loc.t('walletDetailLoadingError'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            // Listing thumbnail (collapse if none)
            if (hasImage)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl.startsWith('/uploads')
                        ? 'https://teqlif.com$imageUrl'
                        : imageUrl,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      height: 160,
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                    ),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Amount badge
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: widget.isPositive
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.isPositive
                          ? Icons.add_circle_rounded
                          : Icons.remove_circle_rounded,
                      color: widget.isPositive
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.t('walletDetailAmount'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          '${widget.isPositive ? '+' : ''}${widget.amount} TUCi',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: widget.isPositive
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Detail rows
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _DetailRow(label: loc.t('walletDetailType'), value: widget.label),
                  _DetailRow(
                    label: loc.t('walletDetailDate'),
                    value: widget.formattedDate,
                  ),

                  // Listing info
                  if (listing != null) ...[
                    const Divider(height: 24),
                    _DetailRow(
                      label: loc.t('walletDetailListing'),
                      value: listing['title'] as String? ?? '—',
                      badge:
                          (ListingStatusExtension.fromJson(listing) ==
                              ListingStatus.passive)
                          ? loc.t('walletDetailListingInactive')
                          : null,
                    ),
                    if ((listing['category'] as String?) != null)
                      _DetailRow(
                        label: 'Kategori',
                        value: listing['category'] as String,
                      ),
                    if (listing['price'] != null)
                      _DetailRow(
                        label: 'Fiyat',
                        value: '${listing['price']} ₺',
                      ),
                    const SizedBox(height: 12),
                    _NavButton(
                      icon: Icons.storefront_rounded,
                      label: loc.t('walletDetailGoListing'),
                      onTap: () async {
                        final listingId = listing['id'] as int?;
                        if (listingId == null) return;
                        final full = await ListingService.getListingById(
                          listingId,
                        );
                        if (full != null && ctx.mounted) {
                          Navigator.push(
                            ctx,
                            MaterialPageRoute(
                              builder: (_) => ListingDetailScreen(
                                listing: Map<String, dynamic>.from(full),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    if ((listing['owner_username'] as String?) != null)
                      _NavButton(
                        icon: Icons.person_rounded,
                        label: loc.t('walletDetailGoOwner'),
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => PublicProfileScreen(
                              username: listing['owner_username'] as String,
                              userId: listing['owner_id'] as int?,
                            ),
                          ),
                        ),
                      ),
                  ],

                  // Stream info (eski referans türü)
                  if (stream != null) ...[
                    const Divider(height: 24),
                    _DetailRow(
                      label: loc.t('walletDetailStream'),
                      value: stream['title'] as String? ?? '—',
                    ),
                    const SizedBox(height: 12),
                    _NavButton(
                      icon: Icons.bar_chart_rounded,
                      label: loc.t('walletDetailGoStream'),
                      onTap: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => LiveStreamAnalyticsScreen(
                            streamId: stream['id'] as int,
                          ),
                        ),
                      ),
                    ),
                    if ((stream['host_username'] as String?) != null)
                      _NavButton(
                        icon: Icons.person_rounded,
                        label: loc.t('walletDetailGoStreamHost'),
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => PublicProfileScreen(
                              username: stream['host_username'] as String,
                              userId: stream['host_id'] as int?,
                            ),
                          ),
                        ),
                      ),
                  ],

                  // Gift event info
                  if (giftEvent != null) ...[
                    const Divider(height: 24),
                    _GiftNameBadge(
                      giftName: giftEvent['gift_name'] as String? ?? '—',
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: loc.t('walletDetailGiftSender'),
                      value:
                          (giftEvent['sender'] as Map?)?['username']
                              as String? ??
                          '—',
                    ),
                    _DetailRow(
                      label: loc.t('walletDetailGiftReceiver'),
                      value:
                          (giftEvent['receiver'] as Map?)?['username']
                              as String? ??
                          '—',
                    ),
                    if ((giftEvent['stream'] as Map?)?['title'] != null)
                      _DetailRow(
                        label: loc.t('walletDetailGiftStream'),
                        value: (giftEvent['stream'] as Map)['title'] as String,
                      ),
                    if (giftEvent['host_share'] != null &&
                        (giftEvent['host_share'] as int) > 0)
                      _DetailRow(
                        label: loc.t('walletDetailGiftHostShare'),
                        value: '${giftEvent['host_share']} TUCi',
                      ),
                    const SizedBox(height: 12),
                    if ((giftEvent['stream'] as Map?)?['id'] != null)
                      _NavButton(
                        icon: Icons.bar_chart_rounded,
                        label: loc.t('walletDetailGoGiftStream'),
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => LiveStreamAnalyticsScreen(
                              streamId:
                                  (giftEvent['stream'] as Map)['id'] as int,
                            ),
                          ),
                        ),
                      ),
                    if ((giftEvent['sender'] as Map?)?['username'] != null)
                      _NavButton(
                        icon: Icons.person_rounded,
                        label: loc.t('walletDetailGoGiftSender'),
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => PublicProfileScreen(
                              username:
                                  (giftEvent['sender'] as Map)['username']
                                      as String,
                              userId:
                                  (giftEvent['sender'] as Map)['id'] as int?,
                            ),
                          ),
                        ),
                      ),
                    if ((giftEvent['receiver'] as Map?)?['username'] != null)
                      _NavButton(
                        icon: Icons.person_rounded,
                        label: loc.t('walletDetailGoGiftReceiver'),
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => PublicProfileScreen(
                              username:
                                  (giftEvent['receiver'] as Map)['username']
                                      as String,
                              userId:
                                  (giftEvent['receiver'] as Map)['id'] as int?,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }
}

class _GiftNameBadge extends ConsumerWidget {
  final String giftName;
  const _GiftNameBadge({required this.giftName});

  static const _giftEmojis = {
    'rose': '🌹',
    'heart': '❤️',
    'fire': '🔥',
    'star': '⭐',
    'diamond': '💎',
    'crown': '👑',
    'rocket': '🚀',
    'trophy': '🏆',
    'money': '💰',
    'clap': '👏',
    'kiss': '💋',
    'gift': '🎁',
    'ateş': '🔥',
    'elmas': '💎',
    'kral tacı': '👑',
  };

  String _displayName(TranslationPack loc) {
    switch (giftName.toLowerCase()) {
      case 'fire':
      case 'ateş':
      case 'огонь':
      case 'نار':
        return loc.t('giftNameFire');
      case 'diamond':
      case 'elmas':
      case 'бриллиант':
      case 'ماس':
        return loc.t('giftNameDiamond');
      case 'crown':
      case 'kral tacı':
      case 'королевская корона':
      case 'تاج ملكي':
        return loc.t('giftNameCrown');
      default:
        return giftName;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final emoji = _giftEmojis[giftName.toLowerCase()] ?? '🎁';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEC4899).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFEC4899).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text(
            _displayName(loc),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFEC4899),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: kPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textTertiary(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? badge;
  const _DetailRow({required this.label, required this.value, this.badge});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFF97316),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SocialLinksRow extends StatelessWidget {
  final Map<String, dynamic>? user;
  final int? userId;

  const _SocialLinksRow({required this.user, required this.userId});

  // website_url is displayed separately above; excluded here
  static const _platforms = [
    _SocialPlatform(
      'instagram_url',
      FontAwesomeIcons.instagram,
      Color(0xFFE1306C),
      'instagram',
    ),
    _SocialPlatform('kick_url', null, Color(0xFF53FC18), 'kick'),
    _SocialPlatform(
      'twitch_url',
      FontAwesomeIcons.twitch,
      Color(0xFF9146FF),
      'twitch',
    ),
    _SocialPlatform(
      'facebook_url',
      FontAwesomeIcons.facebook,
      Color(0xFF1877F2),
      'facebook',
    ),
    _SocialPlatform(
      'youtube_url',
      FontAwesomeIcons.youtube,
      Color(0xFFFF0000),
      'youtube',
    ),
    _SocialPlatform(
      'tiktok_url',
      FontAwesomeIcons.tiktok,
      Color(0xFF010101),
      'tiktok',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = _platforms
        .where((p) => (user?[p.field] as String?)?.isNotEmpty == true)
        .toList();
    if (active.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: active.map((p) {
        final raw = user![p.field] as String;
        final iconColor = p.color == const Color(0xFF010101)
            ? (isDark ? Colors.white : Colors.black)
            : p.color;
        return Tooltip(
          message: raw,
          child: GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(
                raw.startsWith('http') ? raw : 'https://$raw',
              );
              if (uri != null && await canLaunchUrl(uri)) {
                AnalyticsService.logInteraction(
                  itemId: userId ?? 0,
                  itemType: 'user',
                  interactionType: 'social_link_tap',
                  metadata: {'platform': p.key},
                );
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: p.color.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: p.faIcon != null
                    ? FaIcon(p.faIcon!, color: iconColor, size: 16)
                    : Text(
                        p.key.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SocialPlatform {
  final String field;
  final IconData? faIcon;
  final Color color;
  final String key;
  const _SocialPlatform(this.field, this.faIcon, this.color, this.key);
}

class _ScoreBadge extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final Color color;

  const _ScoreBadge({
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    required this.color,
  });

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(hint),
        actions: [
          TeqButton.text(
            text: 'Tamam',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showInfo(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(9, 4, 9, 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
