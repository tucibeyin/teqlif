import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../core/app_exception.dart';
import '../services/analytics_service.dart';
import '../services/cache_service.dart';
import '../services/captcha_service.dart';
import '../services/category_service.dart';
import '../services/city_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/error_helper.dart';

import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/cards/teq_card.dart';
import '../ui_library/components/buttons/teq_button.dart';

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
  bool _aiDescLoading = false;
  bool _isPro = false;
  String? _selectedCondition;
  int? _aiCreditsRemaining;
  int? _aiDescCreditsRemaining;
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
    _titleCtrl.addListener(() => setState(() {}));
    AnalyticsService.trackEvent('listing_create_start', {});
    SharedPreferences.getInstance().then((prefs) {
      final locale = prefs.getString('app_locale_language_code') ?? 'tr';
      CategoryService.getCategories(locale: locale).then((cats) {
        if (mounted) {
          setState(() {
            _categories = cats;
            if (cats.isNotEmpty) _selectedCategory = cats.first.$1;
          });
        }
      });
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
        if (isPro) {
          _loadAiCredits();
          _loadAiDescCredits();
        }
      }
    } catch (_) {}
  }

  Future<void> _loadAiCredits() async {
    final credits = await AnalyticsService.getAiPriceCredits();
    if (!mounted) return;
    setState(() => _aiCreditsRemaining = (credits?['remaining'] as num?)?.toInt() ?? 20);
  }

  Future<void> _loadAiDescCredits() async {
    final credits = await AnalyticsService.getAiDescCredits();
    if (!mounted) return;
    setState(() => _aiDescCreditsRemaining = (credits?['remaining'] as num?)?.toInt() ?? 6);
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
      TeqSnackBar.show(
        context,
        message: AppLocalizations.of(context)!.createNeedTitle,
        type: TeqSnackBarType.warning,
      );
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final result = await AnalyticsService.getPriceEstimate(
        title: title,
        description: desc,
        category: _selectedCategory ?? '',
        city: _selectedCity ?? '',
      );
      if (!mounted) return;
      if (result == null) {
        TeqSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.aiPriceError,
          type: TeqSnackBarType.error,
        );
        return;
      }
      final tuciSpent = (result['tuci_spent'] as num?)?.toInt() ?? 0;
      if (tuciSpent > 0) {
        // TUCi harcandı — badge'i serverdan taze al
        CacheService.clearData('user_wallet_data');
        _loadAiCredits();
        TeqSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.tuciSpent(tuciSpent),
          type: TeqSnackBarType.success,
        );
      } else if (_aiCreditsRemaining != null && _aiCreditsRemaining! > 0) {
        setState(() => _aiCreditsRemaining = _aiCreditsRemaining! - 1);
      }
      _showPriceEstimateSheet(result);
    } on AiInsufficientTuciException catch (e) {
      if (!mounted) return;
      TeqSnackBar.show(context, message: e.detail, type: TeqSnackBarType.error);
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _fetchAiDescription() async {
    final title = _titleCtrl.text.trim();
    final l = AppLocalizations.of(context)!;
    if (title.isEmpty || _selectedCategory == null) {
      TeqSnackBar.show(context, message: l.createNeedTitle, type: TeqSnackBarType.warning);
      return;
    }
    setState(() => _aiDescLoading = true);
    try {
      final token = await StorageService.getToken();
      final priceRaw = _priceCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
      final price = double.tryParse(priceRaw);
      final resp = await http
          .post(
            Uri.parse('$kBaseUrl/listings/generate-description'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'title': title,
              'category': _selectedCategory,
              'condition': _selectedCondition,
              if (price != null && price > 0) 'price': price,
              if (_selectedCity != null && _selectedCity!.isNotEmpty) 'location': _selectedCity,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final desc = data['description'] as String? ?? '';
        final tuciSpent = (data['tuci_spent'] as num?)?.toInt() ?? 0;
        if (desc.isNotEmpty) {
          _descCtrl.text = desc;
        } else {
          TeqSnackBar.show(context, message: l.aiDescError, type: TeqSnackBarType.error);
        }
        if (tuciSpent > 0) {
          CacheService.clearData('user_wallet_data');
          _loadAiDescCredits();
          TeqSnackBar.show(context, message: l.tuciSpent(tuciSpent), type: TeqSnackBarType.success);
        } else if (_aiDescCreditsRemaining != null && _aiDescCreditsRemaining! > 0) {
          setState(() => _aiDescCreditsRemaining = _aiDescCreditsRemaining! - 1);
        }
      } else if (resp.statusCode == 402) {
        final detail = (jsonDecode(resp.body) as Map<String, dynamic>)['detail'] as String? ?? l.aiDescError;
        TeqSnackBar.show(context, message: detail, type: TeqSnackBarType.error);
      } else if (resp.statusCode == 503) {
        TeqSnackBar.show(context, message: l.aiDescUnavailable, type: TeqSnackBarType.warning);
      } else {
        TeqSnackBar.show(context, message: l.aiDescError, type: TeqSnackBarType.error);
      }
    } catch (_) {
      if (!mounted) return;
      TeqSnackBar.show(context, message: l.aiDescError, type: TeqSnackBarType.error);
    } finally {
      if (mounted) setState(() => _aiDescLoading = false);
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

    final l10n = AppLocalizations.of(context)!;
    String confidenceLabel = confidence == 'high'
        ? l10n.confidenceHigh
        : confidence == 'medium'
        ? l10n.confidenceMedium
        : l10n.confidenceLow;

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
                        Text(
                          l10n.aiPriceTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          l10n.aiPriceSimilar(foundSimilar),
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
                      label: AppLocalizations.of(
                        context,
                      )!.listingSuggestedStart,
                      value: fmt(suggested),
                      accent: const Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PriceMetricCard(
                      icon: '🏆',
                      label: AppLocalizations.of(context)!.listingExpectedClose,
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
                        label: AppLocalizations.of(context)!.listingLowest,
                        value: fmt(minClose),
                        color: const Color(0xFFEF4444),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: const Color(0xFF334155),
                      ),
                      _MiniStat(
                        label: AppLocalizations.of(context)!.listingAverage,
                        value: fmt(estimated),
                        color: const Color(0xFF94A3B8),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: const Color(0xFF334155),
                      ),
                      _MiniStat(
                        label: AppLocalizations.of(context)!.listingHighest,
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      l10n.aiPriceApply,
                      style: const TextStyle(
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
          TeqSnackBar.show(
            context,
            message: AppLocalizations.of(
              context,
            )!.videoTooLong(_maxVideoDurationSecs, dur.inSeconds),
            type: TeqSnackBarType.warning,
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
    } catch (e, st) {
      debugPrint('[CreateListing] Video upload HATA: $e\n$st');
      if (mounted) {
        showErrorSnackbar(context, _uploadError(e));
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
              title: Text(AppLocalizations.of(context)!.profilePickGallery),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(
                AppLocalizations.of(
                  context,
                )!.createPickCamera(_maxVideoDurationSecs),
              ),
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
      TeqSnackBar.show(
        context,
        message: l.listingMaxPhotos,
        type: TeqSnackBarType.warning,
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
      TeqSnackBar.show(
        context,
        message: AppLocalizations.of(context)!.videoUploading,
        type: TeqSnackBarType.warning,
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
            TeqSnackBar.show(
              context,
              message: l.createListingPhotoUploadFailed(e.toString()),
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
            if (_selectedCondition != null) 'condition': _selectedCondition,
            if (_selectedCity != null && _selectedCity!.isNotEmpty)
              'location': _selectedCity,
            'image_urls': imageUrls,
            if (imageUrls.isNotEmpty) 'image_url': imageUrls.first,
            'thumbnail_url': ?thumbnailUrl,
            if (_videoUploadUrl != null) 'video_url': _videoUploadUrl,
          }),
        ),
      );

      if (!mounted) return;
      AnalyticsService.trackEvent('listing_create_complete', {
        'category': _selectedCategory,
        'has_video': _videoUploadUrl != null,
        'photo_count': _images.length,
      });
      final l = AppLocalizations.of(context)!;
      TeqSnackBar.show(
        context,
        message: l.msgListingPublished,
        type: TeqSnackBarType.success,
      );
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      TeqSnackBar.show(
        context,
        message: _mapError(e),
        type: TeqSnackBarType.error,
      );
    } catch (_) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        TeqSnackBar.show(
          context,
          message: l.createListingConnError,
          type: TeqSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Upload hatalarını kullanıcı dostu Türkçe mesaja çevirir.
  String _uploadError(Object e) {
    final s = e.toString();
    if (s.contains('HTTP 413'))
      return 'Video dosyası çok büyük. Daha kısa bir video deneyin.';
    if (s.contains('HTTP 502') ||
        s.contains('HTTP 503') ||
        s.contains('HTTP 504')) {
      return 'Sunucu şu an meşgul, lütfen tekrar deneyin.';
    }
    if (s.contains('HTTP 401') || s.contains('HTTP 403')) {
      return 'Oturum süreniz dolmuş, lütfen tekrar giriş yapın.';
    }
    if (e is NetworkException) {
      return AppLocalizations.of(context)!.errorNetworkMessage;
    }
    return 'Video yüklenemedi, lütfen tekrar deneyin.';
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
    if (e.code == 'CONTENT_POLICY_VIOLATION') {
      return l.errorContentPolicy;
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
              TeqCard(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l.createListingPhotoCount(_images.length, _maxImages),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (_images.length < _maxImages)
                          TeqButton(
                            key: const Key('create_listing_btn_fotograf_ekle'),
                            onPressed: _showImageSourceSheet,
                            icon: Icons.add_photo_alternate_outlined,
                            text: l.btnAdd,
                            type: TeqButtonType.text,
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
                                        l.photoCover,
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
                                    l.btnAddPhoto,
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
                          l.videoLabel(_maxVideoDurationSecs),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (_video == null && !_videoUploading)
                          TeqButton(
                            onPressed: _showVideoSourceSheet,
                            icon: Icons.videocam_outlined,
                            text: l.btnAdd,
                            type: TeqButtonType.text,
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
                            child: Text(
                              _videoUploading ? l.lblLoading : l.lblVideoReady,
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
                      labelText: l.fieldListingTitle,
                      hintText: l.fieldListingTitleHint,
                      validator: (v) => v == null || v.isEmpty
                          ? l.fieldListingTitleHint
                          : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: const Key('create_listing_select_kategori'),
                      // ignore: deprecated_member_use
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: l.fieldCategory,
                        hintText: l.fieldCategoryHint,
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
                      validator: (v) => v == null ? l.fieldCategoryHint : null,
                    ),
                    const SizedBox(height: 14),

                    DropdownButtonFormField<String>(
                      key: const Key('create_listing_select_konum'),
                      // ignore: deprecated_member_use
                      value: _selectedCity,
                      decoration: InputDecoration(labelText: l.fieldLocation),
                      hint: Text(l.fieldLocationHint),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text('-- ${l.fieldLocationHint} --'),
                        ),
                        ..._cities.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedCity = v),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      key: const Key('create_listing_select_durum'),
                      // ignore: deprecated_member_use
                      value: _selectedCondition,
                      decoration: InputDecoration(labelText: l.fieldCondition),
                      hint: Text(l.fieldConditionHint),
                      items: [
                        DropdownMenuItem(value: 'new', child: Text(l.conditionNew)),
                        DropdownMenuItem(value: 'like_new', child: Text(l.conditionLikeNew)),
                        DropdownMenuItem(value: 'used', child: Text(l.conditionUsed)),
                        DropdownMenuItem(value: 'damaged', child: Text(l.conditionDamaged)),
                      ],
                      validator: (v) => v == null ? l.fieldConditionHint : null,
                      onChanged: (v) => setState(() => _selectedCondition = v),
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
                      labelText: l.fieldDescription,
                      hintText: l.fieldDescriptionHint,
                      validator: (v) => v == null || v.isEmpty
                          ? l.fieldDescriptionHint
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _AiDescButton(
                      loading: _aiDescLoading,
                      enabled: _titleCtrl.text.trim().isNotEmpty && _selectedCategory != null,
                      onTap: _fetchAiDescription,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TeqCard(
                child: Column(
                  children: [
                    TeqTextField(
                      key: const Key('create_listing_input_fiyat'),
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_ThousandSeparatorFormatter()],
                      labelText: l.fieldPrice,
                      hintText: l.fieldPriceHint,
                      prefixText: '₺ ',
                      validator: (v) =>
                          v == null || v.isEmpty ? l.fieldPriceHint : null,
                    ),
                    const SizedBox(height: 10),
                    _AiPriceButton(
                      loading: _aiLoading,
                      isPro: _isPro,
                      creditsRemaining: _aiCreditsRemaining,
                      onTap: _fetchAiPriceEstimate,
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
                  text: l.btnPublishListing,
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

class _ThousandSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
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
        child: Builder(
          builder: (context) {
            final l = AppLocalizations.of(context)!;
            return Row(
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
                      Text(
                        l.aiPriceAnalyzing,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]
                  : [
                      const Text('✨', style: TextStyle(fontSize: 15)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l.aiPriceButton,
                          style: const TextStyle(
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
                              FaIcon(
                                FontAwesomeIcons.crown,
                                size: 10,
                                color:
                                    (creditsRemaining == null ||
                                        creditsRemaining! > 0)
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                creditsRemaining == null ||
                                        creditsRemaining! > 0
                                    ? '${creditsRemaining ?? '…'} ${l.aiCreditsLeftSuffix}'
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
            );
          },
        ),
      ),
    );
  }
}

// ── AI Açıklama Butonu ───────────────────────────────────────────────────────

class _AiDescButton extends StatelessWidget {
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  const _AiDescButton({
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final active = enabled && !loading;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: active ? null : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                : const Color(0xFF334155),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: loading
              ? [
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF6366F1)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l.aiDescGenerating,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]
              : [
                  const Text('✍️', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Text(
                    l.aiDescButton,
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFF475569),
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

// ── Section Card ──────────────────────────────────────────────────────────────
