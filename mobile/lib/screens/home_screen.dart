import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/theme.dart';
import 'listing_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _listings = [];
  bool _loading = true;
  String? _error;

  static const _categories = [
    {'slug': 'elektronik', 'label': 'Elektronik', 'icon': Icons.devices_outlined},
    {'slug': 'vasita', 'label': 'Vasıta', 'icon': Icons.directions_car_outlined},
    {'slug': 'emlak', 'label': 'Emlak', 'icon': Icons.home_work_outlined},
    {'slug': 'giyim', 'label': 'Giyim', 'icon': Icons.checkroom_outlined},
    {'slug': 'spor', 'label': 'Spor', 'icon': Icons.sports_soccer_outlined},
    {'slug': 'kitap', 'label': 'Kitap', 'icon': Icons.menu_book_outlined},
    {'slug': 'ev', 'label': 'Ev & Yaşam', 'icon': Icons.home_outlined},
    {'slug': 'diger', 'label': 'Diğer', 'icon': Icons.more_horiz},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? category}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$kBaseUrl/listings${category != null ? '?category=$category' : ''}');
      final resp = await http.get(uri);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() {
          _listings = jsonDecode(resp.body) as List;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'İlanlar yüklenemedi';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Bağlantı hatası';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: const Text(
                'İlanlar',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              backgroundColor: Colors.white,
              floating: true,
              snap: true,
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kategoriler
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _categories.length,
                      itemBuilder: (context, i) {
                        final cat = _categories[i];
                        return GestureDetector(
                          onTap: () => _load(category: cat['slug'] as String),
                          child: Container(
                            width: 68,
                            margin: const EdgeInsets.only(right: 10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: kPrimaryBg,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(cat['icon'] as IconData,
                                      color: kPrimary, size: 24),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cat['label'] as String,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500),
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Son İlanlar',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: _load,
                          child: const Text('Tekrar Dene')),
                    ],
                  ),
                ),
              )
            else if (_listings.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text('Henüz ilan yok',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ListingCard(
                      listing: _listings[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ListingDetailScreen(listing: _listings[i]),
                        ),
                      ),
                    ),
                    childCount: _listings.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final Map<String, dynamic> listing;
  final VoidCallback onTap;
  const _ListingCard({required this.listing, required this.onTap});

  String _fmt(dynamic price) {
    if (price == null) return 'Fiyat Yok';
    final n = (price as num).toInt();
    final s = n.toString();
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
    final imgUrl = imgs.isNotEmpty
        ? imgs[0] as String
        : (listing['image_url'] as String?);
    final user = listing['user'] as Map<String, dynamic>?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
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
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12)),
              child: imgUrl != null
                  ? Image.network(
                      imgUrl,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _noImg(),
                    )
                  : _noImg(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing['title'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (listing['location'] != null)
                      Text(
                        listing['location'],
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmt(listing['price']),
                          style: const TextStyle(
                            color: kPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (user != null)
                          Text(
                            user['username'] ?? '',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                          ),
                      ],
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

  Widget _noImg() => Container(
        width: 90,
        height: 90,
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.image_outlined,
            color: Color(0xFFD1D5DB), size: 28),
      );
}
