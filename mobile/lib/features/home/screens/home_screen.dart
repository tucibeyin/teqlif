import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';

// ── Static data ────────────────────────────────────────────────────────────

const _categories = [
  {'slug': 'elektronik', 'name': 'Elektronik', 'icon': '📱'},
  {'slug': 'mobilya', 'name': 'Mobilya', 'icon': '🛋️'},
  {'slug': 'giyim', 'name': 'Giyim', 'icon': '👕'},
  {'slug': 'arac', 'name': 'Araç', 'icon': '🚗'},
  {'slug': 'ev-esyasi', 'name': 'Ev Eşyası', 'icon': '🏠'},
  {'slug': 'spor', 'name': 'Spor', 'icon': '⚽'},
  {'slug': 'kitap', 'name': 'Kitap', 'icon': '📚'},
  {'slug': 'diger', 'name': 'Diğer', 'icon': '📦'},
];

// Top 20 provinces for quick access
const _provinces = [
  {'id': '34', 'name': 'İstanbul'},
  {'id': '06', 'name': 'Ankara'},
  {'id': '35', 'name': 'İzmir'},
  {'id': '16', 'name': 'Bursa'},
  {'id': '01', 'name': 'Adana'},
  {'id': '07', 'name': 'Antalya'},
  {'id': '41', 'name': 'Kocaeli'},
  {'id': '42', 'name': 'Konya'},
  {'id': '38', 'name': 'Kayseri'},
  {'id': '55', 'name': 'Samsun'},
  {'id': '27', 'name': 'Gaziantep'},
  {'id': '10', 'name': 'Balıkesir'},
  {'id': '61', 'name': 'Trabzon'},
  {'id': '09', 'name': 'Aydın'},
  {'id': '45', 'name': 'Manisa'},
  {'id': '26', 'name': 'Eskişehir'},
  {'id': '33', 'name': 'Mersin'},
  {'id': '44', 'name': 'Malatya'},
  {'id': '63', 'name': 'Şanlıurfa'},
  {'id': '31', 'name': 'Hatay'},
];

// ── Provider ──────────────────────────────────────────────────────────────

class FilterState {
  final String? category;
  final String? provinceId;
  const FilterState({this.category, this.provinceId});
}

