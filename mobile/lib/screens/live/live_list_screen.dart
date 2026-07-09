import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../core/app_exception.dart';
import '../../models/stream.dart';
import '../../services/connectivity_service.dart';
import '../../services/storage_service.dart';
import '../../services/stream_service.dart';
import '../../services/ws_service.dart';
import '../../services/stream_connection_manager.dart';
import '../../utils/start_stream_helper.dart';
import '../../providers/story_provider.dart';
import '../../widgets/live/story_tray.dart';
import '../../widgets/network_error_widget.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/stale_data_banner.dart';
import 'swipe_live_screen.dart';
import '../public_profile_screen.dart';
import '../../l10n/app_localizations.dart';

class LiveListScreen extends ConsumerStatefulWidget {
  const LiveListScreen({super.key});

  @override
  ConsumerState<LiveListScreen> createState() => LiveListScreenState();
}

const _kCatLabels = {
  'sohbet': '🗣 Canlı Sohbet',
  'elektronik': '📱 Elektronik',
  'giyim': '👗 Giyim',
  'ev': '🏠 Ev & Yaşam',
  'vasita': '🚗 Vasıta',
  'spor': '⚽ Spor',
  'kitap': '📚 Kitap',
  'emlak': '🏘️ Emlak',
  'diger': '📦 Diğer',
};

class LiveListScreenState extends ConsumerState<LiveListScreen> {
  List<StreamOut> _streams = []; // tüm aktif yayınlar (En Son)
  List<StreamOut> _recommended = []; // kişiselleştirilmiş (Sana Özel)
  List<Map<String, dynamic>> _suggestedStreamers = []; // önerilen yayıncılar
  bool _loading = true;
  bool _isLoggedIn = false;
  String? _selectedCategory; // null = Tümü
  String? _error;
  bool _isOffline = false;

  StreamSubscription<Map<String, dynamic>>? _wsSub;
  StreamSubscription<bool>? _connectSub;
  final _connectSvc = ConnectivityService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _wsSub = WsService.messageStream.stream.listen(_onWsMessage);

    // Anlık bağlantı durumu
    _connectSvc.isConnected.then((online) {
      if (mounted) setState(() => _isOffline = !online);
    });
    // Değişimleri dinle
    _connectSub = _connectSvc.onConnectivityChanged.listen((online) {
      if (!mounted) return;
      final wasOffline = _isOffline;
      setState(() => _isOffline = !online);
      // İnternet geri geldi → listeyi yenile
      if (online && wasOffline) _load(bypassCache: true);
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _connectSub?.cancel();
    super.dispose();
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    if (msg['type'] == 'stream_ended') {
      final streamId = msg['stream_id'];
      if (streamId is int) {
        setState(() {
          _streams.removeWhere((s) => s.id == streamId);
          _recommended.removeWhere((s) => s.id == streamId);
        });
        // Story tray'i de ağdan yenile (cache'i bypass et)
        unawaited(ref.read(storyGroupsProvider.notifier).refresh());
      }
    }
  }

  void triggerStartDialog() =>
      showStartStreamDialog(context, onStreamStarted: _load);
  void refresh({bool bypassCache = true}) => _load(bypassCache: bypassCache);

  /// [bypassCache]: pull-to-refresh ve bağlantı geri geldiğinde true.
  Future<void> _load({bool bypassCache = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);
    // refresh() → bypassCache:true ile ağdan çeker; invalidate() değil
    // çünkü invalidate, build()'daki bypassCache:false ile Hive cache'i önce
    // gösterir ve story tray anlık güncellenmez.
    unawaited(ref.read(storyGroupsProvider.notifier).refresh());
    unawaited(ref.read(myStoriesProvider.notifier).refresh());

    final token = await StorageService.getToken();
    if (mounted) setState(() => _isLoggedIn = token != null);

    // Kişisel öneriler: arka planda ağdan çek (cache gerekmez, oturum bazlı)
    if (token != null) {
      unawaited(
        StreamService.getRecommendedStreams().then((rec) {
          if (mounted) setState(() => _recommended = rec);
        }),
      );
      unawaited(
        StreamService.getSuggestedStreamers().then((streamers) {
          if (mounted) setState(() => _suggestedStreamers = streamers);
        }),
      );
    }

    // Aktif yayınlar: SWR — önce cache (anlık), sonra API (taze)
    try {
      await for (final streams in StreamService.getActiveStreamsStream(
        bypassCache: bypassCache,
      )) {
        if (!mounted) return;
        setState(() {
          _streams = streams;
          _loading = false;
          _error = null;
        });
      }
    } catch (e, st) {
      debugPrint('[LiveList] _load hatası: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'network';
      });
    }
  }

  Future<void> _showStartDialog() =>
      showStartStreamDialog(context, onStreamStarted: _load);

