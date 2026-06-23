import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api.dart';
import '../../config/app_colors.dart';
import '../../services/storage_service.dart';
import '../listing_detail_screen.dart';
import '../public_profile_screen.dart';

class ForYouScreen extends StatefulWidget {
  const ForYouScreen({super.key});

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  final PageController _pageCtrl = PageController();
  final List<Map<String, dynamic>> _items = [];

  int _currentIndex = 0;
  int _apiPage = 0;
  bool _loading = false;
  bool _exhausted = false;

  // Analytics
  Timer? _dwellTimer;
  DateTime? _pageEnteredAt;
  bool _viewFired = false; // 3s sinyali bu sayfa için gönderildi mi

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Veri Yükleme ───────────────────────────────────────────────────────────

  Future<void> _loadMore() async {
    if (_loading || _exhausted) return;
    setState(() => _loading = true);
    try {
      final token = await StorageService.getToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final uri = Uri.parse('$kBaseUrl/feed/for-you?page=$_apiPage');
      final response = await http.get(uri, headers: headers);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        if (data.isEmpty) {
          setState(() => _exhausted = true);
        } else {
          setState(() {
            _items.addAll(data.cast<Map<String, dynamic>>());
            _apiPage++;
          });
          _preloadImages(_items.length - data.length, 3);
        }
      } else {
        setState(() => _exhausted = true);
      }
    } catch (_) {
      if (mounted) setState(() => _exhausted = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Ön Belleğe Alma (Pre-fetch) ────────────────────────────────────────────

  void _preloadImages(int fromIndex, int count) {
    for (var i = fromIndex; i < fromIndex + count && i < _items.length; i++) {
      final item = _items[i];
      final urls = (item['image_urls'] as List?)?.cast<String>() ?? [];
      final raw = urls.isNotEmpty ? urls[0] : item['image_url'] as String?;
      if (raw != null && raw.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(imgUrl(raw)), context);
      }
    }
  }

  // ── Sayfa Geçişi ───────────────────────────────────────────────────────────

  void _onPageChanged(int newIndex) {
    // Önceki sayfa için dwell analitik
    _flushDwell();

    setState(() {
      _currentIndex = newIndex;
      _viewFired = false;
    });
    _pageEnteredAt = DateTime.now();

    // 3 saniye timer'ı başlat
    _dwellTimer?.cancel();
    _dwellTimer = Timer(const Duration(seconds: 3), () {
      if (!_viewFired) {
        _viewFired = true;
        _trackInteraction(
          index: _currentIndex,
          interactionType: 'view',
          durationSeconds: 3.0,
        );
      }
    });

    // Sonraki 2 öğeyi ön belleğe al
    _preloadImages(newIndex + 1, 2);

    // Sona yaklaşınca daha fazla yükle
    if (newIndex >= _items.length - 3) _loadMore();
  }

  /// Sayfa değişirken gerçek dwell süresini gönderir (3s+ ise).
  void _flushDwell() {
    _dwellTimer?.cancel();
    if (_pageEnteredAt != null && !_viewFired && _currentIndex < _items.length) {
      final secs = DateTime.now().difference(_pageEnteredAt!).inMilliseconds / 1000.0;
      if (secs >= 3.0) {
        _viewFired = true;
        _trackInteraction(
          index: _currentIndex,
          interactionType: 'view',
          durationSeconds: secs,
        );
      }
    }
  }

  // ── Analytics (fire-and-forget, hata kullanıcıya gösterilmez) ─────────────

  Future<void> _trackInteraction({
    required int index,
    required String interactionType,
    double? durationSeconds,
  }) async {
    if (index >= _items.length) return;
    final item = _items[index];
    final itemId = item['id'] as int?;
    if (itemId == null) return;

    try {
      final token = await StorageService.getToken();
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
          'interaction_type': interactionType,
          if (durationSeconds != null) 'duration_seconds': durationSeconds,
        }),
      ).catchError((_) {});
    } catch (_) {}
  }

  // ── Beğeni ─────────────────────────────────────────────────────────────────

  Future<void> _toggleLike(int index) async {
    final item = _items[index];
    final itemId = item['id'] as int;
    final wasLiked = item['is_liked'] as bool? ?? false;

    setState(() {
      _items[index]['is_liked'] = !wasLiked;
      _items[index]['likes_count'] =
          ((item['likes_count'] as int? ?? 0) + (wasLiked ? -1 : 1)).clamp(0, 999999);
    });

    _trackInteraction(index: index, interactionType: 'like');

    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('$kBaseUrl/listings/$itemId/like'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _items[index]['is_liked'] = wasLiked;
          _items[index]['likes_count'] = item['likes_count'];
        });
      }
    }
  }

  // ── Navigasyon ─────────────────────────────────────────────────────────────

  void _openDetail(int index) {
    _trackInteraction(index: index, interactionType: 'click');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listing: _items[index]),
      ),
    );
  }

  void _openOffer(int index) {
    _trackInteraction(index: index, interactionType: 'offer');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listing: _items[index]),
      ),
    );
  }

  void _openProfile(int index) {
    final item = _items[index];
    final user = item['user'] as Map<String, dynamic>?;
    final username = user?['username'] as String?;
    if (username == null || username.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(username: username),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white38, size: 72),
              const SizedBox(height: 20),
              const Text(
                'Sana Özel içerik yükleniyor...',
                style: TextStyle(color: Colors.white60, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Birkaç ilan incele, algoritma öğrensin!',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
                style: FilledButton.styleFrom(backgroundColor: kPrimary),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Sana Özel',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: _items.length + (_loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return _ForYouCard(
            item: _items[index],
            onTap: () => _openDetail(index),
            onLike: () => _toggleLike(index),
            onOffer: () => _openOffer(index),
            onProfile: () => _openProfile(index),
          );
        },
      ),
    );
  }
}