final adsProvider = FutureProvider.family<List<AdModel>, FilterState>(
  (ref, filter) async {
    final params = <String, dynamic>{'status': 'ACTIVE'};
    if (filter.category != null) params['category'] = filter.category;
    if (filter.provinceId != null) params['province'] = filter.provinceId;
    final res = await ApiClient().get(Endpoints.ads, params: params);
    final list = res.data as List<dynamic>;
    return list
        .map((e) => AdModel.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);

// ── Screen ─────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedCategory;
  String? _selectedProvinceId;
  String? _selectedProvinceName;
  final _searchCtrl = TextEditingController();
  List<AdModel> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final res =
          await ApiClient().get(Endpoints.search, params: {'q': q});
      final list = res.data as List<dynamic>;
      setState(() {
        _searchResults = list
            .map((e) => AdModel.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _showProvinceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProvinceSheet(
        selected: _selectedProvinceId,
        onSelect: (id, name) {
          setState(() {
            _selectedProvinceId = id;
            _selectedProvinceName = name;
          });
          Navigator.pop(context);
        },
        onClear: () {
          setState(() {
            _selectedProvinceId = null;
            _selectedProvinceName = null;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  bool get _hasFilters =>
      _selectedCategory != null || _selectedProvinceId != null;

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'İlan ara...',
                prefixIcon:
                    Icon(Icons.search, color: Color(0xFF9AAAB8), size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                hintStyle: TextStyle(color: Color(0xFF9AAAB8), fontSize: 14),
              ),
              onChanged: _search,
            ),
          ),
          const SizedBox(height: 8),
          // Row: Category chips + Province button
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildCatChip(null, '🏷️', 'Tümü'),
                      ..._categories.map((c) => _buildCatChip(
                          c['slug'], c['icon']!, c['name']!)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showProvinceSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _selectedProvinceId != null
                        ? const Color(0xFF00B4CC)
                        : const Color(0xFFF4F7FA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedProvinceId != null
                          ? const Color(0xFF00B4CC)
                          : const Color(0xFFE2EBF0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14,
                          color: _selectedProvinceId != null
                              ? Colors.white
                              : const Color(0xFF4A5568)),
                      const SizedBox(width: 4),
                      Text(
                        _selectedProvinceName ?? 'Şehir',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _selectedProvinceId != null
                              ? Colors.white
                              : const Color(0xFF4A5568),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Active filter indicators
          if (_hasFilters) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Filtreler aktif',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9AAAB8),
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategory = null;
                    _selectedProvinceId = null;
                    _selectedProvinceName = null;
                    _searchCtrl.clear();
                    _searchResults = [];
                  }),
                  child: const Text(
                    'Temizle',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF00B4CC),
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCatChip(String? slug, String icon, String name) {
    final selected = _selectedCategory == slug;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = slug),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00B4CC)
              : const Color(0xFFF4F7FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF00B4CC) : const Color(0xFFE2EBF0),
          ),
        ),
        child: Text(
          '$icon $name',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF4A5568),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter =
        _FilterState(category: _selectedCategory, provinceId: _selectedProvinceId);
    final adsAsync = ref.watch(adsProvider(filter));
    final isSearchActive =
        _searchCtrl.text.length >= 2 && _searchResults.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: Column(
          children: [
            // App bar row
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text(
                    'teqlif',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF00B4CC),
                    ),
                  ),
                  const Spacer(),
                  // Ad count badge
                  adsAsync.when(
                    data: (ads) => Text(
                      '${ads.length} ilan',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9AAAB8),
                          fontWeight: FontWeight.w500),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            // Filter bar
            _buildFilterBar(),
            // Divider
            const Divider(height: 1, color: Color(0xFFE2EBF0)),
            // Content
            Expanded(
              child: isSearchActive
                  ? _SearchResultsList(results: _searchResults)
                  : _isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : adsAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) =>
                              Center(child: Text('Hata: $e')),
                          data: (ads) => ads.isEmpty
                              ? _EmptyState(
                                  hasFilters: _hasFilters,
                                  onClear: () => setState(() {
                                    _selectedCategory = null;
                                    _selectedProvinceId = null;
                                    _selectedProvinceName = null;
                                  }),
                                )
                              : RefreshIndicator(
                                  onRefresh: () =>
                                      ref.refresh(adsProvider(filter).future),
                                  child: GridView.builder(
                                    padding: const EdgeInsets.all(12),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      childAspectRatio: 0.72,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: ads.length,
                                    itemBuilder: (ctx, i) =>
                                        _AdCard(ad: ads[i]),
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

// ── Province bottom sheet ─────────────────────────────────────────────────

class _ProvinceSheet extends StatefulWidget {
  final String? selected;
  final void Function(String id, String name) onSelect;
  final VoidCallback onClear;

  const _ProvinceSheet(
      {required this.selected,
      required this.onSelect,
      required this.onClear});

  @override
  State<_ProvinceSheet> createState() => _ProvinceSheetState();
}

class _ProvinceSheetState extends State<_ProvinceSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, String>> _filtered = List.from(_provinces);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _filter(String q) {
    setState(() {
      _filtered = _provinces
          .where((p) =>
              p['name']!.toLowerCase().contains(q.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE2EBF0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Şehir Seç',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                if (widget.selected != null)
                  TextButton(
                    onPressed: widget.onClear,
                    child: const Text('Temizle',
                        style: TextStyle(color: Color(0xFFEF4444))),
                  ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: 'Şehir ara...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: const Color(0xFFF4F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: _filter,
            ),
          ),
          // List
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final p = _filtered[i];
                final isSelected = p['id'] == widget.selected;
                return ListTile(
                  leading: Icon(
                    Icons.location_city_outlined,
                    color: isSelected
                        ? const Color(0xFF00B4CC)
                        : const Color(0xFF9AAAB8),
                    size: 20,
                  ),
                  title: Text(
                    p['name']!,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: isSelected
                          ? const Color(0xFF00B4CC)
                          : const Color(0xFF0F1923),
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle,
                          color: Color(0xFF00B4CC), size: 20)
                      : null,
                  onTap: () => widget.onSelect(p['id']!, p['name']!),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search results ─────────────────────────────────────────────────────────

class _SearchResultsList extends StatelessWidget {
  final List<AdModel> results;
  const _SearchResultsList({required this.results});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: results.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFFE2EBF0)),
      itemBuilder: (ctx, i) => _AdListTile(ad: results[i]),
    );
  }
}

// ── Ad card ────────────────────────────────────────────────────────────────

class _AdCard extends StatelessWidget {
  final AdModel ad;
  const _AdCard({required this.ad});

  String _fmt(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/ad/${ad.id}'),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ad.images.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl(ad.images.first),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(
                          color: const Color(0xFFF4F7FA),
                          child: const Icon(Icons.image_outlined,
                              color: Color(0xFF9AAAB8), size: 32)),
                      errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFFF4F7FA),
                          child: const Icon(Icons.image_not_supported_outlined,
                              color: Color(0xFF9AAAB8))),
                    )
                  : Container(
                      color: const Color(0xFFF4F7FA),
                      child: Center(
                        child: Text(ad.category?.icon ?? '📦',
                            style: const TextStyle(fontSize: 36)),
                      ),
                    ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ad.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const Spacer(),
                    Text(
                      ad.startingBid == null
                          ? '🔥 Serbest'
                          : _fmt(ad.startingBid!),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF00B4CC)),
                    ),
                    Row(
                      children: [
                        if (ad.province != null) ...[
                          const Icon(Icons.location_on_outlined,
                              size: 10, color: Color(0xFF9AAAB8)),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              ad.province!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xFF9AAAB8)),
                            ),
                          ),
                        ],
                        if (ad.count != null && ad.count!.bids > 0)
                          Text('🔨${ad.count!.bids}',
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xFF9AAAB8))),
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
}

