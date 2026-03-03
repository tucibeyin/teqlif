import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../../../core/constants/categories.dart';
import '../../ad/screens/live_arena_host.dart';
import '../widgets/live_stories.dart';

// ── Static data ────────────────────────────────────────────────────────────
// (categoryTree artık categories.dart'tan geliyor)

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterState &&
          runtimeType == other.runtimeType &&
          category == other.category &&
          provinceId == other.provinceId;

  @override
  int get hashCode => category.hashCode ^ provinceId.hashCode;
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
  String? _selectedCategorySlug;
  String? _selectedCategoryName;
  String? _selectedProvinceId;
  String? _selectedProvinceName;
  final _searchCtrl = TextEditingController();
  List<AdModel> _searchResults = [];
  bool _isSearching = false;
  bool _isListView = false;

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
      final params = <String, dynamic>{'status': 'ACTIVE', 'q': q};
      if (_selectedCategorySlug != null) params['category'] = _selectedCategorySlug;
      if (_selectedProvinceId != null) params['province'] = _selectedProvinceId;

      final res = await ApiClient().get(Endpoints.ads, params: params);
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

  void _showCategorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategorySheet(
        selected: _selectedCategorySlug,
        onSelect: (slug, name) {
          setState(() {
            _selectedCategorySlug = slug;
            _selectedCategoryName = name;
          });
          Navigator.pop(context);
        },
        onClear: () {
          setState(() {
            _selectedCategorySlug = null;
            _selectedCategoryName = null;
          });
          Navigator.pop(context);
        },
      ),
    );
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
      _selectedCategorySlug != null || _selectedProvinceId != null;

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
          // Row: Category button + Province button
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _showCategorySheet,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _selectedCategorySlug != null
                          ? const Color(0xFF00B4CC)
                          : const Color(0xFFF4F7FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selectedCategorySlug != null
                            ? const Color(0xFF00B4CC)
                            : const Color(0xFFE2EBF0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.category_outlined,
                            size: 14,
                            color: _selectedCategorySlug != null
                                ? Colors.white
                                : const Color(0xFF4A5568)),
                        const SizedBox(width: 4),
                        Text(
                          _selectedCategoryName ?? 'Kategori',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _selectedCategorySlug != null
                                ? Colors.white
                                : const Color(0xFF4A5568),
                          ),
                        ),
                      ],
                    ),
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
              const SizedBox(width: 8),
              // View toggle button
              GestureDetector(
                onTap: () => setState(() => _isListView = !_isListView),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7FA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2EBF0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_isListView ? Icons.grid_view : Icons.view_list,
                          size: 14, color: const Color(0xFF4A5568)),
                      const SizedBox(width: 4),
                      Text(
                        _isListView ? 'Izgara' : 'Liste',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4A5568),
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
                    _selectedCategorySlug = null;
                    _selectedCategoryName = null;
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

  Future<void> _showQuickLiveBottomSheet() async {
    final titleCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    File? selectedImage;
    bool isLoading = false;
    final picker = ImagePicker();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🔴 Canlı Yayın Aç',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Yayın Başlığı *',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      hintText: 'Örn: Antika Saat Açık Arttırması',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Başlangıç Fiyatı (₺)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Opsiyonel (Varsayılan: 1₺)',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Kapak Fotoğrafı (İsteğe Bağlı)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                            if (picked != null) {
                              setModalState(() => selectedImage = File(picked.path));
                            }
                          },
                          icon: const Icon(Icons.photo_library),
                          label: Text(selectedImage != null ? 'Değiştir' : 'Fotoğraf Seç'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      if (selectedImage != null) ...[
                        const SizedBox(width: 12),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                selectedImage!,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -8,
                              right: -8,
                              child: GestureDetector(
                                onTap: () => setModalState(() => selectedImage = null),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            final title = titleCtrl.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Lütfen yayın başlığı girin.')),
                              );
                              return;
                            }

                            setModalState(() => isLoading = true);

                            try {
                              String? uploadedImageUrl;

                              // 1. Upload the image if selected
                              if (selectedImage != null) {
                                final form = FormData.fromMap({
                                  'file': await MultipartFile.fromFile(
                                    selectedImage!.path,
                                    filename: selectedImage!.path.split('/').last,
                                  ),
                                });
                                final uploadRes = await ApiClient().uploadFile('/api/upload', form);
                                uploadedImageUrl = uploadRes.data['url'] as String;
                              }

                              final price =
                                  int.tryParse(priceCtrl.text.trim()) ?? 1;
                              final res = await ApiClient().post(
                                '/api/livekit/quick-start',
                                data: {
                                  'title': title,
                                  'startingBid': price,
                                  if (uploadedImageUrl != null) 'images': [uploadedImageUrl],
                                },
                              );

                              if (res.statusCode == 201 && res.data != null) {
                                final adId = res.data['id'];
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  
                                  final ad = AdModel.fromJson(res.data);

                                  // Request permissions before jumping to Arena
                                  final cameraStatus = await Permission.camera.request();
                                  final micStatus = await Permission.microphone.request();

                                  if (cameraStatus != PermissionStatus.granted || micStatus != PermissionStatus.granted) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Kamera ve Mikrofon izni olmadan canlı yayın başlatılamaz!')),
                                      );
                                      context.push('/ad/${ad.id}');
                                    }
                                    return;
                                  }

                                  // Direct navigation to Host Arena
                                  Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute(builder: (_) => LiveArenaHost(ad: ad))
                                  );

                                  // Invalidate providers to show the new live ad
                                  ref.invalidate(adsProvider);
                                }
                              } else {
                                throw Exception('Sunucu hatası');
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Yayına başlanamadı: $e')),
                                );
                              }
                            } finally {
                              setModalState(() => isLoading = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'YAYINI HEMEN BAŞLAT',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = FilterState(
        category: _selectedCategorySlug, provinceId: _selectedProvinceId);
    final adsAsync = ref.watch(adsProvider(filter));
    final isSearchActive =
        _searchCtrl.text.length >= 2 && _searchResults.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showQuickLiveBottomSheet,
        backgroundColor: Colors.redAccent,
        icon: const Icon(Icons.sensors, color: Colors.white),
        label: const Text(
          'Canlı Yayın Aç',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        elevation: 4,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // App bar row
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(liveAdsProvider);
                  return ref.refresh(adsProvider(filter).future);
                },
                child: isSearchActive
                    ? _SearchResultsList(results: _searchResults)
                    : _isSearching
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Live Stories
                              const LiveStories(),
                              // Feed
                              Expanded(
                                child: adsAsync.when(
                                  loading: () => const Center(
                                      child: CircularProgressIndicator()),
                                  error: (e, _) =>
                                      Center(child: Text('Hata: $e')),
                                  data: (ads) => ads.isEmpty
                                      ? _EmptyState(
                                          hasFilters: _hasFilters,
                                          onClear: () => setState(() {
                                            _selectedCategorySlug = null;
                                            _selectedCategoryName = null;
                                            _selectedProvinceId = null;
                                            _selectedProvinceName = null;
                                          }),
                                        )
                                      : _isListView
                                          ? ListView.separated(
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 8),
                                              itemCount: ads.length,
                                              separatorBuilder: (_, __) =>
                                                  const Divider(
                                                      height: 1,
                                                      color: Color(0xFFE2EBF0)),
                                              itemBuilder: (ctx, i) =>
                                                  _AdListTile(ad: ads[i]),
                                            )
                                          : GridView.builder(
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

// ── Category bottom sheet (N-katmanlı, stack tabanlı) ─────────────────────

class _CategorySheet extends StatefulWidget {
  final String? selected;
  final void Function(String slug, String name) onSelect;
  final VoidCallback onClear;

  const _CategorySheet(
      {required this.selected, required this.onSelect, required this.onClear});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  /// Geçmişe göre yığın: boşsa root listelenir,
  /// doluysa son elemanın children listelenir.
  final List<CategoryNode> _stack = [];

  List<CategoryNode> get _currentChildren =>
      _stack.isEmpty ? categoryTree : _stack.last.children;

  String get _headerTitle {
    if (_stack.isEmpty) return 'Kategori Seç';
    return _stack.map((n) => n.name).join(' › ');
  }

  void _onTap(CategoryNode node) {
    if (node.isLeaf) {
      // Yaprak → seç ve kapat
      final path = [..._stack, node];
      final label = path
          .map((n) => n.name)
          .join(' › ');
      widget.onSelect(node.slug, label);
    } else {
      setState(() => _stack.add(node));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                if (_stack.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 16),
                    onPressed: () => setState(() => _stack.removeLast()),
                  ),
                Expanded(
                  child: Text(
                    _headerTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.selected != null)
                  TextButton(
                    onPressed: widget.onClear,
                    child: const Text('Temizle',
                        style: TextStyle(color: Color(0xFFEF4444))),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: _currentChildren.length,
              itemBuilder: (_, i) {
                final node = _currentChildren[i];
                final isSelected = widget.selected == node.slug;
                final hasSelectedChild = widget.selected != null &&
                    findPath(widget.selected!, node.children) != null;

                return ListTile(
                  leading: node.icon.isNotEmpty
                      ? Text(node.icon,
                          style: const TextStyle(fontSize: 20))
                      : null,
                  title: Text(
                    node.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected || hasSelectedChild
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected || hasSelectedChild
                          ? const Color(0xFF00B4CC)
                          : const Color(0xFF0F1923),
                    ),
                  ),
                  trailing: node.isLeaf
                      ? (isSelected
                          ? const Icon(Icons.check_circle,
                              color: Color(0xFF00B4CC), size: 20)
                          : null)
                      : const Icon(Icons.chevron_right,
                          color: Color(0xFF9AAAB8)),
                  onTap: () => _onTap(node),
                );
              },
            ),
          ),
        ],
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
      {required this.selected, required this.onSelect, required this.onClear});

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
          .where((p) => p['name']!.toLowerCase().contains(q.toLowerCase()))
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
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
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
                  ? Container(
                      color: const Color(0xFFF4F7FA),
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl(ad.images.first),
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(
                          child: Icon(Icons.image_outlined,
                              color: Color(0xFF9AAAB8), size: 32),
                        ),
                        errorWidget: (_, __, ___) => const Center(
                          child: Icon(Icons.image_not_supported_outlined,
                              color: Color(0xFF9AAAB8)),
                        ),
                      ),
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
                      ad.highestBidAmount != null
                          ? 'Güncel ${_fmt(ad.highestBidAmount!)}'
                          : ad.isFixedPrice
                              ? _fmt(ad.price)
                              : ad.startingBid == null
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

  String _fmt(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => context.push('/ad/${ad.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ad.images.isNotEmpty
            ? Container(
                width: 56,
                height: 56,
                color: const Color(0xFFF4F7FA),
                child: CachedNetworkImage(
                    imageUrl: imageUrl(ad.images.first),
                    fit: BoxFit.contain,
                ),
              )
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${ad.province?.name ?? ''} · ${ad.category?.name ?? ''}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9AAAB8)),
          ),
          const SizedBox(height: 4),
          Text(
            ad.highestBidAmount != null
                ? _fmt(ad.highestBidAmount!)
                : (ad.startingBid != null
                    ? _fmt(ad.startingBid!)
                    : 'Serbest Teqlif'),
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Color(0xFF00B4CC)),
          ),
        ],
      ),
      trailing: ad.highestBidAmount != null
          ? Text(
              'Güncel ${_fmt(ad.highestBidAmount!)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF00B4CC)),
            )
          : ad.isFixedPrice
              ? Text(
                  _fmt(ad.price),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF00B4CC)),
                )
              : ad.startingBid == null
                  ? const Text('🔥', style: TextStyle(fontSize: 16))
                  : Text(
                      _fmt(ad.startingBid!),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF00B4CC)),
                    ),
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
          Text(hasFilters ? '🔍' : '📭', style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(
            hasFilters ? 'Sonuç bulunamadı' : 'Henüz ilan yok',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
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
