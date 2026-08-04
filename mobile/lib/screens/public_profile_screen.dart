import 'package:intl/intl.dart';
import '../widgets/ratings/expandable_comment.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/analytics_service.dart';
import '../services/share_service.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../config/api.dart';
import '../ui_library/components/buttons/teq_button.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/overlays/teq_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import 'messages_screen.dart';
import '../services/call_service.dart';
import 'follow_list_screen.dart';
import 'listing_detail_screen.dart';
import 'live/swipe_live_screen.dart';
import '../models/listing_filter_state.dart';
import '../ui_library/components/filters/teq_filter_bar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'viewmodels/public_profile_view_model.dart';

const _starColor = Color(0xFFF59E0B);

class PublicProfileScreen extends ConsumerStatefulWidget {
  final String username;
  final int? userId;
  const PublicProfileScreen({super.key, required this.username, this.userId});

  @override
  ConsumerState<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _listings = [];
  bool _loading = true;
  bool _isOwnProfile = false;
  String _followStatus = 'none';
  bool _isPrivate = false;
  bool _followLoading = false;
  bool _isBlocked = false;
  Map<String, dynamic>? _ratingSummary;

  ListingFilterState _filter = const ListingFilterState();

  List<dynamic> get _filteredListings {
    var r = _listings;
    if (_filter.category != null && _filter.category!.isNotEmpty) {
      r = r.where((l) => l['category'] == _filter.category).toList();
    }
    if (_filter.subcategory != null && _filter.subcategory!.isNotEmpty) {
      r = r.where((l) => l['subcategory'] == _filter.subcategory).toList();
    }
    if (_filter.searchQuery != null && _filter.searchQuery!.isNotEmpty) {
      final q = _filter.searchQuery!.toLowerCase();
      r = r.where((l) {
        final title = (l['title'] as String? ?? '').toLowerCase();
        final desc = (l['description'] as String? ?? '').toLowerCase();
        return title.contains(q) || desc.contains(q);
      }).toList();
    }
    if (_filter.dateFrom != null && _filter.dateTo != null) {
      final start = _filter.dateFrom!;
      final end = _filter.dateTo!.add(const Duration(days: 1));
      r = r.where((l) {
        final dateStr = l['created_at'] as String?;
        if (dateStr == null) return true;
        final date = DateTime.tryParse(dateStr);
        if (date == null) return true;
        return !date.isBefore(start) && date.isBefore(end);
      }).toList();
    }
    return r;
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showRatingForm() {
    if (_user == null) return;
    final userId = _user!['id'] as int;
    final existingRating =
        _ratingSummary?['my_rating'] as Map<String, dynamic>?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RatingFormSheet(
        userId: userId,
        existingScore: existingRating?['score'] as int?,
        existingComment: existingRating?['comment'] as String?,
        onSaved: (score, comment) async {
          Navigator.pop(ctx);
          final args = PublicProfileArgs(username: widget.username, userId: widget.userId);
          await ref.read(publicProfileProvider(args).notifier).saveRating(score, comment);
          ref.read(publicProfileProvider(args).notifier).reloadRatingSummary();
        },
      ),
    );
  }

