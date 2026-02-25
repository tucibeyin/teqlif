import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../home/screens/home_screen.dart';
import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';
import '../../../core/constants/locations.dart';



const _categories = [
  {'slug': 'elektronik', 'name': 'Elektronik'},
  {'slug': 'arac', 'name': 'Araç'},
  {'slug': 'emlak', 'name': 'Emlak'},
  {'slug': 'giyim', 'name': 'Giyim & Moda'},
  {'slug': 'mobilya', 'name': 'Mobilya & Ev'},
  {'slug': 'spor', 'name': 'Spor & Outdoor'},
  {'slug': 'kitap', 'name': 'Kitap & Hobi'},
  {'slug': 'koleksiyon', 'name': 'Koleksiyon & Antika'},
  {'slug': 'cocuk', 'name': 'Bebek & Çocuk'},
  {'slug': 'bahce', 'name': 'Bahçe & Tarım'},
  {'slug': 'hayvan', 'name': 'Hayvanlar'},
  {'slug': 'diger', 'name': 'Diğer'},
];

class PostAdScreen extends ConsumerStatefulWidget {
  const PostAdScreen({super.key});

  @override
  ConsumerState<PostAdScreen> createState() => _PostAdScreenState();
}

class _PostAdScreenState extends ConsumerState<PostAdScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _startBidCtrl = TextEditingController();
  final _minBidStepCtrl = TextEditingController(text: '100');
  final _buyItNowCtrl = TextEditingController();
  String? _selectedCategory;
  String? _selectedProvinceId;
  String? _selectedDistrictId;
  bool _isFixedPrice = false;
  bool _showPhone = false;
  int? _selectedDurationDays = 30; // 30 is default, null means Custom
  DateTime? _customExpiresAt;
  List<File> _images = [];
  bool _loading = false;
  final _picker = ImagePicker();

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

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() => _images = picked.map((x) => File(x.path)).toList());
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty ||
        _descCtrl.text.isEmpty ||
        _priceCtrl.text.isEmpty ||
        _selectedCategory == null ||
        _selectedProvinceId == null ||
        _selectedDistrictId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen tüm alanları doldurun.')));
      return;
    }
    setState(() => _loading = true);
    try {
      // Upload images first
      final imageUrls = <String>[];
      for (final file in _images) {
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path,
              filename: file.path.split('/').last),
        });
        final res = await ApiClient().uploadFile(Endpoints.upload, form);
        imageUrls.add(res.data['url'] as String);
      }

      final pStr = _priceCtrl.text
          .replaceAll('₺', '')
          .replaceAll(' ', '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final sStr = _startBidCtrl.text
          .replaceAll('₺', '')
          .replaceAll(' ', '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final mStr = _minBidStepCtrl.text
          .replaceAll('₺', '')
          .replaceAll(' ', '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final bStr = _buyItNowCtrl.text
          .replaceAll('₺', '')
          .replaceAll(' ', '')
          .replaceAll('.', '')
          .replaceAll(',', '.');

      // Create ad
      await ApiClient().post(Endpoints.ads, data: {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': double.parse(pStr),
        'isFixedPrice': _isFixedPrice,
        'showPhone': _showPhone,
        'startingBid': _isFixedPrice
            ? null
            : (_startBidCtrl.text.isEmpty ? null : double.parse(sStr)),
        'minBidStep': _isFixedPrice || _minBidStepCtrl.text.isEmpty
            ? 100
            : double.parse(mStr),
        'buyItNowPrice': _isFixedPrice || _buyItNowCtrl.text.isEmpty
            ? null
            : double.parse(bStr),
        'durationDays': _selectedDurationDays,
        'customExpiresAt': _selectedDurationDays == null && _customExpiresAt != null
            ? _customExpiresAt!.toIso8601String()
            : null,
        'categorySlug': _selectedCategory,
        'provinceId': _selectedProvinceId,
        'districtId': _selectedDistrictId, // true district mapped
        'images': imageUrls,
      });

      ref.invalidate(myAdsProvider);
      ref.invalidate(adsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('İlan yayınlandı! 🎉')));
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
          title: const Text('İlan Ver')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image picker
            GestureDetector(
              onTap: _pickImages,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: const Color(0xFFE2EBF0), style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFF4F7FA),
                ),
                child: _images.isEmpty
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: Color(0xFF9AAAB8), size: 36),
                          SizedBox(height: 8),
                          Text('Fotoğraf Ekle',
                              style: TextStyle(color: Color(0xFF9AAAB8))),
                        ],
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        itemCount: _images.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(_images[i],
                                width: 100, height: 120, fit: BoxFit.cover),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Başlık'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Açıklama'),
            ),
            const SizedBox(height: 12),
            // Category dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: _categories
                  .map((c) => DropdownMenuItem(
                      value: c['slug'], child: Text(c['name']!)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedProvinceId,
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
            // Ad Duration Component
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('İlan Yayında Kalma Süresi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDurationChip('1 Hafta', 7),
                          const SizedBox(width: 8),
                          _buildDurationChip('1 Ay', 30),
                          const SizedBox(width: 8),
                          _buildDurationChip('3 Ay', 90),
                          const SizedBox(width: 8),
                          _buildDurationChip('Özel', null),
                        ],
                      ),
                    ),
                    if (_selectedDurationDays == null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2EBF0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Text(
                              _customExpiresAt == null
                                ? 'Bir son kullanma tarihi seçin...'
                                : 'Bitiş: ${_customExpiresAt!.day}/${_customExpiresAt!.month}/${_customExpiresAt!.year}',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_month),
                                label: const Text('Tarih Seç'),
                                onPressed: () async {
                                  final selected = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now().add(const Duration(days: 1)),
                                    firstDate: DateTime.now().add(const Duration(days: 1)),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (selected != null) {
                                    setState(() {
                                      _customExpiresAt = selected;
                                    });
                                  }
                                },
                              ),
                            )
                          ],
                        ),
                      )
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Bid settings
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
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('🚀 Yayınla'),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(String label, int? value) {
    final isSelected = _selectedDurationDays == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF00B4CC).withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF00B4CC) : const Color(0xFF4A5568),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedDurationDays = value;
            if (value != null) {
              _customExpiresAt = null; // reset custom context
            }
          });
        }
      },
    );
  }
}
