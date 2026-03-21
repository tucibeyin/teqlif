import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
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
  String? _selectedCategory;
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

  bool get _hasFilter => _selectedCategory != null || _selectedCity != null;

  @override
  void initState() {
    super.initState();
    _load();
    CityService.getCities().then((c) {
      if (mounted) setState(() => _cities = c);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = <String, String>{};
      if (_selectedCategory != null) params['category'] = _selectedCategory!;
      if (_selectedCity != null) params['location'] = _selectedCity!;
      final uri = Uri.parse('$kBaseUrl/listings')
          .replace(queryParameters: params.isEmpty ? null : params);
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Bağlantı hatası';
        _loading = false;
      });
    }
  }

  void _clearAll() {
    setState(() {
      _selectedCategory = null;
      _selectedCity = null;
    });
    _load();
  }

  void _showCityPicker() {
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
                'Şehir Seç',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
            ListTile(
              title: const Text('Tüm Şehirler'),
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
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final city = _cities[i];
                  final selected = _selectedCity == city;
                  return ListTile(
                    title: Text(
                      city,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
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

  String get _sectionHeader {
    if (!_hasFilter) return 'Son İlanlar';
    if (_loading) return 'Aranıyor...';
    return '${_listings.length} ilan bulundu';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // ── AppBar ──────────────────────────────────────────────
            SliverAppBar(
              title: const Text(
                'İlanlar',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              backgroundColor: AppColors.surface(context),
              floating: true,
              snap: true,
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CreateListingScreen()),
                  ),
                  icon: const Icon(Icons.add, size: 18, color: kPrimary),
                  label: const Text(
                    'İlan Ver',
                    style: TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Kategori ikonları ────────────────────────────
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _categories.length,
                      itemBuilder: (context, i) {
                        final cat = _categories[i];
                        final slug = cat['slug'] as String;
                        final isSelected = _selectedCategory == slug;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedCategory =
                                isSelected ? null : slug);
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
                                        ? Border.all(
                                            color: kPrimaryDark, width: 1.5)
                                        : null,
                                  ),
                                  child: Icon(
                                    cat['icon'] as IconData,
                                    color: isSelected
                                        ? Colors.white
                                        : kPrimary,
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
                            onTap: _cities.isEmpty ? null : _showCityPicker,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
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
                                    _selectedCity ?? 'Şehir',
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
                              label: _categories.firstWhere(
                                      (c) => c['slug'] == _selectedCategory)[
                                  'label'] as String,
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
                              onTap: _clearAll,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.3),
                                      width: 1),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.close,
                                        size: 13, color: Colors.red),
                                    SizedBox(width: 4),
                                    Text(
                                      'Filtreleri Temizle',
                                      style: TextStyle(
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

                  // ── Başlık ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      _sectionHeader,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            // ── İlan grid ───────────────────────────────────────────
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
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_outlined,
                          size: 56, color: AppColors.border(context)),
                      const SizedBox(height: 12),
                      Text(
                        _hasFilter
                            ? 'Bu filtreyle ilan bulunamadı'
                            : 'Henüz ilan yok',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (_hasFilter) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _clearAll,
                          child: const Text('Filtreleri Temizle'),
                        ),
                      ],
                    ],
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
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _GridItem(
                      listing: _listings[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ListingDetailScreen(
                              listing:
                                  Map<String, dynamic>.from(_listings[i])),
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
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: kPrimary),
          ),
        ],
      ),
    );
  }
}

// ── İlan grid tile ──────────────────────────────────────────────────────────
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
