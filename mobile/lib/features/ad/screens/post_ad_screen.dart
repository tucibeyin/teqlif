import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../dashboard/screens/dashboard_screen.dart';

// Locations data - province list
const _provinces = [
  {'id': '34', 'name': 'İstanbul'},
  {'id': '6', 'name': 'Ankara'},
  {'id': '35', 'name': 'İzmir'},
  {'id': '7', 'name': 'Antalya'},
  {'id': '16', 'name': 'Bursa'},
  {'id': '1', 'name': 'Adana'},
  {'id': '42', 'name': 'Konya'},
  {'id': '55', 'name': 'Samsun'},
  {'id': '61', 'name': 'Trabzon'},
  {'id': '27', 'name': 'Gaziantep'},
];

const _categories = [
  {'slug': 'elektronik', 'name': 'Elektronik'},
  {'slug': 'mobilya', 'name': 'Mobilya'},
  {'slug': 'giyim', 'name': 'Giyim'},
  {'slug': 'arac', 'name': 'Araç'},
  {'slug': 'ev-esyasi', 'name': 'Ev Eşyası'},
  {'slug': 'spor', 'name': 'Spor'},
  {'slug': 'kitap', 'name': 'Kitap'},
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
  String? _selectedCategory;
  String? _selectedProvinceId;
  bool _freeBid = false;
  List<File> _images = [];
  bool _loading = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _startBidCtrl.dispose();
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
        _selectedProvinceId == null) {
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

      // Create ad
      await ApiClient().post(Endpoints.ads, data: {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text),
        'startingBid': _freeBid
            ? null
            : (_startBidCtrl.text.isEmpty
                ? null
                : double.parse(_startBidCtrl.text)),
        'categorySlug': _selectedCategory,
        'provinceId': _selectedProvinceId,
        'districtId': _selectedProvinceId, // simplified: using same as province
        'images': imageUrls,
      });

      ref.invalidate(myAdsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İlan yayınlandı! 🎉')));
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
      appBar: AppBar(title: const Text('İlan Ver')),
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
                              style:
                                  TextStyle(color: Color(0xFF9AAAB8))),
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
                                width: 100,
                                height: 120,
                                fit: BoxFit.cover),
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
              value: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: _categories
                  .map((c) => DropdownMenuItem(
                      value: c['slug'], child: Text(c['name']!)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedProvinceId,
              decoration: const InputDecoration(labelText: 'Şehir'),
              items: _provinces
                  .map((p) => DropdownMenuItem(
                      value: p['id'], child: Text(p['name']!)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedProvinceId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Piyasa Değeri (₺)',
                  prefixIcon: Icon(Icons.monetization_on_outlined)),
            ),
            const SizedBox(height: 12),
            // Bid settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _freeBid,
                      onChanged: (v) => setState(() => _freeBid = v),
                      title: const Text('🔥 Serbest Teklif (1 ₺\'den başlar)'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (!_freeBid)
                      TextField(
                        controller: _startBidCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Minimum Açılış Teklifi (₺)'),
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
}