// ── Kart Widget'ı ─────────────────────────────────────────────────────────────

class _ForYouCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onOffer;
  final VoidCallback onProfile;

  const _ForYouCard({
    required this.item,
    required this.onTap,
    required this.onLike,
    required this.onOffer,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final urls = (item['image_urls'] as List?)?.cast<String>() ?? [];
    final rawUrl = urls.isNotEmpty ? urls[0] : item['image_url'] as String?;
    final imageUrl = rawUrl != null && rawUrl.isNotEmpty ? imgUrl(rawUrl) : null;

    final title = item['title'] as String? ?? '';
    final price = item['price'];
    final likesCount = item['likes_count'] as int? ?? 0;
    final isLiked = item['is_liked'] as bool? ?? false;
    final user = item['user'] as Map<String, dynamic>?;
    final seller = user?['username'] as String? ?? '';
    final location = item['location'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Arka plan resmi
          imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (_, __) =>
                      Container(color: const Color(0xFF1A1A1A)),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF1A1A1A),
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.white24,
                      size: 64,
                    ),
                  ),
                )
              : Container(
                  color: const Color(0xFF1A1A1A),
                  child: const Icon(
                    Icons.photo_outlined,
                    color: Colors.white24,
                    size: 64,
                  ),
                ),

          // Alt gradient
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0x66000000),
                    Color(0xCC000000),
                  ],
                  stops: [0.0, 0.45, 0.70, 1.0],
                ),
              ),
            ),
          ),

          // Sol alt: ilan bilgisi
          Positioned(
            left: 16,
            right: 76,
            bottom: 36,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (seller.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '@$seller',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          color: Colors.white60, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        location,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ],
                if (price != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${(price as num).toStringAsFixed(0)} ₺',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Sağ: TikTok tarzı aksiyon butonları
          Positioned(
            right: 10,
            bottom: 36,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SideButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  iconColor: isLiked ? Colors.redAccent : Colors.white,
                  label: likesCount > 0 ? '$likesCount' : 'Beğen',
                  onTap: onLike,
                ),
                const SizedBox(height: 18),
                _SideButton(
                  icon: Icons.local_offer_outlined,
                  label: 'Teklif',
                  onTap: onOffer,
                ),
                const SizedBox(height: 18),
                _SideButton(
                  icon: Icons.person_outline,
                  label: 'Profil',
                  onTap: onProfile,
                ),
              ],
            ),
          ),

          // Kaydır ipucu (sadece ilk kart)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white.withOpacity(0.4),
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Yan Buton ─────────────────────────────────────────────────────────────────

class _SideButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(color: Colors.black, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }
}
