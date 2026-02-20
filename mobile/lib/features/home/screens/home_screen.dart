import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/ad.dart';

// Categories matching the backend
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

final adsProvider = FutureProvider.family<List<AdModel>, String?>(
  (ref, category) async {
    final api = ApiClient();
    final params = <String, dynamic>{'status': 'ACTIVE'};
    if (category != null) params['category'] = category;
    final res = await api.get(Endpoints.ads, params: params);
    final list = res.data as List<dynamic>;
    return list.map((e) => AdModel.fromJson(e as Map<String, dynamic>)).toList();
  },
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedCategory;
  final _searchCtrl = TextEditingController();
  List<AdModel> _searchResults = [];
  bool _isSearching = false;
  bool _showSearch = false;

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
      final res = await ApiClient().get(Endpoints.search, params: {'q': q});
      final list = res.data as List<dynamic>;
      setState(() {
        _searchResults =
            list.map((e) => AdModel.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (_) {} finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adsAsync = ref.watch(adsProvider(_selectedCategory));

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'İlan ara...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: _search,
              )
            : const Text('teqlif'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchCtrl.clear();
                  _searchResults = [];
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Category chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _CategoryChip(
                  label: '🏷️ Tümü',
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                ..._categories.map((cat) => _CategoryChip(
                      label: '${cat['icon']} ${cat['name']}',
                      selected: _selectedCategory == cat['slug'],
                      onTap: () =>
                          setState(() => _selectedCategory = cat['slug']),
                    )),
              ],
            ),
          ),
          // Search results overlay
          if (_showSearch && _searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _searchResults.length,
                itemBuilder: (ctx, i) =>
                    _AdListTile(ad: _searchResults[i]),
              ),
            )
          else if (_showSearch && _isSearching)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: adsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Hata: $e')),
                data: (ads) => ads.isEmpty
                    ? _EmptyState(
                        onPostAd: () => context.push('/post-ad'))
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(adsProvider(_selectedCategory).future),
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
                          itemBuilder: (ctx, i) => _AdCard(ad: ads[i]),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00B4CC).withOpacity(0.12)
              : Colors.white,
          border: Border.all(
              color: selected ? const Color(0xFF00B4CC) : const Color(0xFFE2EBF0)),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFF00B4CC) : const Color(0xFF4A5568),
          ),
        ),
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  final AdModel ad;
  const _AdCard({required this.ad});

  String _formatPrice(double p) =>
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
            // Image
            Expanded(
              flex: 3,
              child: ad.images.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: ad.images.first,
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
                        child: Text(
                          ad.category?.icon ?? '📦',
                          style: const TextStyle(fontSize: 36),
                        ),
                      ),
                    ),
            ),
            // Content
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      ad.startingBid == null
                          ? '🔥 Serbest Teklif'
                          : _formatPrice(ad.startingBid!),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF00B4CC)),
                    ),
                    if (ad.count != null && ad.count!.bids > 0)
                      Text(
                        '🔨 ${ad.count!.bids} teklif',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9AAAB8)),
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
                imageUrl: ad.images.first,
                width: 48,
                height: 48,
                fit: BoxFit.cover)
            : Container(
                width: 48, height: 48,
                color: const Color(0xFFF4F7FA),
                child: Center(child: Text(ad.category?.icon ?? '📦'))),
      ),
      title: Text(ad.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(ad.province?.name ?? '',
          style: const TextStyle(fontSize: 12)),
      onTap: () => context.push('/ad/${ad.id}'),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPostAd;
  const _EmptyState({required this.onPostAd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📭', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          const Text('Henüz ilan yok',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Bu kategoride ilan bulunmuyor.',
              style: TextStyle(color: Color(0xFF9AAAB8))),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onPostAd, child: const Text('İlan Ver')),
        ],
      ),
    );
  }
}
