import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../core/app_exception.dart';
import '../services/analytics_service.dart';
import '../services/captcha_service.dart';
import '../services/category_service.dart';
import '../services/city_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../l10n/app_localizations.dart';

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
  String? _selectedCategory;
  String? _selectedCity;
  List<(String, String)> _categories = [];
  List<String> _cities = [];
  bool _submitting = false;
  bool _aiLoading = false;
  bool _isPro = false;
  final List<File> _images = [];
  final _picker = ImagePicker();
  File? _video;
  String? _videoUploadUrl;
  bool _videoUploading = false;

  static const int _maxImages = 10;
  static const int _maxVideoDurationSecs = 15;

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
    CityService.getCities().then((c) {
      if (mounted) setState(() => _cities = c);
    });
    _loadProStatus();
  }

  Future<void> _loadProStatus() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _isPro = data['is_premium'] == true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAiPriceEstimate() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce ilan başlığını giriniz.')),
      );
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final result = await AnalyticsService.getPriceEstimate(
        title: title,
        description: desc,
        category: _selectedCategory ?? '',
      );
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fiyat tahmini alınamadı. Lütfen tekrar deneyin.')),
        );
        return;
      }
      _showPriceEstimateSheet(result);
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  void _showPriceEstimateSheet(Map<String, dynamic> data) {
    final suggested = data['suggested_start_price'] as double?;
    final estimated = data['estimated_close_price'] as double?;
    final minClose = data['min_close_price'] as double?;
    final maxClose = data['max_close_price'] as double?;
    final advice = data['advice'] as String? ?? '';
    final confidence = data['confidence'] as String? ?? 'low';
    final foundSimilar = data['found_similar'] as int? ?? 0;

    String fmt(double? v) {
      if (v == null || v <= 0) return '—';
      return '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} ₺';
    }

    Color confidenceColor = confidence == 'high'
        ? const Color(0xFF22C55E)
        : confidence == 'medium'
            ? const Color(0xFFF59E0B)
            : const Color(0xFF64748B);

    String confidenceLabel = confidence == 'high'
        ? '● Yüksek güven'
        : confidence == 'medium'
            ? '● Orta güven'
            : '● Düşük güven';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.88,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('✨', style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Yapay Zeka Fiyat Tahmini',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '$foundSimilar benzer ürün analiz edildi',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: confidenceColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      confidenceLabel,
                      style: TextStyle(color: confidenceColor, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Metrik kartları
              Row(
                children: [
                  Expanded(
                    child: _PriceMetricCard(
                      icon: '🎯',
                      label: 'Önerilen Başlangıç',
                      value: fmt(suggested),
                      accent: const Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PriceMetricCard(
                      icon: '🏆',
                      label: 'Beklenen Kapanış',
                      value: fmt(estimated),
                      accent: const Color(0xFF22C55E),
                    ),
                  ),
                ],
              ),
              if (minClose != null && maxClose != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MiniStat(label: 'En Düşük', value: fmt(minClose), color: const Color(0xFFEF4444)),
                      Container(width: 1, height: 32, color: const Color(0xFF334155)),
                      _MiniStat(label: 'Ortalama', value: fmt(estimated), color: const Color(0xFF94A3B8)),
                      Container(width: 1, height: 32, color: const Color(0xFF334155)),
                      _MiniStat(label: 'En Yüksek', value: fmt(maxClose), color: const Color(0xFF22C55E)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // Tavsiye metni
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        advice,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Uygula butonu
              if (suggested != null && suggested > 0)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final intVal = suggested.toInt();
                      final formatted = intVal.toString().replaceAllMapped(
                        RegExp(r'(\d)(?=(\d{3})+$)'),
                        (m) => '${m[1]}.',
                      );
                      _priceCtrl.text = formatted;
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Önerilen Fiyatı Uygula',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickVideo(ImageSource source) async {
    XFile? picked;
    if (source == ImageSource.camera) {
      picked = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: _maxVideoDurationSecs),
      );
    } else {
      picked = await _picker.pickVideo(source: ImageSource.gallery);
    }
    if (picked == null || !mounted) return;

    final file = File(picked.path);

    // Galeri seçiminde süre kontrolü
    if (source == ImageSource.gallery) {
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      final dur = ctrl.value.duration;
      await ctrl.dispose();
      if (dur.inSeconds > _maxVideoDurationSecs) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Video $_maxVideoDurationSecs saniyeyi geçemez (${dur.inSeconds}s).')),
          );
        }
        return;
      }
    }

    setState(() {
      _video = file;
      _videoUploadUrl = null;
    });

    // Arka planda yükle
    setState(() => _videoUploading = true);
    try {
      final result = await UploadService.uploadVideo(file);
      if (mounted) setState(() => _videoUploadUrl = result.videoUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video yüklenemedi: $e')),
        );
        _removeVideo();
        return;
      }
    } finally {
      if (mounted) setState(() => _videoUploading = false);
    }
  }

  void _removeVideo() {
    setState(() {
      _video = null;
      _videoUploadUrl = null;
      _videoUploading = false;
    });
  }

  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Kamera ile çek (maks 15 sn)'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages(ImageSource source) async {
    if (_images.length >= _maxImages) {
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.listingMaxPhotos)),
      );
      return;
    }
    if (source == ImageSource.gallery) {
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (picked.isEmpty) return;
      final remaining = _maxImages - _images.length;
      final toAdd = picked.take(remaining).map((x) => File(x.path)).toList();
      setState(() => _images.addAll(toAdd));
    } else {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (picked == null) return;
      setState(() => _images.add(File(picked.path)));
    }
  }

  void _showImageSourceSheet() {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.btnPickGallery),
              onTap: () {
                Navigator.pop(context);
                _pickImages(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(l.btnCamera),
              onTap: () {
                Navigator.pop(context);
                _pickImages(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_videoUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video henüz yükleniyor, lütfen bekleyin.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await StorageService.getToken();

      // Upload images and collect URLs + first thumbnail
      final List<String> imageUrls = [];
      String? thumbnailUrl;
      for (final img in _images) {
        try {
          final result = await UploadService.uploadFile(img);
          imageUrls.add(result.url);
          // İlk fotoğrafın thumb'ını thumbnail olarak kullan
          thumbnailUrl ??= result.thumbUrl;
        } catch (e) {
          debugPrint('UPLOAD EXCEPTION: $e');
          if (mounted) {
            final l = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.createListingPhotoUploadFailed(e.toString()))),
            );
          }
        }
      }

      // Güvenlik doğrulaması: görünmez Turnstile challenge
      if (!mounted) return;
      final captchaToken = await CaptchaService.getToken();
      if (!mounted) return;

      await apiCall(
        () async => http.post(
          Uri.parse('$kBaseUrl/listings'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
            if (captchaToken != null && captchaToken.isNotEmpty)
              'X-Captcha-Token': captchaToken,
          },
          body: jsonEncode({
            'title': _titleCtrl.text.trim(),
            'description': _descCtrl.text.trim(),
            'price': double.tryParse(
              _priceCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.'),
            ),
            'category': _selectedCategory,
            if (_selectedCity != null && _selectedCity!.isNotEmpty)
              'location': _selectedCity,
            'image_urls': imageUrls,
            if (imageUrls.isNotEmpty) 'image_url': imageUrls.first,
            if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
            if (_videoUploadUrl != null) 'video_url': _videoUploadUrl,
          }),
        ),
      );

      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.msgListingPublished),
          backgroundColor: kPrimary,
        ),
      );
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapError(e))),
      );
    } catch (_) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.createListingConnError)),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 403/429 hata kodlarını kullanıcı dostu mesaja çevirir.
  String _mapError(AppException e) {
    final l = AppLocalizations.of(context)!;
    if (e.statusCode == 403 || e.code == 'FORBIDDEN') {
      return l.errorCaptchaFailed;
    }
    if (e.statusCode == 429 || e.code == 'RATE_LIMIT_EXCEEDED') {
      return l.errorTooFast;
    }
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.btnCreateListing)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo picker section
              _SectionCard(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l.createListingPhotoCount(_images.length, _maxImages),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      if (_images.length < _maxImages)
                        TextButton.icon(
                          key: const Key('create_listing_btn_fotograf_ekle'),
                          onPressed: _showImageSourceSheet,
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 18),
                          label: Text(l.btnAdd),
                        ),
                    ],
                  ),
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length + (_images.length < _maxImages ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx, i) {
                          if (i == _images.length) {
                            // Add button at end
                            return Builder(
                              builder: (context) => GestureDetector(
                              onTap: _showImageSourceSheet,
                              child: Container(
                                width: 90,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border(context)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.add, color: AppColors.textSecondary(context)),
                              ),
                            ));
                          }
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _images[i],
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _images.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 14),
                                  ),
                                ),
                              ),
                              if (i == 0)
                                Positioned(
                                  bottom: 2,
                                  left: 2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: kPrimary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(l.photoCover,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 10)),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      key: const Key('create_listing_gesture_fotograf_ekle_bos'),
                      onTap: _showImageSourceSheet,
                      child: Builder(
                        builder: (context) => Container(
                        height: 90,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: AppColors.border(context),
                              style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.surfaceVariant(context),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  color: AppColors.textSecondary(context), size: 28),
                              const SizedBox(height: 4),
                              Text(l.btnAddPhoto,
                                  style: TextStyle(
                                      color: AppColors.textSecondary(context), fontSize: 12)),
                            ],
                          ),
                        ),
                      ),),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Video section
              _SectionCard(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Video (maks 15 sn)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      if (_video == null && !_videoUploading)
                        TextButton.icon(
                          onPressed: _showVideoSourceSheet,
                          icon: const Icon(Icons.videocam_outlined, size: 18),
                          label: const Text('Ekle'),
                        ),
                    ],
                  ),
                  if (_video != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: _videoUploading
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _videoUploading ? 'Yükleniyor...' : 'Video hazır',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        GestureDetector(
                          onTap: _removeVideo,
                          child: const Icon(Icons.close, size: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                children: [
                  TextFormField(
                    key: const Key('create_listing_input_baslik'),
                    controller: _titleCtrl,
                    decoration: InputDecoration(labelText: l.fieldListingTitle, hintText: l.fieldListingTitleHint),
                    validator: (v) =>
                        v == null || v.isEmpty ? l.fieldListingTitleHint : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const Key('create_listing_select_kategori'),
                    value: _selectedCategory,
                    decoration: InputDecoration(labelText: l.fieldCategory, hintText: l.fieldCategoryHint),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedCategory = v ?? _selectedCategory),
                    validator: (v) => v == null ? l.fieldCategoryHint : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('create_listing_input_fiyat'),
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ThousandSeparatorFormatter()],
                    decoration: InputDecoration(
                      labelText: l.fieldPrice,
                      hintText: l.fieldPriceHint,
                      prefixText: '₺ ',
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? l.fieldPriceHint : null,
                  ),
                  const SizedBox(height: 10),
                  _AiPriceButton(
                    loading: _aiLoading,
                    onTap: _fetchAiPriceEstimate,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const Key('create_listing_select_konum'),
                    value: _selectedCity,
                    decoration: InputDecoration(labelText: l.fieldLocation),
                    hint: Text(l.fieldLocationHint),
                    items: [
                      DropdownMenuItem(value: null, child: Text('-- ${l.fieldLocationHint} --')),
                      ..._cities.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (v) => setState(() => _selectedCity = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                children: [
                  TextFormField(
                    key: const Key('create_listing_input_aciklama'),
                    controller: _descCtrl,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      labelText: l.fieldDescription,
                      hintText: l.fieldDescriptionHint,
                      alignLabelWithHint: true,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? l.fieldDescriptionHint : null,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('create_listing_btn_yayinla'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l.btnPublishListing),
                            const SizedBox(height: 3),
                            _isPro
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.workspace_premium_rounded,
                                            size: 11, color: Color(0xFF34D399)),
                                        SizedBox(width: 3),
                                        Text(
                                          'Pro · Ücretsiz',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF34D399),
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Text(
                                          '1 TUCi',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFFBBF24),
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ],
                        ),
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

class _ThousandSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('.', '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final formatted = _addDots(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _addDots(String digits) {
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}

// ── AI Fiyat Butonu ──────────────────────────────────────────────────────────

class _AiPriceButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _AiPriceButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          gradient: loading
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: loading ? const Color(0xFF1E293B) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: loading
                ? const Color(0xFF334155)
                : const Color(0xFF6366F1).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: loading
              ? [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF6366F1)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Analiz ediliyor…',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ]
              : [
                  const Text('✨', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  const Text(
                    'Yapay Zeka ile Fiyat Belirle',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}

// ── AI Fiyat Metrik Kartı ─────────────────────────────────────────────────────

class _PriceMetricCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color accent;
  const _PriceMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
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
