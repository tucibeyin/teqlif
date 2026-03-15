import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/theme.dart';
import '../services/category_service.dart';
import '../services/storage_service.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  String? _selectedCategory;
  List<(String, String)> _categories = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    CategoryService.getCategories().then((cats) {
      if (mounted) {
        setState(() {
          _categories = cats;
          if (cats.isNotEmpty) _selectedCategory = cats.first.$1;
        });
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/listings'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'price': double.tryParse(_priceCtrl.text.trim()),
          'category': _selectedCategory,
          if (_locationCtrl.text.trim().isNotEmpty)
            'location': _locationCtrl.text.trim(),
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İlan yayına alındı!'),
            backgroundColor: kPrimary,
          ),
        );
        Navigator.pop(context, true);
      } else {
        final err = jsonDecode(resp.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err['detail'] ?? 'Bir hata oluştu')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı hatası')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('İlan Ver')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionCard(
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'İlan Başlığı'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Başlık giriniz' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedCategory = v ?? _selectedCategory),
                    validator: (v) => v == null ? 'Kategori seçiniz' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Fiyat',
                      prefixText: '₺ ',
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Fiyat giriniz' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _locationCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Konum (isteğe bağlı)',
                      hintText: 'İstanbul, Ankara...',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                children: [
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      alignLabelWithHint: true,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Açıklama giriniz' : null,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('İlanı Yayınla'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}