  void _showRatingsList() {
    if (_user == null) return;
    final userId = _user!['id'] as int;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RatingsListSheet(
        userId: userId,
        summary: _ratingSummary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final args = PublicProfileArgs(username: widget.username, userId: widget.userId);
    final stateAsync = ref.watch(publicProfileProvider(args));

    return stateAsync.when(
      data: (state) {
        _user = state.user;
        _listings = state.listings;
        _isOwnProfile = state.isOwnProfile;
        _followStatus = state.followStatus;
        _isPrivate = state.isPrivate;
        _isBlocked = state.isBlocked;
        _ratingSummary = state.ratingSummary;
        _filter = state.filter;
        _followLoading = state.followLoading;
        _loading = false;
        
        return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('@${widget.username}'),
        actions: [
          if (_user != null && !_isOwnProfile) ...[
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () {
                final uid = (_user!['id'] as int?) ?? widget.userId ?? 0;
                final name = (_user!['full_name'] as String?) ?? widget.username;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DirectChatScreen(
                      otherUserId: uid,
                      displayName: name,
                      otherHandle: widget.username,
                    ),
                  ),
                );
              },
            ),
            if (_followStatus == 'accepted')
              IconButton(
                icon: const Icon(Icons.call),
                onPressed: () {
                  if (CallService.instance.hasActiveCall) return;
                  final uid = (_user!['id'] as int?) ?? widget.userId ?? 0;
                  CallService.instance.startCall(
                    calleeId: uid,
                    calleeUsername: widget.username,
                    calleeAvatar: _user?['profile_image_thumb_url'] as String?,
                  );
                },
              ),
          ],
          Builder(
            builder: (btnCtx) => IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: loc.t('btnShareProfile'),
              onPressed: () {
                final box = btnCtx.findRenderObject() as RenderBox?;
                final origin = box == null
                    ? Rect.zero
                    : box.localToGlobal(Offset.zero) & box.size;
                final imageUrl = _user?['profile_image_url'] as String?;
                ShareService.show(
                  btnCtx,
                  url: 'https://www.teqlif.com/profil/${widget.username}',
                  text: '@${widget.username} — teqlif\'te incele',
                  imageUrl: imageUrl,
                  origin: origin,
                );
              },
            ),
          ),
        ],
      ),
      body: _user == null
          ? Center(child: Text(loc.t('pubProfileUserNotFound')))
          : _buildBody(),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text('@${widget.username}')),
        body: const Center(child: CircularProgressIndicator(color: kPrimary)),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text('@${widget.username}')),
        body: const Center(child: Text('Error loading profile')),
      ),
    );
  }

  Widget _buildBody() {
    final loc = ref.read(localizationProvider);
    final fullName = (_user!['full_name'] as String?) ?? widget.username;
    final userId = (_user!['id'] as int?) ?? widget.userId ?? 0;
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
    final listingCount = _user!['active_listings_count'] ?? 0;
    final followerCount = _user!['follower_count'] ?? 0;
    final followingCount = _user!['following_count'] ?? 0;
    final hasMyRating = _ratingSummary?['my_rating'] != null;
    final avgRaw = _ratingSummary?['average'];
    final hasRating = avgRaw != null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 28, 24, 0),
            child: Column(
              children: [
                // Avatar
                _buildAvatar(fullName, initial),
                const SizedBox(height: 14),
                Text(
                  fullName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                // ── Verified, PRO, Rank ─────────────────────
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    if (_user!['is_verified'] == true)
                      GestureDetector(
                        onTap: () {
                          TeqDialog.show(
                            context: context,
                            title: 'Verified',
                            message: ref.read(localizationProvider).t('badgeVerifiedHint'),
                            primaryButtonText: 'Tamam',
                            onPrimaryPressed: () => Navigator.pop(context),
                          );
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const FaIcon(
                                FontAwesomeIcons.circleCheck,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ref.read(localizationProvider).t('badgeVerified'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_user?['influence_rank'] != null && (_user!['influence_rank'] as int) > 0)
                      _ProfileBadge(
                        icon: FontAwesomeIcons.rankingStar,
                        title: ref.read(localizationProvider).t('influenceRankLabel'),
                        value: '${_user!['influence_rank']}',
                        color: const Color(0xFF8B5CF6),
                        hint: ref.read(localizationProvider).t('influenceRankHint'),
                      ),
                    if (_user?['trust_score'] != null)
                      Builder(builder: (_) {
                        final ts = (_user!['trust_score'] as num).toInt();
                        final loc = ref.read(localizationProvider);
                        return _ProfileBadge(
                          icon: FontAwesomeIcons.shieldHalved,
                          title: loc.t('trustScoreLabel'),
                          value: '$ts / 100',
                          color: ts >= 70
                              ? const Color(0xFF10B981)
                              : ts >= 35
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFF9CA3AF),
                          hint: loc.t('trustScoreHint'),
                        );
                      }),
                  ],
                ),
                const SizedBox(height: 8),
                _SocialLinksRow(user: _user, userId: userId),
                const SizedBox(height: 12),

                // Rating badge
                _buildRatingBadge(hasRating, avgRaw),
                const SizedBox(height: 12),

                // Stats row
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _statCell(
                          loc.t('pubProfileStatListings'),
                          listingCount,
                        ),
                      ),
                      _divider(),
                      Expanded(
                        child: GestureDetector(
                          key: const Key('pub_profile_stat_takipci'),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FollowListScreen(
                                userId: userId,
                                type: FollowListType.followers,
                                title: loc.t('publicProfileFollowers'),
                              ),
                            ),
                          ),
                          child: _statCell(
                            loc.t('pubProfileStatFollowers'),
                            followerCount,
                          ),
                        ),
                      ),
                      _divider(),
                      Expanded(
                        child: GestureDetector(
                          key: const Key('pub_profile_stat_takip'),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FollowListScreen(
                                userId: userId,
                                type: FollowListType.following,
                                title: loc.t('publicProfileFollowing'),
                              ),
                            ),
                          ),
                          child: _statCell(
                            loc.t('pubProfileStatFollowing'),
                            followingCount,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Action buttons
                if (_isOwnProfile) ...[
                  _actionButton(
                    key: const Key('pub_profile_btn_profil_duzenle'),
                    label: loc.t('publicProfileEditProfile'),
                    icon: Icons.edit_outlined,
                    primary: false,
                    onPressed: () => TeqSnackBar.show(message: loc.t('pubProfileEditComingSoon'),
                      type: TeqSnackBarType.info,
                    ),
                  ),
                ] else if (userId != 0) ...[
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      // ── İşlemler ──────────────────────────────────────
                      PopupMenuButton<String>(
                        key: const Key('pub_profile_btn_islemler'),
                        tooltip: 'İşlemler',
                        position: PopupMenuPosition.under,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (value) async {
                          final args = PublicProfileArgs(username: widget.username, userId: widget.userId);
                          switch (value) {
                            case 'rate':
                              _showRatingForm();
                            case 'block':
                              try {
                                await ref.read(publicProfileProvider(args).notifier).toggleBlock();
                              } catch (_) {
                                final loc = ref.read(localizationProvider);
                                TeqSnackBar.show(message: loc.t('pubProfileActionFailed'), type: TeqSnackBarType.error);
                              }
                          }
                        },
                        itemBuilder: (_) => [
                          if (_followStatus == 'accepted')
                            PopupMenuItem(
                              value: 'rate',
                              child: Row(
                                children: [
                                  Icon(
                                    hasMyRating
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    hasMyRating
                                        ? loc.t('pubProfileUpdateRating')
                                        : loc.t('pubProfileGiveRating'),
                                  ),
                                ],
                              ),
                            ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'block',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.block_outlined,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _isBlocked
                                      ? loc.t('pubProfileUnblock')
                                      : loc.t('pubProfileBlock'),
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ref.read(localizationProvider).t('titleActions'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: AppColors.textPrimary(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // ── Takip Et / Takip Ediliyor ──────────────────────
                      GestureDetector(
                        onTap: _followLoading ? null : () {
                           final args = PublicProfileArgs(username: widget.username, userId: widget.userId);
                           ref.read(publicProfileProvider(args).notifier).toggleFollow();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          decoration: BoxDecoration(
                            color: _followStatus != 'none'
                                ? AppColors.surfaceVariant(context)
                                : const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _followLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _followStatus == 'accepted'
                                          ? Icons.person_remove_outlined
                                          : _followStatus == 'pending'
                                              ? Icons.access_time
                                              : Icons.person_add_outlined,
                                      size: 18,
                                      color: _followStatus != 'none'
                                          ? AppColors.textPrimary(context)
                                          : Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _followStatus == 'accepted'
                                          ? loc.t('pubProfileFollowingLabel')
                                          : _followStatus == 'pending'
                                              ? loc.t('requested')
                                              : loc.t('pubProfileFollowLabel'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _followStatus != 'none'
                                            ? AppColors.textPrimary(context)
                                            : Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    loc.t('pubProfileListingsCount', {'count': _listings.length.toString()}),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),

        // ── Arama & Kategori filtresi ──
        if (_isPrivate && _followStatus != 'accepted' && !_isOwnProfile)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 48,
                      color: AppColors.textTertiary(context),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      loc.t('thisAccountIsPrivate'),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.t('thisAccountIsPrivateDesc'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          if (!_loading || _listings.isNotEmpty)
            SliverToBoxAdapter(
              child: TeqFilterBar(
                filter: _filter,
                onChanged: (f) {
                  final args = PublicProfileArgs(username: widget.username, userId: widget.userId);
                  ref.read(publicProfileProvider(args).notifier).updateFilter(f);
                },
                showSubcategory: true,
                showCity: false,
                showCondition: false,
                showSort: false,
                showPriceRange: false,
              ),
            ),

        // Listings grid
        if (_listings.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  loc.t('lblNoListingsYet'),
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          )
        else if (_filteredListings.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 48,
                      color: Color(0xFFD1D5DB),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Sonuç bulunamadı',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate((ctx, i) {
                final listing = Map<String, dynamic>.from(_filteredListings[i]);
                final imgs = listing['image_urls'] as List? ?? [];
                final raw = imgs.isNotEmpty
                    ? imgs[0] as String
                    : listing['image_url'] as String?;
                final photo = raw != null ? imgUrl(raw) : null;
                final price = listing['price'];
                final priceStr = price != null
                    ? () {
                        final s = (price as num).toInt().toString();
                        final buf = StringBuffer();
                        for (int j = 0; j < s.length; j++) {
                          if (j > 0 && (s.length - j) % 3 == 0) buf.write('.');
                          buf.write(s[j]);
                        }
                        return '${buf.toString()} ₺';
                      }()
                    : '';
                return GestureDetector(
                  key: Key('pub_profile_listing_${listing['id']}'),
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => ListingDetailScreen(listing: listing),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      photo != null
                          ? CachedNetworkImage(
                              imageUrl: photo,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              errorWidget: (c, _, _) => Container(
                                color: AppColors.surfaceVariant(c),
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 28,
                                  color: AppColors.border(c),
                                ),
                              ),
                            )
                          : Builder(
                              builder: (c) => Container(
                                color: AppColors.surfaceVariant(c),
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 28,
                                  color: AppColors.border(c),
                                ),
                              ),
                            ),
                      if (priceStr.isNotEmpty)
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
                              priceStr,
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
                    ],
                  ),
                );
              }, childCount: _filteredListings.length),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAvatar(String fullName, String initial) {
    final rawImg = _user?['profile_image_url'] as String?;
    final isLive = (_user?['is_live'] as bool?) ?? false;
    final streamId = _user?['active_stream_id'] as int?;
    final isPremium = (_user?['is_premium'] as bool?) ?? false;

    Widget avatarWidget = CircleAvatar(
      radius: 44,
      backgroundColor: kPrimary.withValues(alpha: 0.15),
      backgroundImage: rawImg != null ? NetworkImage(imgUrl(rawImg)) : null,
      child: rawImg == null
          ? Text(
              initial,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: kPrimary,
              ),
            )
          : null,
    );

    if (isLive && streamId != null) {
      avatarWidget = _LiveAvatarRing(
        onTap: () => _goToLiveStream(streamId),
        child: avatarWidget,
      );
    }

    if (!isPremium) return avatarWidget;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWidget,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
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
    );
  }

  void _goToLiveStream(int streamId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SwipeLiveScreen.single(streamId: streamId),
      ),
    );
  }

  Widget _buildRatingBadge(bool hasRating, dynamic avgRaw) {
    final loc = ref.read(localizationProvider);
    if (!hasRating) {
      return Text(
        loc.t('pubProfileNoReview'),
        style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
      );
    }
    final avg = (avgRaw as num).toDouble();
    final count = _ratingSummary!['count'] as int;
    final filled = avg.round().clamp(0, 5);

    return GestureDetector(
      key: const Key('pub_profile_btn_rating_badge'),
      onTap: _showRatingsList,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border(context), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${'★' * filled}${'☆' * (5 - filled)}',
              style: const TextStyle(
                color: _starColor,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              avg.toStringAsFixed(1),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 5),
            Text(
              '($count)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.textTertiary(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String label, dynamic count) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
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
      ),
    ),
  );

  Widget _divider() => Builder(
    builder: (context) =>
        Container(width: 1, height: 36, color: AppColors.border(context)),
  );

  Widget _actionButton({
    Key? key,
    required String label,
    required IconData icon,
    required bool primary,
    bool danger = false,
    VoidCallback? onPressed,
  }) {
    return Builder(
      builder: (context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          key: key,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary
                ? kPrimary
                : danger
                ? const Color(0xFFFEF2F2)
                : AppColors.surfaceVariant(context),
            foregroundColor: primary
                ? Colors.white
                : danger
                ? const Color(0xFFEF4444)
                : AppColors.textPrimary(context),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

// ── Rating form bottom sheet ─────────────────────────────────────────────────

class _RatingFormSheet extends ConsumerStatefulWidget {
  final int userId;
  final int? existingScore;
  final String? existingComment;
  final Function(int score, String comment) onSaved;

  const _RatingFormSheet({
    required this.userId,
    this.existingScore,
    this.existingComment,
    required this.onSaved,
  });

  @override
  ConsumerState<_RatingFormSheet> createState() => _RatingFormSheetState();
}

class _RatingFormSheetState extends ConsumerState<_RatingFormSheet> {
  int _selected = 0;
  bool _saving = false;
  late final TextEditingController _commentCtrl;

  List<String> _getLabels(BuildContext context) {
    final loc = ref.read(localizationProvider);
    return [
      '',
      loc.t('ratingVeryBad'),
      loc.t('ratingBad'),
      loc.t('ratingMedium'),
      loc.t('ratingGood'),
      loc.t('ratingExcellent'),
    ];
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.existingScore ?? 0;
    _commentCtrl = TextEditingController(text: widget.existingComment ?? '');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected == 0) return;
    setState(() => _saving = true);
    try {
      final comment = _commentCtrl.text.trim();
      widget.onSaved(_selected, comment);
    } catch (_) {
      if (mounted) {
        final loc = ref.read(localizationProvider);
        TeqSnackBar.show(message: loc.t('ratingSaveFailed'), type: TeqSnackBarType.error);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final labels = _getLabels(context);
    final isUpdate = widget.existingScore != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 0),
            child: Text(
              isUpdate ? loc.t('pubProfileUpdateRating') : loc.t('pubProfileGiveRating'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 22),

          // Star picker
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final v = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _selected = v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    v <= _selected
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _starColor,
                    size: 46,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            _selected > 0 ? labels[_selected] : loc.t('ratingSelectStar'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: _selected > 0 ? FontWeight.w600 : FontWeight.normal,
              color: _selected > 0
                  ? _starColor
                  : AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 18),

          // Comment field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TeqTextField(
              controller: _commentCtrl,
              maxLines: 3,
              maxLength: 500,
              hintText: loc.t('ratingCommentHint'),
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 28),
            child: Row(
              children: [
                Expanded(
                  child: TeqButton.outline(
                    onPressed: () => Navigator.pop(context),
                    text: loc.t('btnCancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TeqButton(
                    onPressed: (_selected == 0 || _saving) ? null : _save,
                    text: isUpdate ? loc.t('btnUpdate') : loc.t('btnSave'),
                    isLoading: _saving,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ratings list bottom sheet ────────────────────────────────────────────────

class _RatingsListSheet extends ConsumerWidget {
  final int userId;
  final Map<String, dynamic>? summary;

  const _RatingsListSheet({
    required this.userId,
    required this.summary,
  });

  String _formatDate(BuildContext context, WidgetRef ref, String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return DateFormat.yMMMd(
        ref.read(localizationProvider).lang,
      ).format(d);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final avgRaw = summary?['average'];
    final count = summary?['count'] as int? ?? 0;
    final avg = avgRaw != null ? (avgRaw as num).toDouble() : null;
    final filled = avg != null ? avg.round().clamp(0, 5) : 0;
    
    final ratingsAsync = ref.watch(ratingsListProvider(RatingsListArgs(userId)));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 14),
            child: Text(
              loc.t('ratingReviews'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),

          // Summary bar
          if (avg != null) ...[
            Container(
              margin: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text(
                    avg.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: _starColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${'★' * filled}${'☆' * (5 - filled)}',
                        style: const TextStyle(
                          color: _starColor,
                          fontSize: 20,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loc.t('ratingCount', {'count': count.toString()}),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          Divider(height: 1, color: AppColors.divider(context)),

          // Ratings list
          Expanded(
            child: ratingsAsync.when(
              data: (ratings) {
                if (ratings.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        loc.t('pubProfileNoReview'),
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  controller: controller,
                  itemCount: ratings.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: AppColors.divider(context)),
                  itemBuilder: (_, i) {
                    final r = ratings[i] as Map<String, dynamic>;
                    return _PublicRatingItem(
                      key: ValueKey(r['id']),
                      rating: r,
                      formatDate: (iso) => _formatDate(context, ref, iso),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
              error: (e, _) => Center(child: Text(loc.t('errorGenericRetry'))),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Public Rating Item ───────────────────────────────────────────────────────

class _PublicRatingItem extends StatefulWidget {
  final Map<String, dynamic> rating;
  final String Function(String) formatDate;

  const _PublicRatingItem({
    super.key,
    required this.rating,
    required this.formatDate,
  });

  @override
  State<_PublicRatingItem> createState() => _PublicRatingItemState();
}

class _PublicRatingItemState extends State<_PublicRatingItem> {
  bool _historyExpanded = false;

  void _goToRaterProfile() {
    final rater = widget.rating['rater'] as Map<String, dynamic>?;
    final username = rater?['username'] as String?;
    if (username == null || username.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(username: username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rating;
    final rater = r['rater'] as Map<String, dynamic>;
    final raterName = (rater['full_name'] as String?) ??
        (rater['username'] as String?) ??
        '?';
    final raterInitial =
        raterName.isNotEmpty ? raterName[0].toUpperCase() : '?';
    final raterImg = rater['profile_image_url'] as String?;
    final score = r['score'] as int;
    final comment = r['comment'] as String?;
    final reply = r['reply'] as String?;
    final history =
        (r['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final hasHistory = history.isNotEmpty;
    final hasReply = reply != null && reply.isNotEmpty;
    final date = (r['updated_at'] as String?) ?? (r['created_at'] as String?);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Rater header (tappable) ──────────────────────────────────
          GestureDetector(
            onTap: _goToRaterProfile,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: kPrimary.withValues(alpha: 0.12),
                  backgroundImage:
                      raterImg != null ? NetworkImage(imgUrl(raterImg)) : null,
                  child: raterImg == null
                      ? Text(
                          raterInitial,
                          style: const TextStyle(
                            color: kPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              raterName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${'★' * score}${'☆' * (5 - score)}',
                            style: const TextStyle(
                              color: _starColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      if (date != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.formatDate(date),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Yorum ────────────────────────────────────────────────────
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            ExpandableComment(text: comment),
          ],

          // ── Yanıt ────────────────────────────────────────────────────
          if (hasReply) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.reply,
                      size: 13,
                      color: AppColors.textTertiary(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      reply,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Geçmiş ───────────────────────────────────────────────────
          if (hasHistory) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () =>
                  setState(() => _historyExpanded = !_historyExpanded),
              child: Row(
                children: [
                  Icon(Icons.history,
                      size: 13,
                      color: AppColors.textTertiary(context)),
                  const SizedBox(width: 4),
                  Text(
                    'Düzenlendi (${history.length}x)',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _historyExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                    color: AppColors.textTertiary(context),
                  ),
                ],
              ),
            ),
            if (_historyExpanded) ...[
              const SizedBox(height: 6),
              ...history.reversed.map((h) {
                final hScore = h['score'] as int? ?? 0;
                final hComment = h['comment'] as String?;
                final hDate = widget.formatDate(
                    h['changed_at'] as String? ?? '');
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${'★' * hScore}${'☆' * (5 - hScore)}',
                              style: const TextStyle(
                                color: _starColor,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              hDate,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                          ],
                        ),
                        if (hComment != null && hComment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            hComment,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Canlı Yayın Halka Widget'ı ──────────────────────────────────────────────

class _LiveAvatarRing extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _LiveAvatarRing({required this.child, required this.onTap});

  @override
  ConsumerState<_LiveAvatarRing> createState() => _LiveAvatarRingState();
}

class _LiveAvatarRingState extends ConsumerState<_LiveAvatarRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFFDD2A7B,
                ).withValues(alpha: 0.15 + 0.35 * _glow.value),
                blurRadius: 8 + 14 * _glow.value,
                spreadRadius: 1 + 3 * _glow.value,
              ),
              BoxShadow(
                color: const Color(
                  0xFFF58529,
                ).withValues(alpha: 0.1 + 0.2 * _glow.value),
                blurRadius: 12 + 16 * _glow.value,
                spreadRadius: 0 + 2 * _glow.value,
              ),
            ],
          ),
          child: child,
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Gradient ring + beyaz boşluk + avatar
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Color(0xFFF58529),
                    Color(0xFFFEDA77),
                    Color(0xFFDD2A7B),
                    Color(0xFF8134AF),
                    Color(0xFF515BD4),
                    Color(0xFFF58529),
                  ],
                ),
              ),
              child: Builder(
                builder: (ctx) => Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bg(ctx),
                  ),
                  child: widget.child,
                ),
              ),
            ),

            // CANLI rozeti
            Positioned(
              bottom: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  '● ${ref.read(localizationProvider).t('liveBadgeLabel')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialLinksRow extends StatelessWidget {
  final Map<String, dynamic>? user;
  final int? userId;

  const _SocialLinksRow({required this.user, required this.userId});

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
    _SocialPlatform(
      'website_url',
      FontAwesomeIcons.globe,
      Color(0xFF0EA5E9),
      'website',
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
      spacing: 8, // 10 -> 8
      runSpacing: 8, // 10 -> 8
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
              width: 34, // 38 -> 34
              height: 34, // 38 -> 34
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
                    ? FaIcon(p.faIcon!, color: iconColor, size: 15) // 16 -> 15
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

class _ProfileBadge extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final String hint;

  const _ProfileBadge({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.hint,
  });

  void _showInfo(BuildContext context) {
    TeqDialog.show(
      context: context,
      title: title,
      message: hint,
      primaryButtonText: 'Tamam',
      onPrimaryPressed: () => Navigator.pop(context),
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
