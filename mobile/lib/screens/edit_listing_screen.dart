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
import '../ui_library/components/cards/teq_card.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/buttons/teq_button.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/overlays/teq_bottom_sheet.dart';
import '../utils/error_helper.dart';
import '../utils/snackbar_helper.dart';
import '../services/analytics_service.dart';
import '../services/cache_service.dart';
import '../services/captcha_service.dart';
import '../services/category_service.dart';
import '../services/state_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/localization_service.dart';
import '../utils/number_formatter.dart';
import '../core/media_constants.dart';
import '../services/media_compressor.dart';
import '../providers/compression_progress_provider.dart';

class EditListingScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> listing;
  const EditListingScreen({super.key, required this.listing});

  @override
  ConsumerState<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends ConsumerState<EditListingScreen> {
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
  int? _aiCreditsRemaining;
  final List<dynamic> _images = [];
  final _picker = ImagePicker();
  File? _video;
  String? _videoUploadUrl;
  bool _videoUploading = false;
  double _videoUploadProgress = 0.0;

  static const int _maxImages = 10;
  static const int _maxVideoDurationSecs = MediaConstants.listingVideoMaxSecs;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.listing['title'] ?? '';
    _descCtrl.text = widget.listing['description'] ?? '';
    _priceCtrl.text = (widget.listing['price'] ?? '').toString();

    if (widget.listing['image_urls'] != null) {
      try {
        final imgs = widget.listing['image_urls'] as List;
        _images.addAll(imgs.cast<String>());
      } catch (e) {
        debugPrint('Error loading images: $e');
      }
    } else if (widget.listing['image_url'] != null) {
      _images.add(widget.listing['image_url'] as String);
    }

    if (widget.listing['video_url'] != null) {
      _videoUploadUrl = widget.listing['video_url'];
    }

    CategoryService.getCategories().then((cats) {
      if (mounted) {
        setState(() {
          _categories = cats;
          final initialCat = widget.listing['category'];
          if (initialCat != null && cats.any((c) => c.$1 == initialCat)) {
            _selectedCategory = initialCat;
          } else if (cats.isNotEmpty) {
            _selectedCategory = cats.first.$1;
          }
        });
      }
    });
    StateService.getStates().then((c) {
      if (mounted) {
        setState(() {
          _cities = c;
          final initialCity = widget.listing['location'];
          if (initialCity != null && c.contains(initialCity)) {
            _selectedCity = initialCity;
          }
        });
      }
    });
    _loadProStatus();
  }

  Future<void> _loadProStatus() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final resp = await http
          .get(
            Uri.parse('$kBaseUrl/auth/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final isPro = data['is_premium'] == true;
        setState(() => _isPro = isPro);
      }
    } catch (_) {}
  }

  Future<void> _loadAiCredits() async {
    final credits = await AnalyticsService.getAiPriceCredits();
    if (!mounted) return;
    setState(
      () =>
          _aiCreditsRemaining = (credits?['remaining'] as num?)?.toInt() ?? 20,
    );
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
      TeqSnackBar.show(message: ref.read(localizationProvider).t('createNeedTitle'),
        type: TeqSnackBarType.warning,
      );
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final rawEf = widget.listing['extra_fields'];
      final ef = rawEf is Map ? Map<String, dynamic>.from(rawEf) : null;
      final result = await AnalyticsService.getPriceEstimate(
        title: title,
        description: desc,
        category: _selectedCategory ?? '',
        subcategory: widget.listing['subcategory'] as String? ?? '',
        city: _selectedCity ?? '',
        condition: widget.listing['condition'] as String? ?? '',
        extraFields: (ef != null && ef.isNotEmpty) ? ef : null,
        excludeListingId: widget.listing['id'] as int?,
      );
      if (!mounted) return;
      if (result == null) {
        TeqSnackBar.show(message: ref.read(localizationProvider).t('aiPriceError'),
          type: TeqSnackBarType.error,
        );
        return;
      }
      final tuciSpent = (result['tuci_spent'] as num?)?.toInt() ?? 0;
      if (tuciSpent > 0) {
        // TUCi harcandı — badge'i serverdan taze al
        CacheService.clearData('user_wallet_data');
        _loadAiCredits();
        TeqSnackBar.show(message: ref.read(localizationProvider).t('tuciSpent', {'count': tuciSpent.toString()}),
          type: TeqSnackBarType.info,
        );
      } else if (_aiCreditsRemaining != null && _aiCreditsRemaining! > 0) {
        setState(() => _aiCreditsRemaining = _aiCreditsRemaining! - 1);
      }
      _showPriceEstimateSheet(result);
    } on AiInsufficientTuciException catch (e) {
      if (!mounted) return;
      TeqSnackBar.show(message: e.detail, type: TeqSnackBarType.error);
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
      return TeqNumberFormatter.format(v, fieldKey: 'price', unit: '₺');
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
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: confidenceColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      confidenceLabel,
                      style: TextStyle(
                        color: confidenceColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
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
                      label: ref.read(localizationProvider).t('listingSuggestedStart'),
                      value: fmt(suggested),
                      accent: const Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PriceMetricCard(
                      icon: '🏆',
                      label: ref.read(localizationProvider).t('listingExpectedClose'),
                      value: fmt(estimated),
                      accent: const Color(0xFF22C55E),
                    ),
                  ),
                ],
              ),
              if (minClose != null && maxClose != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MiniStat(
                        label: ref.read(localizationProvider).t('listingLowest'),
                        value: fmt(minClose),
                        color: const Color(0xFFEF4444),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: const Color(0xFF334155),
                      ),
                      _MiniStat(
                        label: ref.read(localizationProvider).t('listingAverage'),
                        value: fmt(estimated),
                        color: const Color(0xFF94A3B8),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: const Color(0xFF334155),
                      ),
                      _MiniStat(
                        label: ref.read(localizationProvider).t('listingHighest'),
                        value: fmt(maxClose),
                        color: const Color(0xFF22C55E),
                      ),
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
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  ),
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
                      _priceCtrl.text = TeqNumberFormatter.format(intVal, fieldKey: 'price');
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Önerilen Fiyatı Uygula',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
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
    // T-HC-07: Kamera seçiminde izni önceden kontrol et
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        final loc = ref.read(localizationProvider);
        showPermissionDeniedDialog(
          context,
          title: loc.t('attachCameraPermission'),
          message: loc.t('permPermanentlyDenied'),
          openSettingsLabel: loc.t('permOpenSettings'),
          cancelLabel: loc.t('btnCancel'),
        );
        return;
      }
    }
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
          TeqSnackBar.show(message: ref.read(localizationProvider).t('videoTooLong', {'max': _maxVideoDurationSecs.toString(), 'actual': dur.inSeconds.toString()}),
            type: TeqSnackBarType.warning,
          );
        }
        return;
      }
    }

    setState(() {
      _video = file;
      _videoUploadUrl = null;
      _videoUploading = true;
      _videoUploadProgress = 0.0;
    });
    try {
      // Aşama 1: sıkıştır
      ref.read(compressionProgressProvider.notifier).state = 0.0;
      final compressed = await MediaCompressor.compress(
        picked.path,
        MediaCompressType.listingVideo,
        targetDurationMs: _maxVideoDurationSecs * 1000,
        onProgress: (p) {
          ref.read(compressionProgressProvider.notifier).state = p;
        },
      );
      ref.read(compressionProgressProvider.notifier).state = null;
      if (!mounted) return;

      // Aşama 2: yükle
      final result = await UploadService.uploadVideoBytes(
        compressed.bytes,
        onProgress: (p) {
          if (mounted) setState(() => _videoUploadProgress = p);
        },
      );
      if (mounted) setState(() => _videoUploadUrl = result.videoUrl);
    } on MediaCompressCancelledException {
      if (mounted) _removeVideo();
    } catch (e) {
      if (mounted) {
        handleError(e, ref.read(localizationProvider));
        _removeVideo();
        return;
      }
    } finally {
      ref.read(compressionProgressProvider.notifier).state = null;
      if (mounted) setState(() {
        _videoUploading = false;
        _videoUploadProgress = 0.0;
      });
    }
  }

  void _removeVideo() {
    setState(() {
      _video = null;
      _videoUploadUrl = null;
      _videoUploading = false;
      _videoUploadProgress = 0.0;
    });
  }

  void _showVideoSourceSheet() {
    final loc = ref.read(localizationProvider);
    TeqBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(loc.t('profilePickGallery')),
            onTap: () {
              Navigator.pop(context);
              _pickVideo(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(loc.t('createPickCamera', {'sec': _maxVideoDurationSecs.toString()})),
            onTap: () {
              Navigator.pop(context);
              _pickVideo(ImageSource.camera);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickImages(ImageSource source) async {
    if (_images.length >= _maxImages) {
      final loc = ref.read(localizationProvider);
      TeqSnackBar.show(message: loc.t('listingMaxPhotos'),
        type: TeqSnackBarType.warning,
      );
      return;
    }
    // T-HC-07: Kamera seçiminde izni önceden kontrol et
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        final loc = ref.read(localizationProvider);
        showPermissionDeniedDialog(
          context,
          title: loc.t('attachCameraPermission'),
          message: loc.t('permPermanentlyDenied'),
          openSettingsLabel: loc.t('permOpenSettings'),
          cancelLabel: loc.t('btnCancel'),
        );
        return;
      }
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
    final loc = ref.read(localizationProvider);
    TeqBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(loc.t('btnPickGallery')),
            onTap: () {
              Navigator.pop(context);
              _pickImages(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text(loc.t('btnCamera')),
            onTap: () {
              Navigator.pop(context);
              _pickImages(ImageSource.camera);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_videoUploading) {
      TeqSnackBar.show(message: ref.read(localizationProvider).t('videoUploading'),
        type: TeqSnackBarType.info,
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
          if (img is String) {
            imageUrls.add(img);
          } else if (img is File) {
            final compressed = await MediaCompressor.compress(img.path, MediaCompressType.listingPhoto);
            final result = await UploadService.uploadBytes(
              Uint8List.fromList(compressed.bytes),
              'listing_photo.jpg',
            );
            imageUrls.add(result.url);
            thumbnailUrl ??= result.thumbUrl;
          }
        } catch (e) {
          debugPrint('UPLOAD EXCEPTION: $e');
          if (mounted) {
            final loc = ref.read(localizationProvider);
            TeqSnackBar.show(message: loc.t('createListingPhotoUploadFailed', {'error': e.toString()}),
              type: TeqSnackBarType.error,
            );
          }
        }
      }

      // Güvenlik doğrulaması: görünmez Turnstile challenge
      if (!mounted) return;
      final captchaToken = await CaptchaService.getToken();
      if (!mounted) return;

      await apiCall(
        () async => http.put(
          Uri.parse('$kBaseUrl/listings/${widget.listing['id']}'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
            if (captchaToken != null && captchaToken.isNotEmpty)
              'X-Captcha-Token': captchaToken,
          },
          body: jsonEncode({
            'title': _titleCtrl.text.trim(),
            'description': _descCtrl.text.trim(),
            'price': TeqNumberFormatter.parse(_priceCtrl.text.trim())?.toDouble(),
            'category': _selectedCategory,
            if (_selectedCity != null && _selectedCity!.isNotEmpty)
              'location': _selectedCity,
            'image_urls': imageUrls,
            if (imageUrls.isNotEmpty) 'image_url': imageUrls.first,
            'thumbnail_url': ?thumbnailUrl,
            'video_url': _videoUploadUrl,
          }),
        ),
      );

      if (!mounted) return;
      final loc = ref.read(localizationProvider);
      TeqSnackBar.show(message: loc.t('msgListingPublished'),
        type: TeqSnackBarType.success,
      );
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      TeqSnackBar.show(message: _mapError(e),
        type: TeqSnackBarType.error,
      );
    } catch (_) {
      if (mounted) {
        final loc = ref.read(localizationProvider);
        TeqSnackBar.show(message: loc.t('createListingConnError'),
          type: TeqSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 403/429 hata kodlarını kullanıcı dostu mesaja çevirir.
  String _mapError(AppException e) {
    final loc = ref.read(localizationProvider);
    if (e.statusCode == 403 || e.code == 'FORBIDDEN') {
      return loc.t('errorCaptchaFailed');
    }
    if (e.statusCode == 429 || e.code == 'RATE_LIMIT_EXCEEDED') {
      return loc.t('errorTooFast');
    }
    if (e.code == 'CONTENT_POLICY_VIOLATION') {
      return loc.t('errorContentPolicy');
    }
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(loc.t('btnUpdate'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo picker section
              TeqCard(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          loc.t('createListingPhotoCount', {'count': _images.length.toString(), 'max': _maxImages.toString()}),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (_images.length < _maxImages)
                          TextButton.icon(
                            key: const Key('create_listing_btn_fotograf_ekle'),
                            onPressed: _showImageSourceSheet,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 18,
                            ),
                            label: Text(loc.t('btnAdd')),
                          ),
                      ],
                    ),
                    if (_images.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              _images.length +
                              (_images.length < _maxImages ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (ctx, i) {
                            if (i == _images.length) {
                              // Add button at end
                              return Builder(
                                builder: (context) => GestureDetector(
                                  onTap: _showImageSourceSheet,
                                  child: Container(
                                    width: 90,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.border(context),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.add,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ),
                              );
                            }
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _images[i] is String
                                      ? Image.network(
                                          imgUrl(_images[i] as String),
                                          width: 90,
                                          height: 90,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          _images[i] as File,
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
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                if (i == 0)
                                  Positioned(
                                    bottom: 2,
                                    left: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: kPrimary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        loc.t('photoCover'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                      ),
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
                        key: const Key(
                          'create_listing_gesture_fotograf_ekle_bos',
                        ),
                        onTap: _showImageSourceSheet,
                        child: Builder(
                          builder: (context) => Container(
                            height: 90,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.border(context),
                                style: BorderStyle.solid,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: AppColors.surfaceVariant(context),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_outlined,
                                    color: AppColors.textSecondary(context),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    loc.t('btnAddPhoto'),
                                    style: TextStyle(
                                      color: AppColors.textSecondary(context),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Video section
              TeqCard(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          loc.t('videoLabel', {'sec': _maxVideoDurationSecs.toString()}),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (_video == null &&
                            _videoUploadUrl == null &&
                            !_videoUploading)
                          TextButton.icon(
                            onPressed: _showVideoSourceSheet,
                            icon: const Icon(Icons.videocam_outlined, size: 18),
                            label: Text(loc.t('btnAdd')),
                          ),
                      ],
                    ),
                    if (_video != null || _videoUploadUrl != null) ...[
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _videoUploading
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${(_videoUploadProgress * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      LinearProgressIndicator(
                                        value: _videoUploadProgress,
                                        minHeight: 3,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ],
                                  )
                                : Text(
                                    loc.t('lblVideoReady'),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                          ),
                          GestureDetector(
                            onTap: _removeVideo,
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TeqCard(
                child: Column(
                  children: [
                    TeqTextField(
                      key: const Key('create_listing_input_baslik'),
                      controller: _titleCtrl,
                      labelText: loc.t('fieldListingTitle'),
                      hintText: loc.t('fieldListingTitleHint'),
                      validator: (v) => v == null || v.isEmpty
                          ? loc.t('fieldListingTitleHint')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: const Key('create_listing_select_kategori'),
                      // ignore: deprecated_member_use
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: loc.t('fieldCategory'),
                        hintText: loc.t('fieldCategoryHint'),
                      ),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.$1,
                              child: Text(c.$2),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(
                        () => _selectedCategory = v ?? _selectedCategory,
                      ),
                      validator: (v) => v == null ? loc.t('fieldCategoryHint') : null,
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      key: const Key('create_listing_input_fiyat'),
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [const TeqNumericInputFormatter(fieldKey: 'price')],
                      labelText: loc.t('fieldPrice'),
                      hintText: loc.t('fieldPriceHint'),
                      prefixText: '₺ ',
                      validator: (v) =>
                          v == null || v.isEmpty ? loc.t('fieldPriceHint') : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: const Key('create_listing_select_konum'),
                      // ignore: deprecated_member_use
                      value: _selectedCity,
                      decoration: InputDecoration(labelText: loc.t('fieldLocation')),
                      hint: Text(loc.t('fieldLocationHint')),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text('-- ${loc.t('fieldLocationHint')} --'),
                        ),
                        ..._cities.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedCity = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TeqCard(
                child: Column(
                  children: [
                    TeqTextField(
                      key: const Key('create_listing_input_aciklama'),
                      controller: _descCtrl,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      labelText: loc.t('fieldDescription'),
                      hintText: loc.t('fieldDescriptionHint'),
                      validator: (v) => v == null || v.isEmpty
                          ? loc.t('fieldDescriptionHint')
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TeqButton(
                  key: const Key('create_listing_btn_yayinla'),
                  onPressed: _submitting ? null : _submit,
                  text: loc.t('btnUpdateListing'),
                  isLoading: _submitting,
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

// ── AI Fiyat Butonu ──────────────────────────────────────────────────────────

class _AiPriceButton extends StatelessWidget {
  final bool loading;
  final bool isPro;
  final int? creditsRemaining;
  final VoidCallback onTap;
  const _AiPriceButton({
    required this.loading,
    required this.isPro,
    required this.onTap,
    this.creditsRemaining,
  });

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
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]
              : [
                  const Text('✨', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Yapay Zeka ile Fiyat Belirle',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPro) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 10,
                            color:
                                (creditsRemaining == null ||
                                    creditsRemaining! > 0)
                                ? const Color(0xFF34D399)
                                : const Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            creditsRemaining == null || creditsRemaining! > 0
                                ? '${creditsRemaining ?? '…'} hak kaldı'
                                : '5 TUCi',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color:
                                  (creditsRemaining == null ||
                                      creditsRemaining! > 0)
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFFF59E0B),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
    return TeqCard(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1E293B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
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
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