  Future<void> _joinStream(StreamOut stream) async {
    if (!mounted) return;
    // Çevrimdışıyken yayına girmeyi engelle
    if (_isOffline) return;

    // Erken bağlantı (Early Connection) - WebRTC handshake'i animasyon süresince başlat
    StreamConnectionManager.instance.prefetchForImmediateJoin(stream.id);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SwipeLiveScreen.fromStream(stream)),
    ).then((_) => _load(bypassCache: true));
  }

  List<String> get _categories {
    final seen = <String>{};
    return _streams.map((s) => s.category).where(seen.add).toList();
  }

  List<StreamOut> get _filtered => _selectedCategory == null
      ? _streams
      : _streams.where((s) => s.category == _selectedCategory).toList();

  // Sana Özel: kategori filtresi de uygulanır
  List<StreamOut> get _filteredRecommended => _selectedCategory == null
      ? _recommended
      : _recommended.where((s) => s.category == _selectedCategory).toList();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cats = _categories;
    final showFilter = !_loading && cats.isNotEmpty;
    final filtered = _filtered;

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
              l.liveStreamsTitle,
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
              l.liveStartStream,
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
          // ── Çevrimdışı bilgi bandı ─────────────────────────────
          const OfflineBanner(),

          // ── Video Hikayeler (Story Tray) ────────────────────────
          const StoryTray(),

          // ── Kategori filtre çubuğu ──────────────────────────────
          if (showFilter)
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
                    label: l.liveAllCategory,
                    active: _selectedCategory == null,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  ...cats.map(
                    (c) => _CategoryChip(
                      key: Key('live_list_chip_$c'),
                      label: _kCatLabels[c] ?? c,
                      active: _selectedCategory == c,
                      onTap: () => setState(() => _selectedCategory = c),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null && _streams.isNotEmpty)
            StaleDataBanner(onRetry: _load),
          // ── İçerik ──────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: kPrimary,
              onRefresh: _load,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: kPrimary),
                    )
                  : _error != null && filtered.isEmpty
                  ? NetworkErrorWidget(onRetry: _load, scrollable: true)
                  : filtered.isEmpty
                  ? const _EmptyState()
                  : _buildContent(l, filtered),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations l, List<StreamOut> filtered) {
    final rec = _filteredRecommended;
    final hasRec = _isLoggedIn && rec.isNotEmpty;
    final hasSuggestedStreamers = _isLoggedIn && _suggestedStreamers.isNotEmpty;
    final cats = _categories;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ── Önerilen Yayıncılar ────────────────────────────────
        if (hasSuggestedStreamers) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: const [
                  Icon(
                    Icons.live_tv_rounded,
                    color: Color(0xFFEF4444),
                    size: 15,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Önerilen Yayıncılar',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                itemCount: _suggestedStreamers.length,
                itemBuilder: (ctx, i) => _StreamerAvatarCard(
                  streamer: _suggestedStreamers[i],
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => PublicProfileScreen(
                        username:
                            _suggestedStreamers[i]['username'] as String? ?? '',
                        userId: _suggestedStreamers[i]['id'] as int?,
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: kPrimary, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    l.forYouStreams,
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
                    padding: const EdgeInsets.only(right: 10),
                    child: _StreamGridTile(
                      stream: rec[i],
                      onTap: () => _joinStream(rec[i]),
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                      ? '${_kCatLabels[_selectedCategory!] ?? _selectedCategory!} Yayınları'
                      : 'En Son Canlı Yayınlar',
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                  onTap: () => _joinStream(filtered[i]),
                ),
                childCount: filtered.length,
              ),
            ),
          )
        else
          ..._buildSectionedSlivers(cats, filtered),
      ],
    );
  }

  List<Widget> _buildSectionedSlivers(List<String> cats, List<StreamOut> all) {
    final groups = {
      for (var c in cats) c: all.where((s) => s.category == c).toList(),
    };
    return [
      for (final c in cats)
        if (groups[c]!.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                _kCatLabels[c] ?? c,
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
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
                  onTap: () => _joinStream(groups[c]![i]),
                ),
                childCount: groups[c]!.length,
              ),
            ),
          ),
        ],
    ];
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CategoryChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? kPrimary : const Color(0xFFD1D5DB),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
              l.liveNoStreams,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              l.liveBeFirst,
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _StreamerAvatarCard extends StatelessWidget {
  final Map<String, dynamic> streamer;
  final VoidCallback? onTap;
  const _StreamerAvatarCard({required this.streamer, this.onTap});

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.only(right: 12),
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
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
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
                        child: const Text(
                          'CANLI',
                          style: TextStyle(
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

class _AvatarInitial extends StatelessWidget {
  final String initial;
  final BuildContext context;
  const _AvatarInitial({required this.initial, required this.context});

  @override
  Widget build(BuildContext _) {
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

class _StreamGridTile extends StatelessWidget {
  final StreamOut stream;
  final VoidCallback onTap;

  const _StreamGridTile({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
                          AppLocalizations.of(context)!.liveBadgeLabel,
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
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.videocam_rounded, color: Colors.white30, size: 36),
      ),
    );
  }
}
