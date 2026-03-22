import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/stream.dart';
import '../services/storage_service.dart';
import '../services/stream_service.dart';
import 'public_profile_screen.dart';
import 'listing_detail_screen.dart';
import 'live/swipe_live_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _userResults = [];
  bool _searching = false;
  bool _hasQuery = false;

  // Explore data
  List<dynamic> _exploreListings = [];
  List<StreamOut> _exploreStreams = [];
  bool _exploreLoading = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _loadExplore();
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _hasQuery = false;
        _userResults = [];
      });
      return;
    }
    setState(() => _hasQuery = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _searchUsers(q));
  }

  Future<void> _loadExplore() async {
    setState(() => _exploreLoading = true);
    try {
      final token = await StorageService.getToken();
      final headers = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
      final listingsFuture = http.get(Uri.parse('$kBaseUrl/listings'), headers: headers);
      final streamsFuture = StreamService.getActiveStreams();

      final listingsResp = await listingsFuture;
      final streams = await streamsFuture;

      if (!mounted) return;
      setState(() {
        if (listingsResp.statusCode == 200) {
          _exploreListings = (jsonDecode(listingsResp.body) as List).take(12).toList();
        }
        _exploreStreams = streams.take(4).toList();
        _exploreLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _exploreLoading = false);
    }
  }

  Future<void> _searchUsers(String q) async {
    setState(() => _searching = true);
    try {
      final token = await StorageService.getToken();
      final headers = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
      final resp = await http.get(
        Uri.parse('$kBaseUrl/search/users').replace(queryParameters: {'q': q}),
        headers: headers,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        setState(() {
          _userResults = data.cast<Map<String, dynamic>>();
          _searching = false;
        });
      } else {
        setState(() => _searching = false);
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  hintText: 'Kullanıcı ara...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _hasQuery
                      ? IconButton(
                          key: const Key('search_btn_arama_temizle'),
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: _controller.clear,
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
              child: _hasQuery ? _buildUserResults() : _buildExplore(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserResults() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    if (_userResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_outlined, size: 56, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text('Kullanıcı bulunamadı', style: TextStyle(color: Color(0xFF6B7280))),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _userResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final u = _userResults[i];
        final imgRaw = u['profile_image_url'] as String?;
        final img = imgRaw != null && imgRaw.isNotEmpty ? imgUrl(imgRaw) : null;
        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: kPrimary,
            backgroundImage: img != null ? NetworkImage(img) : null,
            child: img == null
                ? Text(
                    (u['full_name'] as String? ?? '?')[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  )
                : null,
          ),
          title: Text(
            u['full_name'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            '@${u['username']}',
            style: const TextStyle(color: kPrimary, fontSize: 12),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PublicProfileScreen(username: u['username'] as String),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExplore() {
    if (_exploreLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _loadExplore,
      child: CustomScrollView(
        slivers: [
          // ── Canlı Yayınlar ────────────────────────────────────────
          if (_exploreStreams.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
                    SizedBox(width: 6),
                    Text(
                      'Canlı Yayınlar',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
          // ── Son İlanlar ──────────────────────────────────────────
          if (_exploreListings.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Son İlanlar',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
                      onTap: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => ListingDetailScreen(listing: listing),
                        ),
                      ),
                    );
                  },
                  childCount: _exploreListings.length,
                ),
              ),
            ),
          ],
          // ── Boş durum ────────────────────────────────────────────
          if (_exploreStreams.isEmpty && _exploreListings.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.explore_outlined, size: 56,
                        color: Color(0xFFD1D5DB)),
                    SizedBox(height: 12),
                    Text('Henüz içerik yok',
                        style: TextStyle(color: Color(0xFF6B7280))),
                  ],
                ),
              ),
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
                child: const Text(
                  'CANLI',
                  style: TextStyle(
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
