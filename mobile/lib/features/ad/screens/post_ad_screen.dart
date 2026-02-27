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
import '../../../core/constants/categories.dart';

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
  // Dinamik N-katmanlı kategori seçimi
  List<String> _selectedPath = [];
  String? _selectedProvinceId;
  String? _selectedDistrictId;
  bool _isFixedPrice = false;
  bool _showPhone = false;
  int? _selectedDurationDays = 30; // 30 is default, null means Custom
  DateTime? _customExpiresAt;
  List<File> _images = [];
  bool _loading = false;
  final _picker = ImagePicker();

  // Hesaplanan yardımcılar
  List<CategoryNode> _childrenAt(int level) {
    if (level == 0) return categoryTree;
    final slug = _selectedPath[level - 1];
    return findNode(slug)?.children ?? [];
  }
  CategoryNode? get _lastNode => _selectedPath.isEmpty
      ? null
      : findNode(_selectedPath.last);
  String? get _effectiveLeafSlug =>
      (_lastNode?.isLeaf ?? false) ? _selectedPath.last : null;

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

  void _showSearchableSheet(
    String title,
    List<CategoryNode> options,
    void Function(String slug) onSelected,
  ) {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = query.isEmpty
              ? options
              : options
                  .where((o) =>
                      o.name.toLowerCase().contains(query.toLowerCase()))
                  .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '$title ara...',
                      prefixIcon: const Icon(Icons.search),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setSheetState(() => query = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final o = filtered[i];
                      final label = o.icon.isNotEmpty
                          ? '${o.icon} ${o.name}'
                          : o.name;
                      return ListTile(
                        title: Text(label),
                        onTap: () {
                          Navigator.pop(ctx);
                          onSelected(o.slug);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showImageSourceSheet() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Fotoğraf Ekle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00B4CC)),
              title: const Text('Galeriden Seç'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await _picker.pickMultiImage(imageQuality: 80);
                if (picked.isNotEmpty) {
                  setState(() {
                    final remaining = 10 - _images.length;
                    _images.addAll(picked.take(remaining).map((x) => File(x.path)));
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF00B4CC)),
              title: const Text('Kamerayla Çek'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                if (picked != null && _images.length < 10) {
                  setState(() => _images.add(File(picked.path)));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty ||
        _descCtrl.text.isEmpty ||
        _priceCtrl.text.isEmpty ||
        (_effectiveLeafSlug == null) ||
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
        'categorySlug': _effectiveLeafSlug,
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
              onTap: _showImageSourceSheet,
              child: Container(
                height: 140,
                 decoration: BoxDecoration(
                   border: Border.all(
                       color: const Color(0xFFE2EBF0), style: BorderStyle.solid),
                   borderRadius: BorderRadius.circular(12),
                   color: const Color(0xFFF4F7FA),
                 ),
                 child: ListView.builder(
                         scrollDirection: Axis.horizontal,
                         padding: const EdgeInsets.all(8),
                         // Extra slot for the "add" button if under limit
                         itemCount: _images.length + (_images.length < 10 ? 1 : 0),
                         itemBuilder: (_, i) {
                           // "Add more" button as last item
                           if (i == _images.length) {
                             return Padding(
                               padding: const EdgeInsets.only(right: 8),
                               child: GestureDetector(
                                 onTap: _showImageSourceSheet,
                                 child: Container(
                                   width: 100,
                                   height: 120,
                                   decoration: BoxDecoration(
                                     color: const Color(0xFFE6F9FC),
                                     borderRadius: BorderRadius.circular(8),
                                     border: Border.all(
                                         color: const Color(0xFF00B4CC),
                                         style: BorderStyle.solid),
                                   ),
                                   child: Column(
                                     mainAxisAlignment: MainAxisAlignment.center,
                                     children: [
                                       const Icon(Icons.add_photo_alternate_outlined,
                                           color: Color(0xFF00B4CC), size: 30),
                                       const SizedBox(height: 4),
                                       Text(
                                         '${_images.length}/10',
                                         style: const TextStyle(
                                             color: Color(0xFF00B4CC),
                                             fontSize: 12,
                                             fontWeight: FontWeight.w600),
                                       ),
                                     ],
                                   ),
                                 ),
                               ),
                             );
                           }
                           return Padding(
                             padding: const EdgeInsets.only(right: 8),
                             child: Stack(
                               children: [
                                 ClipRRect(
                                   borderRadius: BorderRadius.circular(8),
                                   child: Image.file(_images[i],
                                       width: 100, height: 120, fit: BoxFit.cover),
                                 ),
                                 Positioned(
                                   top: 4,
                                   right: 4,
                                   child: GestureDetector(
                                     onTap: () {
                                       setState(() => _images.removeAt(i));
                                     },
                                     child: Container(
                                       padding: const EdgeInsets.all(4),
                                       decoration: const BoxDecoration(
                                         color: Colors.black54,
                                         shape: BoxShape.circle,
                                       ),
                                       child: const Icon(Icons.close,
                                           size: 16, color: Colors.white),
                                     ),
                                   ),
                                 ),
                               ],
                             ),
                           );
                         },
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
            // ── N-Katmanlı Kategori Seçimi ──
            ...List.generate(_selectedPath.length + 1, (level) {
              final opts = _childrenAt(level);
              if (opts.isEmpty) return const SizedBox.shrink();
              const labels = [
                'Ana Kategori',
                'Alt Kategori',
                'Marka',
                'Model',
                'Motor / Versiyon',
                'Donanım',
              ];
              final label = level < labels.length ? labels[level] : 'Seçiniz';
              final currentVal =
                  level < _selectedPath.length ? _selectedPath[level] : null;
              final currentNode = currentVal != null ? findNode(currentVal) : null;
              final displayText = currentNode != null
                  ? (currentNode.icon.isNotEmpty
                      ? '${currentNode.icon} ${currentNode.name}'
                      : currentNode.name)
                  : null;

              // If many options, open a searchable bottom sheet
              if (opts.length > 10) {
                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => _showSearchableSheet(label, opts, (slug) {
                        setState(() {
                          _selectedPath = [..._selectedPath.sublist(0, level), slug];
                        });
                      }),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFCCDDE3)),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayText ?? label,
                                style: TextStyle(
                                  color: displayText != null
                                      ? Colors.black87
                                      : const Color(0xFF90A4AE),
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.search, color: Color(0xFF00B4CC), size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              }

              // Few options: use dropdown
              return Column(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: currentVal,
                    decoration: InputDecoration(labelText: label),
                    items: opts
                        .map((o) => DropdownMenuItem(
                            value: o.slug,
                            child: Text(
                              o.icon.isNotEmpty ? '${o.icon} ${o.name}' : o.name,
                              overflow: TextOverflow.ellipsis,
                            )))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedPath = [..._selectedPath.sublist(0, level), v];
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }),
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
