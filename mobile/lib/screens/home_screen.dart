import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../services/city_service.dart';
import 'create_listing_screen.dart';
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
  String? _selectedCity;
  List<String> _cities = [];

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
    CityService.getCities().then((c) {
      if (mounted) setState(() => _cities = c);
    });
  }

  Future<void> _load({String? category}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = <String, String>{};
      if (category != null) params['category'] = category;
      if (_selectedCity != null) params['location'] = _selectedCity!;
      final uri = Uri.parse('$kBaseUrl/listings').replace(queryParameters: params.isEmpty ? null : params);
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
              backgroundColor: AppColors.surface(context),
              floating: true,
              snap: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'İlan Ver',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateListingScreen()),
                  ),
                ),
              ],
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
                                    color: AppColors.primaryBg(context),
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
                  // Konum filtresi — dropdown
                  if (_cities.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border(context)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedCity,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                            style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Tüm Şehirler'),
                              ),
                              ..._cities.map((c) => DropdownMenuItem<String?>(
                                    value: c,
                                    child: Text(c),
                                  )),
                            ],
                            onChanged: (v) {
                              setState(() => _selectedCity = v);
                              _load();
                            },
                          ),
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                padding: const EdgeInsets.symmetric(horizontal: 2),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _GridItem(
                      listing: _listings[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ListingDetailScreen(
                              listing: Map<String, dynamic>.from(_listings[i])),
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

class _GridItem extends StatelessWidget {
  final Map<String, dynamic> listing;
  final VoidCallback onTap;
  const _GridItem({required this.listing, required this.onTap});

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
              ? Image.network(
                  photo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),
          // Alt gradient + fiyat
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

  Widget _placeholder() => Builder(
        builder: (context) => Container(
          color: AppColors.surfaceVariant(context),
          child: Center(
            child: Icon(Icons.image_outlined,
                size: 28, color: AppColors.border(context)),
          ),
        ),
      );
}
