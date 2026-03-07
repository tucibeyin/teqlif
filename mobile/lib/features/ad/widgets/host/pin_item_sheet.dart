import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/providers/auth_provider.dart';

/// 2-tab BottomSheet: "Hızlı Ürün" and "İlanlarım".
/// Returns Map<String, dynamic>? via Navigator.pop — null means cancelled.
///   Quick mode:  { 'customTitle': str, 'customPrice': int, 'startingBid': int }
///   Ads mode:    { 'adId': str, 'startingBid': int }
class PinItemSheet extends ConsumerStatefulWidget {
  const PinItemSheet({super.key});

  @override
  ConsumerState<PinItemSheet> createState() => _PinItemSheetState();
}

class _PinItemSheetState extends ConsumerState<PinItemSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Hızlı Ürün
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _bidCtrl = TextEditingController();

  // İlanlarım
  List<Map<String, dynamic>> _adsList = [];
  bool _adsLoading = false;
  String? _selectedAdId;
  final _adBidCtrl = TextEditingController();

  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _adsList.isEmpty && !_adsLoading) {
        _fetchAds();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _bidCtrl.dispose();
    _adBidCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAds() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    setState(() => _adsLoading = true);
    try {
      final res = await ApiClient().get(
        '/api/ads',
        params: {'status': 'ACTIVE', 'userId': userId},
      );
      if (res.statusCode == 200 && res.data is List) {
        setState(() {
          _adsList = (res.data as List)
              .map((d) => {
                    'id': d['id']?.toString() ?? '',
                    'title': d['title']?.toString() ?? '',
                    'price': (d['price'] as num?)?.toDouble() ?? 0.0,
                    'startingBid': (d['startingBid'] as num?)?.toDouble(),
                    'images': (d['images'] as List?)
                            ?.map((e) => e.toString())
                            .toList() ??
                        <String>[],
                  })
              .toList();
        });
      }
    } catch (_) {
      setState(() => _adsList = []);
    } finally {
      setState(() => _adsLoading = false);
    }
  }

  void _submit() {
    setState(() => _error = null);
    if (_tabController.index == 0) {
      final title = _titleCtrl.text.trim();
      if (title.isEmpty) {
        setState(() => _error = 'Ürün adı zorunludur.');
        return;
      }
      final price =
          double.tryParse(_priceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
              0.0;
      final bid =
          double.tryParse(_bidCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
              price;
      Navigator.pop(context, {
        'customTitle': title,
        'customPrice': price.toInt(),
        'startingBid': bid.toInt(),
      });
    } else {
      if (_selectedAdId == null) {
        setState(() => _error = 'Bir ilan seçin.');
        return;
      }
      final bid = int.tryParse(
              _adBidCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
          0;
      Navigator.pop(context, {
        'adId': _selectedAdId,
        'startingBid': bid,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0E1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 4, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '\u{1F4CC} ÜRÜN SABİTLE',
                  style: TextStyle(
                    color: Color(0xFF06C8E0),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context, null),
                ),
              ],
            ),
          ),
          // Tabs
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF06C8E0),
            labelColor: const Color(0xFF06C8E0),
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 12),
            tabs: const [
              Tab(text: '\u26A1 HIZLI ÜRÜN'),
              Tab(text: '\u{1F4CB} İLANLARIM'),
            ],
          ),
          // Tab views
          SizedBox(
            height: 280,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildQuickTab(),
                _buildMyAdsTab(),
              ],
            ),
          ),
          // Error
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),
          // Footer buttons
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('İptal',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF06C8E0).withOpacity(0.18),
                      foregroundColor: const Color(0xFF06C8E0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(
                            color: Color(0xFF06C8E0), width: 0.8),
                      ),
                    ),
                    child: const Text(
                      '\u{1F4CC} Sahneye Sabitle',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('ÜRÜN ADI *'),
          const SizedBox(height: 6),
          _inputField(_titleCtrl, 'Örn: iPhone 14 Pro'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('ÜRÜN FİYATI (₺)'),
                    const SizedBox(height: 6),
                    _inputField(_priceCtrl, '0', numeric: true),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('BAŞLANGIÇ TEKLİFİ (₺)'),
                    const SizedBox(height: 6),
                    _inputField(_bidCtrl, 'Boş = fiyat', numeric: true),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyAdsTab() {
    return Column(
      children: [
        Expanded(
          child: _adsLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF06C8E0)))
              : _adsList.isEmpty
                  ? const Center(
                      child: Text(
                        'Aktif ilanınız bulunamadı.',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: _adsList.length,
                      itemBuilder: (ctx, i) {
                        final ad = _adsList[i];
                        final isSelected = _selectedAdId == ad['id'];
                        final images =
                            ad['images'] as List<String>? ?? [];
                        return GestureDetector(
                          onTap: () => setState(
                              () => _selectedAdId = ad['id'] as String),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF06C8E0)
                                    : Colors.white12,
                              ),
                              color: isSelected
                                  ? const Color(0xFF06C8E0)
                                      .withOpacity(0.08)
                                  : Colors.white.withOpacity(0.04),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: images.isNotEmpty
                                      ? Image.network(
                                          images.first,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _adPlaceholder(),
                                        )
                                      : _adPlaceholder(),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ad['title'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '₺${((ad['price'] ?? ad['startingBid'] ?? 0) as num).toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            color: Color(0xFF06C8E0),
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle,
                                      color: Color(0xFF06C8E0), size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        if (_selectedAdId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('BAŞLANGIÇ TEKLİFİ — Boş bırakılırsa ilan fiyatı'),
                const SizedBox(height: 6),
                _inputField(_adBidCtrl, '0', numeric: true),
              ],
            ),
          ),
      ],
    );
  }

  Widget _adPlaceholder() => Container(
        width: 44,
        height: 44,
        color: Colors.white10,
        child: const Icon(Icons.inventory_2_outlined,
            color: Colors.white38, size: 22),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      );

  Widget _inputField(TextEditingController ctrl, String hint,
      {bool numeric = false}) {
    return TextField(
      controller: ctrl,
      keyboardType:
          numeric ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Color(0xFF06C8E0)),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
      ),
    );
  }
}
