import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../../home/screens/home_screen.dart';
import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';
import '../../../core/constants/locations.dart';
import '../../../core/constants/categories.dart';

class EditAdScreen extends ConsumerStatefulWidget {
  final String adId;
  const EditAdScreen({super.key, required this.adId});

  @override
  ConsumerState<EditAdScreen> createState() => _EditAdScreenState();
}

class _EditAdScreenState extends ConsumerState<EditAdScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _startBidCtrl = TextEditingController();
  final _minBidStepCtrl = TextEditingController();
  final _buyItNowCtrl = TextEditingController();
  String? _selectedCategory; // leaf slug
  String? _selectedRootSlug;
  String? _selectedSubSlug;
  String? _selectedProvinceId;
  String? _selectedDistrictId;
  bool _loading = true;
  bool _saving = false;
  bool _isFixedPrice = false;
  bool _showPhone = false;

  RootCategory? get _rootObj => _selectedRootSlug == null
      ? null
      : categoryTree.firstWhere((r) => r.slug == _selectedRootSlug,
          orElse: () => categoryTree.first);
  SubCategory? get _subObj => _selectedSubSlug == null || _rootObj == null
      ? null
      : _rootObj!.children.firstWhere((s) => s.slug == _selectedSubSlug,
          orElse: () => _rootObj!.children.first);
  bool get _isLeafOnly =>
      _rootObj != null && _rootObj!.children.isEmpty;
  String? get _effectiveLeafSlug =>
      _isLeafOnly ? _selectedRootSlug : _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _startBidCtrl.dispose();
    _minBidStepCtrl.dispose();
    _buyItNowCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAd() async {
    try {
      final res = await ApiClient().get(Endpoints.adById(widget.adId));
      final ad = AdModel.fromJson(res.data as Map<String, dynamic>);
      setState(() {
        final formatter = CurrencyTextInputFormatter.currency(
            locale: 'tr_TR', symbol: '', decimalDigits: 2);
        _titleCtrl.text = ad.title;
        _descCtrl.text = ad.description;
        _priceCtrl.text = formatter.formatDouble(ad.price);
        _minBidStepCtrl.text = formatter.formatDouble(ad.minBidStep);
        _isFixedPrice = ad.isFixedPrice;
        _showPhone = ad.showPhone;
        _startBidCtrl.text = ad.startingBid != null
            ? formatter.formatDouble(ad.startingBid!)
            : '';
        _buyItNowCtrl.text = ad.buyItNowPrice != null
            ? formatter.formatDouble(ad.buyItNowPrice!)
            : '';
        final sel = findSelections(ad.category?.slug ?? '');
        _selectedRootSlug = sel.root.isEmpty ? null : sel.root;
        _selectedSubSlug = sel.sub.isEmpty ? null : sel.sub;
        _selectedCategory = sel.leaf.isEmpty ? null : sel.leaf;
        _selectedProvinceId = ad.province?.id;
        _selectedDistrictId = ad.district?.id;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.isEmpty ||
        _descCtrl.text.isEmpty ||
        _priceCtrl.text.isEmpty ||
        _effectiveLeafSlug == null ||
        _selectedProvinceId == null ||
        _selectedDistrictId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen tüm alanları doldurun.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient().put(Endpoints.adById(widget.adId), data: {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text
            .replaceAll('₺', '')
            .replaceAll(' ', '')
            .replaceAll('.', '')
            .replaceAll(',', '.')),
        'isFixedPrice': _isFixedPrice,
        'showPhone': _showPhone,
        'startingBid': _isFixedPrice
            ? null
            : (_startBidCtrl.text.isEmpty
                ? null
                : double.parse(_startBidCtrl.text
                    .replaceAll('₺', '')
                    .replaceAll(' ', '')
                    .replaceAll('.', '')
                    .replaceAll(',', '.'))),
        'minBidStep': _isFixedPrice || _minBidStepCtrl.text.isEmpty
            ? 100
            : double.parse(_minBidStepCtrl.text
                .replaceAll('₺', '')
                .replaceAll(' ', '')
                .replaceAll('.', '')
                .replaceAll(',', '.')),
        'buyItNowPrice': _isFixedPrice || _buyItNowCtrl.text.isEmpty
            ? null
            : double.parse(_buyItNowCtrl.text
                .replaceAll('₺', '')
                .replaceAll(' ', '')
                .replaceAll('.', '')
                .replaceAll(',', '.')),
        'categorySlug': _effectiveLeafSlug,
        'provinceId': _selectedProvinceId,
        'districtId': _selectedDistrictId,
      });
      ref.invalidate(adsProvider(const FilterState()));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('İlan güncellendi! ✅')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
          ),
          title: const Text('İlanı Düzenle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Başlık'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Açıklama'),
            ),
            const SizedBox(height: 12),
            // ── 3 Kademeli Kategori Seçimi ──
            // Level 1: Ana Kategori
            DropdownButtonFormField<String>(
              value: _selectedRootSlug,
              decoration: const InputDecoration(labelText: 'Ana Kategori'),
              items: categoryTree
                  .map((r) => DropdownMenuItem(
                      value: r.slug, child: Text('${r.icon} ${r.name}')))
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedRootSlug = v;
                _selectedSubSlug = null;
                _selectedCategory = null;
              }),
            ),
            const SizedBox(height: 12),
            // Level 2: Alt Kategori
            if (_selectedRootSlug != null &&
                _rootObj != null &&
                _rootObj!.children.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedSubSlug,
                decoration: const InputDecoration(labelText: 'Alt Kategori'),
                items: _rootObj!.children
                    .map((s) =>
                        DropdownMenuItem(value: s.slug, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedSubSlug = v;
                  _selectedCategory = null;
                }),
              ),
              const SizedBox(height: 12),
            ],
            // Level 3: İlan Türü
            if (_selectedSubSlug != null &&
                _subObj != null &&
                _subObj!.leaves.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'İlan Türü'),
                items: _subObj!.leaves
                    .map((l) =>
                        DropdownMenuItem(value: l.slug, child: Text(l.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            // Province dropdown
            DropdownButtonFormField<String>(
              value: _selectedProvinceId,
              decoration: const InputDecoration(labelText: 'İl (Şehir)'),
              items: AppLocations.provinces
                  .map((p) =>
                      DropdownMenuItem(value: p['id'], child: Text(p['name']!)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedProvinceId = v;
                  _selectedDistrictId = null; // reset district when province changes
                });
              },
            ),
            const SizedBox(height: 12),
            // Dependent District Dropdown
            DropdownButtonFormField<String>(
              value: _selectedDistrictId, // Can be null initially
              decoration: const InputDecoration(labelText: 'İlçe'),
              items: _selectedProvinceId == null
                  ? [] // Empty items until province is selected
                  : (AppLocations.districts[_selectedProvinceId] ?? [])
                      .map((d) => DropdownMenuItem(
                          value: d['id'], child: Text(d['name']!)))
                      .toList(),
              onChanged: _selectedProvinceId == null
                  ? null // Disabled if province is not selected
                  : (v) => setState(() => _selectedDistrictId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                CurrencyTextInputFormatter.currency(
                    locale: 'tr_TR', symbol: '', decimalDigits: 2)
              ],
              decoration: InputDecoration(
                  labelText:
                      _isFixedPrice ? 'Satış Fiyatı (₺)' : 'Piyasa Değeri (₺)',
                  prefixIcon: const Icon(Icons.monetization_on_outlined)),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _isFixedPrice,
                      onChanged: (v) => setState(() => _isFixedPrice = v),
                      title: const Text('🛍️ Sabit Fiyatlı İlan'),
                      subtitle: const Text(
                          'Ürün direkt belirlenen satış fiyatından tekliflere kapalı listelenir.'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (!_isFixedPrice) ...[
                      const Divider(),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Nasıl İşler? İlanınıza teklif verilebilir durumdadır. İster bir başlangıç açılış teklifi belirleyebilir (Örn: 5000 ₺), isterseniz boş bırakarak serbest pazar fiyatlamasına (1 ₺\'den başlar) izin verebilirsiniz.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF4A5568)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _startBidCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          CurrencyTextInputFormatter.currency(
                              locale: 'tr_TR', symbol: '', decimalDigits: 2)
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Açılış Teklifi (₺) (İsteğe Bağlı)',
                            helperText: 'Boş bırakırsanız 1 ₺\'den açık artırma başlar.'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _minBidStepCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          CurrencyTextInputFormatter.currency(
                              locale: 'tr_TR', symbol: '', decimalDigits: 2)
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Pey Aralığı (Minimum Artış) (₺)',
                            helperText:
                                'Teklif verenlerin en az ne kadar artırması gerektiğini belirler.'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _buyItNowCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          CurrencyTextInputFormatter.currency(
                              locale: 'tr_TR', symbol: '', decimalDigits: 2)
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Hemen Al Fiyatı (₺) (Opsiyonel)',
                            helperText:
                                'Açık artırma bitmeden bu fiyata hemen satabilirsiniz.'),
                      ),
                    ],
                    const Divider(),
                    SwitchListTile(
                      value: _showPhone,
                      onChanged: (v) => setState(() => _showPhone = v),
                      title: const Text('📞 Telefonum İlanda Gösterilsin'),
                      subtitle: const Text(
                          'İşaretlemezseniz, alıcılar sizinle sadece mesajlaşabilir.'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