// ── List tile (search) ─────────────────────────────────────────────────────

class _AdListTile extends StatelessWidget {
  final AdModel ad;
  const _AdListTile({required this.ad});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ad.images.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl(ad.images.first),
                width: 56,
                height: 56,
                fit: BoxFit.cover)
            : Container(
                width: 56,
                height: 56,
                color: const Color(0xFFF4F7FA),
                child: Center(child: Text(ad.category?.icon ?? '📦'))),
      ),
      title: Text(ad.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        '${ad.province?.name ?? ''} · ${ad.category?.name ?? ''}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF9AAAB8)),
      ),
      trailing: ad.startingBid == null
          ? const Text('🔥',
              style: TextStyle(fontSize: 16))
          : Text(
              '₺${ad.startingBid!.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF00B4CC)),
            ),
      onTap: () => context.push('/ad/${ad.id}'),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  final VoidCallback onClear;
  const _EmptyState({required this.hasFilters, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(hasFilters ? '🔍' : '📭',
              style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(
            hasFilters ? 'Sonuç bulunamadı' : 'Henüz ilan yok',
            style:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilters
                ? 'Farklı kategori veya şehir deneyin.'
                : 'Bu kategoride ilan bulunmuyor.',
            style: const TextStyle(color: Color(0xFF9AAAB8)),
            textAlign: TextAlign.center,
          ),
          if (hasFilters) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Filtreleri Temizle'),
            ),
          ],
        ],
      ),
    );
  }
}
