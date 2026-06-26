import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/stream.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';
import 'public_profile_screen.dart';
import 'listing_detail_screen.dart';
import 'live/swipe_live_screen.dart';
import '../l10n/app_localizations.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _searchToken = 0; // her yeni arama için artar; eski yanıtlar görmezden gelinir

  List<Map<String, dynamic>> _userResults = [];
  List<Map<String, dynamic>> _listingResults = [];
  List<StreamOut> _streamResults = [];
  bool _isSemanticSearch = false;
  bool _showAllUsers = false;
  bool _searching = false;
  bool _hasQuery = false;
  bool _alertCreating = false;

  // Explore data
  // Sana Özel (for-you, personalized)
  List<dynamic> _exploreListings = [];
  // En Son İlanlar (recent, /api/listings)
  List<dynamic> _recentListings = [];
  List<StreamOut> _exploreStreams = [];
  bool _exploreLoading = true;
  bool _isLoggedIn = false;
  int _forYouPage = 0;
  bool _forYouExhausted = false;
  bool _forYouLoadingMore = false;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _scrollCtrl.addListener(_onScroll);
    _loadExplore();
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _debounce?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAlertSheet(BuildContext context) async {
    final query = _controller.text.trim();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Arama Alarmı', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('"$query" için yeni ilan eklendiğinde bildirim al.', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('İptal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Alarm Oluştur'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _alertCreating = true);
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/search-alerts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'query': query}),
      );
      if (mounted) {
        if (resp.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arama alarmı oluşturuldu ✓')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alarm oluşturulamadı, tekrar dene')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarm oluşturulamadı, tekrar dene')),
        );
      }
    } finally {
      if (mounted) setState(() => _alertCreating = false);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMoreForYou();
    }
  }

  void _onQueryChanged() {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _hasQuery = false;
        _userResults = [];
        _listingResults = [];
        _streamResults = [];
        _isSemanticSearch = false;
        _showAllUsers = false;
      });
      return;
    }
    setState(() => _hasQuery = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(q));
  }

  /// SWR paralel yükleme: yayınlar + kişisel feed + son ilanlar aynı anda başlar.
  /// Her akış Hive'dan anında veri yayarsa _exploreLoading hemen kapanır.
  /// [bypassCache]: pull-to-refresh senaryosunda cache READ atlanır.
  Future<void> _loadExplore({bool bypassCache = false}) async {
    if (!mounted) return;
    setState(() {
      _exploreLoading = true;
      _forYouPage = 0;
      _forYouExhausted = false;
    });

    final token = await StorageService.getToken();
    final loggedIn = token != null;
    if (mounted) setState(() => _isLoggedIn = loggedIn);

    // İlk veri geldiğinde loading'i kapat (cache varsa anlık)
    bool _firstDataArrived = false;
    void _maybeStopLoading() {
      if (!_firstDataArrived && mounted) {
        _firstDataArrived = true;
        setState(() => _exploreLoading = false);
      }
    }

    // ── Aktif yayınlar (1 dk cache) ────────────────────────────────────────
    _loadExploreStreams(bypassCache, _maybeStopLoading);

    // ── Kişisel feed (giriş: 1 saat cache | misafir: 5 dk) ────────────────
    _loadExploreForYou(loggedIn: loggedIn, bypassCache: bypassCache, onData: _maybeStopLoading);

    // ── En son ilanlar (5 dk cache, yalnızca giriş yapılmışsa ayrı çek) ───
    if (loggedIn) {
      _loadExploreRecent(bypassCache: bypassCache, onData: _maybeStopLoading);
    } else {
      // Misafirde for-you zaten son ilanları gösterir
      _maybeStopLoading();
    }
  }

  void _loadExploreStreams(bool bypassCache, VoidCallback onData) {
    StreamService.getActiveStreamsStream(bypassCache: bypassCache).listen(
      (streams) {
        if (mounted) setState(() => _exploreStreams = streams.take(4).toList());
        onData();
      },
      onError: (_) => onData(),
    );
  }

  void _loadExploreForYou({
    required bool loggedIn,
    required bool bypassCache,
    required VoidCallback onData,
  }) {
    final url = loggedIn ? '$kBaseUrl/feed/for-you?page=0' : '$kBaseUrl/listings';
    final cacheKey = loggedIn ? 'explore_for_you' : StorageService.cacheFeed;
    final ttl = loggedIn ? const Duration(hours: 1) : const Duration(minutes: 5);

    ApiService.get<List<dynamic>>(
      url: url,
      cacheKey: cacheKey,
      cacheTtl: ttl,
      bypassCache: bypassCache,
      fromJson: (raw) => raw as List,
    ).listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _exploreListings = data;
          if (loggedIn) {
            _forYouPage = 1;
            _forYouExhausted = data.length < 20;
          }
        });
        onData();
      },
      onError: (_) => onData(),
    );
  }

  void _loadExploreRecent({required bool bypassCache, required VoidCallback onData}) {
    ApiService.get<List<dynamic>>(
      url: '$kBaseUrl/listings',
      cacheKey: StorageService.cacheFeed,
      cacheTtl: const Duration(minutes: 5),
      bypassCache: bypassCache,
      fromJson: (raw) => raw as List,
    ).listen(
      (recent) {
        if (mounted) setState(() => _recentListings = recent.take(12).toList());
        onData();
      },
      onError: (_) => onData(),
    );
  }

  Future<void> _loadMoreForYou() async {
    if (!_isLoggedIn || _forYouExhausted || _forYouLoadingMore || _hasQuery) return;
    setState(() => _forYouLoadingMore = true);
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/feed/for-you?page=$_forYouPage'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        setState(() {
          _exploreListings.addAll(data);
          _forYouPage++;
          if (data.length < 20) _forYouExhausted = true;
        });
      } else {
        setState(() => _forYouExhausted = true);
      }
    } catch (_) {
      if (mounted) setState(() => _forYouExhausted = false);
    } finally {
      if (mounted) setState(() => _forYouLoadingMore = false);
    }
  }

  void _trackInteraction(int itemId) {
    StorageService.getToken().then((token) {
      if (token == null) return;
      http.post(
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
      ).catchError((_) => http.Response('', 200));
    });
  }

  // /search/all → kullanıcı + ilan + canlı yayın; tek çağrı; 500ms debounce.
  Future<void> _search(String q) async {
    final myToken = ++_searchToken; // bu request'in token'ı
    setState(() => _searching = true);
    try {
      final token = await StorageService.getToken();
      final headers = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
      final resp = await http.get(
        Uri.parse('$kBaseUrl/search/all').replace(queryParameters: {'q': q}),
        headers: headers,
      );
      if (!mounted || myToken != _searchToken) return; // eski yanıt, görmezden gel
      if (resp.statusCode != 200) {
        setState(() => _searching = false);
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final listingResults = (data['listings'] as List).cast<Map<String, dynamic>>();
      final resultCount = listingResults.length +
          (data['users'] as List).length +
          (data['streams'] as List).length;
      setState(() {
        _userResults = (data['users'] as List).cast<Map<String, dynamic>>();
        _listingResults = listingResults;
        _streamResults = (data['streams'] as List)
            .map((s) => StreamOut.fromJson(s as Map<String, dynamic>))
            .toList();
        _isSemanticSearch = data['search_type'] == 'semantic';
        _showAllUsers = false;
        _searching = false;
      });
      AnalyticsService.trackSearch(query: q, resultCount: resultCount);
    } catch (_) {
      if (mounted && myToken == _searchToken) setState(() => _searching = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // ── Arama kutusu ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('search_input_arama'),
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Yapay zeka ile arayın (Örn: Vintage bir saat)',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _hasQuery
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: _alertCreating
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.notifications_none, size: 20),
                              tooltip: 'Arama Alarmı Oluştur',
                              onPressed: _alertCreating ? null : () => _showAlertSheet(context),
                            ),
                            IconButton(
                              key: const Key('search_btn_arama_temizle'),
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: _controller.clear,
                            ),
                          ],
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.inputFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            // ── İçerik ───────────────────────────────────────────────
            Expanded(
              child: _hasQuery ? _buildSearchResults(l) : _buildExplore(l),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(AppLocalizations l) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    final hasUsers = _userResults.isNotEmpty;
    final hasListings = _listingResults.isNotEmpty;
    final hasStreams = _streamResults.isNotEmpty;

    if (!hasUsers && !hasListings && !hasStreams) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_outlined, size: 56, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('Sonuç bulunamadı',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
          ],
        ),
      );
    }

    // Max 5 kullanıcı göster; fazlası için "Hepsini gör" satırı
    final visibleUsers =
        _showAllUsers ? _userResults : _userResults.take(5).toList();
    final hasMoreUsers = !_showAllUsers && _userResults.length > 5;

    return CustomScrollView(
      slivers: [
        // ── Akıllı Sonuçlar rozeti ──────────────────────────────────
        if (_isSemanticSearch)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kPrimary.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          'Akıllı Sonuçlar',
                          style: TextStyle(
                              color: kPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
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
              label: 'Kullanıcılar',
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final u = visibleUsers[i];
                final imgRaw = u['profile_image_url'] as String?;
                final img =
                    imgRaw != null && imgRaw.isNotEmpty ? imgUrl(imgRaw) : null;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: kPrimary,
                        backgroundImage:
                            img != null ? NetworkImage(img) : null,
                        child: img == null
                            ? Text(
                                (u['full_name'] as String? ?? '?')[0]
                                    .toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              )
                            : null,
                      ),
                      title: Text(
                        u['full_name'] as String? ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        '@${u['username']}',
                        style: const TextStyle(color: kPrimary, fontSize: 12),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PublicProfileScreen(
                              username: u['username'] as String),
                        ),
                      ),
                    ),
                    if (i < visibleUsers.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                );
              },
              childCount: visibleUsers.length,
            ),
          ),
          // "Tüm hesapları gör" satırı
          if (hasMoreUsers)
            SliverToBoxAdapter(
              child: InkWell(
                onTap: () => setState(() => _showAllUsers = true),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(72, 4, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Tüm hesapları gör (${_userResults.length})',
                        style: TextStyle(
                            color: kPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded,
                          color: kPrimary, size: 18),
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
              icon: _isSemanticSearch
                  ? Icons.auto_awesome_rounded
                  : Icons.grid_view_rounded,
              label: 'İlanlar',
              iconColor: _isSemanticSearch ? kPrimary : null,
            ),
          ),
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
                (ctx, i) {
                  final listing = _listingResults[i];
                  return _ListingTile(
                    listing: listing,
                    onTap: () {
                      final id = listing['id'] as int?;
                      if (id != null && _isLoggedIn) _trackInteraction(id);
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
                childCount: _listingResults.length,
              ),
            ),
          ),
        ],

        // ── 3. Canlı Yayınlar ────────────────────────────────────────
        if (hasStreams) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              icon: Icons.fiber_manual_record,
              label: 'Canlı Yayınlar',
              iconColor: Colors.red,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 168,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _streamResults.length,
                itemBuilder: (_, i) => _StreamCard(
                  stream: _streamResults[i],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SwipeLiveScreen(
                        streams: _streamResults,
                        initialIndex: i,
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

  Widget _buildExplore(AppLocalizations l) {
    if (_exploreLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _loadExplore,
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Canlı Yayınlar ────────────────────────────────────────
          if (_exploreStreams.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
                    const SizedBox(width: 6),
                    Text(
                      l.searchLiveStreams,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
                  itemCount: _exploreStreams.length,
                  itemBuilder: (_, i) => _StreamCard(
                    stream: _exploreStreams[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SwipeLiveScreen(
                          streams: _exploreStreams,
                          initialIndex: i,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          // ── Sana Özel / Son İlanlar ──────────────────────────────
          if (_exploreListings.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    if (_isLoggedIn)
                      const Icon(Icons.auto_awesome, color: kPrimary, size: 16),
                    if (_isLoggedIn) const SizedBox(width: 6),
                    Text(
                      _isLoggedIn ? 'Sana Özel' : l.homeRecentListings,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
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
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final listing =
                        _exploreListings[i] as Map<String, dynamic>;
                    return _ListingTile(
                      listing: listing,
                      onTap: () {
                        final id = listing['id'] as int?;
                        if (id != null && _isLoggedIn) _trackInteraction(id);
                        Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => ListingDetailScreen(listing: listing),
                          ),
                        );
                      },
                    );
                  },
                  childCount: _exploreListings.length,
                ),
              ),
            ),
            if (_forYouLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2),
                  ),
                ),
              ),
          ],

          // ── En Son İlanlar (login, /api/listings) ─────────────────
          if (_isLoggedIn && _recentListings.isNotEmpty) ...[
            const SliverToBoxAdapter(child: Divider(height: 1, indent: 16, endIndent: 16)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(l.homeRecentListings,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final listing = _recentListings[i] as Map<String, dynamic>;
                    return _ListingTile(
                      listing: listing,
                      onTap: () => Navigator.push(ctx, MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listing: listing),
                      )),
                    );
                  },
                  childCount: _recentListings.length,
                ),
              ),
            ),
          ],

          // ── Boş durum ────────────────────────────────────────────
          if (_exploreStreams.isEmpty && _exploreListings.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isLoggedIn
                          ? Icons.auto_awesome_outlined
                          : Icons.explore_outlined,
                      size: 56,
                      color: const Color(0xFFD1D5DB),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isLoggedIn
                          ? 'Birkaç ilan incele,\nSana Özel içerik hazırlanıyor!'
                          : l.searchNoContent,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Bölüm başlığı ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const _SectionHeader({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor ?? const Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF374151)),
          ),
        ],
      ),
    );
  }
}

// ── Yatay stream kartı ──────────────────────────────────────────────────────
class _StreamCard extends StatelessWidget {
  final StreamOut stream;
  final VoidCallback onTap;

  const _StreamCard({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasThumbnail =
        stream.thumbnailUrl != null && stream.thumbnailUrl!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
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
                imageUrl: imgUrl(stream.thumbnailUrl),
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                errorWidget: (_, __, ___) => _gradient(),
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
            // İsim ve başlık
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
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
                      style: const TextStyle(
                        color: kPrimary,
                        fontSize: 10,
                      ),
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Icon(Icons.videocam_rounded, color: Colors.white30, size: 36),
        ),
      );
}

// ── İlan grid tile ──────────────────────────────────────────────────────────
class _ListingTile extends StatelessWidget {
  final Map<String, dynamic> listing;
  final VoidCallback onTap;

  const _ListingTile({required this.listing, required this.onTap});

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
    final raw = imgs.isNotEmpty
        ? imgs[0] as String
        : (listing['image_url'] as String?);
    final photo = raw != null ? imgUrl(raw) : null;
    final price = _fmt(listing['price']);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          photo != null
              ? CachedNetworkImage(
                  imageUrl: photo,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorWidget: (_, __, ___) => _placeholder(context),
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
