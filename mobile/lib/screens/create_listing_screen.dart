import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:teqlif/core/network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../core/app_exception.dart';
import '../services/analytics_service.dart';
import '../services/captcha_service.dart';
import '../services/category_service.dart';
import '../services/state_service.dart';
import '../services/catalog_service.dart';
import '../services/field_config_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../services/localization_service.dart';
import '../utils/error_helper.dart';
import '../utils/listing_fields.dart';
import '../utils/number_formatter.dart';

import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/overlays/teq_bottom_sheet.dart';
import '../utils/snackbar_helper.dart';
import '../ui_library/components/inputs/teq_multi_select.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/cards/teq_card.dart';
import '../ui_library/components/buttons/teq_button.dart';
import '../core/media_constants.dart';
import '../services/media_compressor.dart';
import '../providers/compression_progress_provider.dart';
import '../providers/ai_desc_provider.dart';

class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key});

  @override
  ConsumerState<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  // Category / subcategory
  String? _selectedCategory;
  String? _selectedSubcategory;
  List<(String, String)> _categories = [];
  List<(String, String)> _subcategories = [];

  // Location
  String? _selectedProvince;
  String? _selectedDistrict;
  List<String> _provinces = [];
  List<String> _districts = [];

  // Condition
  String? _selectedCondition;

  // Extra fields: key → value (String for all, since JSONB accepts it; numbers stored as strings and parsed on send)
  final Map<String, String> _extraValues = {};

  // Controllers for number/text extra fields
  final Map<String, TextEditingController> _extraCtrlMap = {};

  // Server-driven field schema
  List<ExtraFieldDef> _currentFields = [];
  bool _fieldsLoading = false;

  // Multiselect values: key → selected values
  final Map<String, Set<String>> _extraMultiValues = {};

  // AI / Pro
  bool _isPro = false;
  int? _aiDescCreditsRemaining;

  // Media
  final List<File> _images = [];
  final _picker = ImagePicker();
  File? _video;
  String? _videoUploadUrl;
  bool _videoUploading = false;
  double _videoUploadProgress = 0.0;

  bool _skipAnimation = false;
  bool _typing = false;

  bool _submitting = false;

  static const int _maxImages = 3;
  static const int _maxVideoDurationSecs = MediaConstants.listingVideoMaxSecs;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    ref.read(analyticsServiceProvider).trackEvent('listing_create_start', {});
    _loadCategories();
    ref.read(stateServiceProvider).getStates().then((c) {
      if (mounted) setState(() => _provinces = c);
    });
    _loadProStatus();
    // If catalog is being fetched in background, refresh subcategories when ready.
    CatalogService.onRefreshed.then((_) {
      if (!mounted) return;
      final selected = _selectedCategory;
      if (selected != null && selected.isNotEmpty) {
        _updateSubcategories(selected);
      }
    });
  }

  Future<void> _loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString('app_locale_language_code') ?? 'tr';
    final cats = await ref.read(categoryServiceProvider).getCategories(locale: locale);
    if (!mounted) return;
    setState(() => _categories = cats);
  }

  void _updateSubcategories(String categoryKey) {
    final subs = CatalogService.subcategoriesFor(categoryKey);
    setState(() {
      _subcategories = subs;
      _selectedSubcategory = null;
      _currentFields = [];
      _extraValues.clear();
      _extraMultiValues.clear();
      _disposeExtraCtrls();
    });
  }

  Future<void> _updateExtraFields(String subcategoryKey) async {
    setState(() {
      _fieldsLoading = true;
      _currentFields = [];
      _extraValues.clear();
      _extraMultiValues.clear();
      _disposeExtraCtrls();
    });

    final fields = await FieldConfigService.getFields(subcategoryKey);

    if (!mounted) return;
    for (final f in fields) {
      if (f.type == ExtraFieldType.text || f.type == ExtraFieldType.number) {
        _extraCtrlMap[f.key] = TextEditingController();
      }
    }
    setState(() {
      _currentFields = fields;
      _fieldsLoading = false;
    });
  }

  Future<void> _fetchDistricts(String province) async {
    final districts = await ref.read(stateServiceProvider).getDistricts(province);
    if (!mounted) return;
    setState(() {
      _districts = districts;
      _selectedDistrict = null;
    });
  }

  void _disposeExtraCtrls() {
    for (final c in _extraCtrlMap.values) {
      c.dispose();
    }
    _extraCtrlMap.clear();
  }

  Future<void> _loadProStatus() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final resp = await http
          .get(Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/auth/me'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final isPro = data['is_premium'] == true;
        setState(() => _isPro = isPro);
        if (isPro) {
          _loadAiDescCredits();
        }
      }
    } catch (_) {}
  }

  Future<void> _loadAiDescCredits() async {
    final c = await ref.read(analyticsServiceProvider).getAiDescCredits();
    if (!mounted) return;
    setState(() => _aiDescCreditsRemaining = (c?['remaining'] as num?)?.toInt() ?? 6);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _disposeExtraCtrls();
    super.dispose();
  }

  // ── AI helpers ─────────────────────────────────────────────────────────────

  bool get _aiReady =>
      _titleCtrl.text.trim().isNotEmpty &&
      _selectedCategory != null &&
      _selectedProvince != null &&
      _selectedCondition != null;

  Map<String, dynamic> _collectExtraFields() {
    final ef = <String, dynamic>{};
    if (_selectedSubcategory == null) return ef;
    for (final f in _currentFields) {
      if (f.type == ExtraFieldType.multiselect) {
        final vals = _extraMultiValues[f.key];
        if (vals != null && vals.isNotEmpty) ef[f.key] = vals.toList();
      } else if (f.type == ExtraFieldType.dropdown) {
        final v = _extraValues[f.key];
        if (v != null && v.isNotEmpty) {
          ef[f.key] = f.key == 'year' ? (int.tryParse(v) ?? v) : v;
        }
      } else {
        final v = _extraCtrlMap[f.key]?.text.trim() ?? '';
        if (v.isNotEmpty) {
          if (f.type == ExtraFieldType.number) {
            final n = TeqNumberFormatter.parse(v);
            if (n != null) ef[f.key] = n;
          } else {
            ef[f.key] = v;
          }
        }
      }
    }
    return ef;
  }


  void _appendLocationSuffix() {
    final province = _selectedProvince;
    if (province == null || province.isEmpty) return;
    final district = _selectedDistrict;
    final location = (district != null && district.isNotEmpty)
        ? '$province, $district'
        : province;
    final suffix = '\n\nLokasyon; $location';
    _descCtrl.value = _descCtrl.value.copyWith(
      text: _descCtrl.text + suffix,
      selection: TextSelection.collapsed(offset: _descCtrl.text.length + suffix.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _fetchAiDescription() async {
    final loc = ref.read(localizationProvider);
    if (!_aiReady) {
      TeqSnackBar.show(message: loc.t('createNeedAllFieldsNew'), type: TeqSnackBarType.warning);
      return;
    }
    setState(() {
      _skipAnimation = false;
      _descCtrl.text = '';
    });
    try {
      await ref.read(aiDescProvider.notifier).generate(
        title: _titleCtrl.text.trim(),
        category: _selectedCategory ?? '',
        condition: _selectedCondition,
        price: TeqNumberFormatter.parse(_priceCtrl.text.trim())?.toDouble(),
        subcategory: _selectedSubcategory,
        extraFields: _collectExtraFields(),
        lang: loc.lang,
      );
    } on AppException catch (e) {
      if (mounted) handleError(e, loc);
    } catch (e) {
      if (mounted) handleError(e, loc);
    }
  }

  void _onTapDuringAnimation() {
    if (_typing) setState(() => _skipAnimation = true);
  }


  // ── Media helpers ──────────────────────────────────────────────────────────

  Future<void> _pickVideo(ImageSource source) async {
    // T-HC-07: Kamera seçiminde izni önceden kontrol et
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        final loc = ref.read(localizationProvider);
        showPermissionDeniedDialog(context, title: loc.t('attachCameraPermission'), message: loc.t('permPermanentlyDenied'), openSettingsLabel: loc.t('permOpenSettings'), cancelLabel: loc.t('btnCancel'));
        return;
      }
    }

    XFile? picked;
    if (source == ImageSource.camera) {
      picked = await _picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: _maxVideoDurationSecs));
    } else {
      picked = await _picker.pickVideo(source: ImageSource.gallery);
    }
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    if (source == ImageSource.gallery) {
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      final dur = ctrl.value.duration;
      await ctrl.dispose();
      if (dur.inSeconds > _maxVideoDurationSecs) {
        if (mounted) {
          final loc = ref.read(localizationProvider);
          TeqSnackBar.show(message: loc.t('videoTooLong', {
                'max': _maxVideoDurationSecs.toString(),
                'actual': dur.inSeconds.toString()
              }),
              type: TeqSnackBarType.warning);
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
      final result = await ref.read(uploadServiceProvider).uploadVideoBytes(
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
      }
    } finally {
      ref.read(compressionProgressProvider.notifier).state = null;
      if (mounted) {
        setState(() {
          _videoUploading = false;
          _videoUploadProgress = 0.0;
        });
      }
    }
  }

  void _removeVideo() => setState(() {
        _video = null;
        _videoUploadUrl = null;
        _videoUploading = false;
        _videoUploadProgress = 0.0;
      });

  void _showVideoSourceSheet() {
    final loc = ref.read(localizationProvider);
    TeqBottomSheet.show(
      context: context,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          title: Text(loc.t('createPickCamera',
              {'sec': _maxVideoDurationSecs.toString()})),
          onTap: () {
            Navigator.pop(context);
            _pickVideo(ImageSource.camera);
          },
        ),
      ]),
    );
  }

  Future<void> _pickImages(ImageSource source) async {
    if (_images.length >= _maxImages) {
      TeqSnackBar.show(message: ref.read(localizationProvider).t('listingMaxPhotos'), type: TeqSnackBarType.warning);
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
          imageQuality: 85, maxWidth: 1200, maxHeight: 1200);
      if (picked.isEmpty) return;
      final toAdd = picked
          .take(_maxImages - _images.length)
          .map((x) => File(x.path))
          .toList();
      setState(() => _images.addAll(toAdd));
    } else {
      final picked = await _picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 1200,
          maxHeight: 1200);
      if (picked == null) return;
      setState(() => _images.add(File(picked.path)));
    }
  }

  void _showImageSourceSheet() {
    final loc = ref.read(localizationProvider);
    TeqBottomSheet.show(
      context: context,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
      ]),
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_videoUploading) {
      TeqSnackBar.show(message: ref.read(localizationProvider).t('videoUploading'),
          type: TeqSnackBarType.warning);
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await StorageService.getToken();

      final List<String> imageUrls = [];
      String? thumbnailUrl;
      for (final img in _images) {
        try {
          final compressed = await MediaCompressor.compress(img.path, MediaCompressType.listingPhoto);
          final result = await ref.read(uploadServiceProvider).uploadBytes(
            Uint8List.fromList(compressed.bytes),
            'listing_photo.jpg',
          );
          imageUrls.add(result.url);
          thumbnailUrl ??= result.thumbUrl;
        } catch (e) {
          if (mounted) handleError(e, ref.read(localizationProvider));
        }
      }

      if (!mounted) return;
      final captchaToken = await CaptchaService.getToken();
      if (!mounted) return;

      final extraFields = _collectExtraFields();

      await ref.read(apiClientProvider).call(
        () async => http.post(
          Uri.parse('${ref.read(apiClientProvider).config.baseUrl}/listings'),
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
            if (_selectedSubcategory != null)
              'subcategory': _selectedSubcategory,
            if (_selectedCondition != null) 'condition': _selectedCondition,
            if (_selectedProvince != null) 'province': _selectedProvince,
            if (_selectedDistrict != null) 'district': _selectedDistrict,
            if (extraFields.isNotEmpty) 'extra_fields': extraFields,
            'image_urls': imageUrls,
            if (imageUrls.isNotEmpty) 'image_url': imageUrls.first,
            'thumbnail_url': ?thumbnailUrl,
            if (_videoUploadUrl != null) 'video_url': _videoUploadUrl,
          }),
        ),
      );

      if (!mounted) return;
      ref.read(analyticsServiceProvider).trackEvent('listing_create_complete', {
        'category': _selectedCategory,
        'subcategory': _selectedSubcategory,
        'has_video': _videoUploadUrl != null,
        'photo_count': _images.length,
        'extra_field_count': extraFields.length,
      });
      TeqSnackBar.show(message: ref.read(localizationProvider).t('msgListingPublished'),
          type: TeqSnackBarType.success);
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      handleError(e, ref.read(localizationProvider));
    } catch (_) {
      if (mounted) {
        TeqSnackBar.show(message: ref.read(localizationProvider).t('createListingConnError'),
            type: TeqSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);

    ref.listen<AiDescState>(aiDescProvider, (prev, next) async {
      if (next.status == AiDescStatus.done && prev?.status == AiDescStatus.loading) {
        if (next.teqlikSpent > 0) {
          _loadAiDescCredits();
          TeqSnackBar.show(
            message: loc.t('teqlikSpent', {'count': next.teqlikSpent.toString()}),
            type: TeqSnackBarType.success,
          );
        } else if (_aiDescCreditsRemaining != null && _aiDescCreditsRemaining! > 0) {
          if (mounted) setState(() => _aiDescCreditsRemaining = _aiDescCreditsRemaining! - 1);
        }
        if (next.provider == 'gemini') {
          TeqSnackBar.show(message: loc.t('aiDescFallbackNotice'), type: TeqSnackBarType.info);
        }
        if (mounted) setState(() => _typing = true);
        final fullText = next.text;
        for (int i = 0; i <= fullText.length; i++) {
          if (!mounted || _skipAnimation) break;
          setState(() => _descCtrl.text = fullText.substring(0, i));
          await Future.delayed(const Duration(milliseconds: 18));
        }
        if (mounted) {
          setState(() {
            _descCtrl.text = fullText;
            _typing = false;
            _skipAnimation = false;
          });
          _appendLocationSuffix();
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('btnCreateListing'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhotoSection(loc),
              const SizedBox(height: 12),
              _buildVideoSection(loc),
              const SizedBox(height: 12),
              _buildMainInfoSection(loc),
              const SizedBox(height: 12),
              _buildConditionSection(loc),
              const SizedBox(height: 12),
              _buildLocationSection(loc),
              const SizedBox(height: 12),
              _buildDescriptionSection(loc),
              const SizedBox(height: 12),
              _buildPriceSection(loc),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TeqButton(
                  key: const Key('create_listing_btn_yayinla'),
                  onPressed: _submitting ? null : _submit,
                  text: loc.t('btnPublishListing'),
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

  // ── Section builders ───────────────────────────────────────────────────────

  Widget _buildPhotoSection(TranslationPack loc) {
    return TeqCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                loc.t('createListingPhotoCount', {'count': _images.length.toString(), 'max': _maxImages.toString()}),
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (_images.length < _maxImages)
                TeqButton(
                  key: const Key('create_listing_btn_fotograf_ekle'),
                  onPressed: _showImageSourceSheet,
                  icon: Icons.add_photo_alternate_outlined,
                  text: loc.t('btnAdd'),
                  type: TeqButtonType.text,
                  isExpanded: false,
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
                    _images.length + (_images.length < _maxImages ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  if (i == _images.length) {
                    return GestureDetector(
                      onTap: _showImageSourceSheet,
                      child: Builder(
                        builder: (context) => Container(
                          width: 90,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border(context)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.add,
                              color: AppColors.textSecondary(context)),
                        ),
                      ),
                    );
                  }
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_images[i],
                            width: 90, height: 90, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.removeAt(i)),
                          child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
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
                            child: Text(loc.t('photoCover'),
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
                    border: Border.all(color: AppColors.border(context)),
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
                        Text(loc.t('btnAddPhoto'),
                            style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoSection(TranslationPack loc) {
    return TeqCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(loc.t('videoLabel', {'sec': _maxVideoDurationSecs.toString()}),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              if (_video == null && !_videoUploading)
                TeqButton(
                  onPressed: _showVideoSourceSheet,
                  icon: Icons.videocam_outlined,
                  text: loc.t('btnAdd'),
                  type: TeqButtonType.text,
                  isExpanded: false,
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
                      borderRadius: BorderRadius.circular(6)),
                  child: _videoUploading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 22),
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
                      : Text(loc.t('lblVideoReady'),
                          style: const TextStyle(fontSize: 13)),
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
    );
  }

  Widget _buildMainInfoSection(TranslationPack loc) {
    final extraFields = _currentFields;

    return TeqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.t('sectionListingDetails'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 14),

          // Title input
          TeqTextField(
            key: const Key('create_listing_input_baslik'),
            controller: _titleCtrl,
            labelText: loc.t('fieldListingTitle'),
            hintText: loc.t('fieldListingTitleHint'),
            floatingLabel: true,
            validator: (v) =>
                v == null || v.isEmpty ? loc.t('fieldListingTitleHint') : null,
          ),
          const SizedBox(height: 14),

          // Category
          DropdownButtonFormField<String>(
            key: const Key('create_listing_select_kategori'),
            // ignore: deprecated_member_use
            value: _selectedCategory,
            decoration: InputDecoration(
                labelText: loc.t('fieldCategory'), hintText: loc.t('fieldCategoryHint')),
            hint: Text(loc.t('fieldCategoryHint')),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedCategory = v);
              _updateSubcategories(v);
            },
            validator: (v) => v == null ? loc.t('fieldCategoryHint') : null,
          ),

          // Subcategory (revealed after category selection)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _subcategories.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: const Key('create_listing_select_alt_kategori'),
                        // ignore: deprecated_member_use
                        value: _selectedSubcategory,
                        decoration: InputDecoration(
                            labelText: loc.t('fieldSubcategory'),
                            hintText: loc.t('fieldSubcategoryHint')),
                        hint: Text(loc.t('fieldSubcategoryHint')),
                        items: _subcategories
                            .map((s) => DropdownMenuItem(
                                value: s.$1, child: Text(loc.tOr('subcat_${s.$1}', s.$2))))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _selectedSubcategory = v);
                          _updateExtraFields(v);
                        },
                        validator: (v) =>
                            v == null ? loc.t('validRequiredSubcategory') : null,
                      ),
                    ],
                  ),
          ),

          // Extra fields merged in (revealed after subcategory selection)
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            child: _fieldsLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : extraFields.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 14),
                          ...extraFields.map((f) => _buildExtraField(f, loc)),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(TranslationPack loc) {
    return TeqCard(
      child: Column(
        children: [
          // İl
          DropdownButtonFormField<String>(
            key: const Key('create_listing_select_il'),
            // ignore: deprecated_member_use
            value: _selectedProvince,
            decoration: InputDecoration(
                labelText: loc.t('fieldProvince'), hintText: loc.t('fieldProvinceHint')),
            hint: Text(loc.t('fieldProvinceHint')),
            items: [
              DropdownMenuItem(
                  value: null,
                  child: Text('-- ${loc.t('fieldProvinceHint')} --')),
              ..._provinces.map(
                  (p) => DropdownMenuItem(value: p, child: Text(p))),
            ],
            validator: (v) =>
                v == null || v.isEmpty ? loc.t('validRequiredProvince') : null,
            onChanged: (v) {
              setState(() {
                _selectedProvince = v;
                _districts = [];
                _selectedDistrict = null;
              });
              if (v != null) _fetchDistricts(v);
            },
          ),

          // İlçe — sadece il seçildikten sonra ve ilçeler yüklendikten sonra açılır
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _districts.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: const Key('create_listing_select_ilce'),
                        // ignore: deprecated_member_use
                        value: _selectedDistrict,
                        decoration: InputDecoration(
                            labelText: loc.t('fieldDistrict'),
                            hintText: loc.t('fieldDistrictHint')),
                        hint: Text(loc.t('fieldDistrictHint')),
                        items: _districts
                            .map((d) =>
                                DropdownMenuItem(value: d, child: Text(d)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedDistrict = v),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionSection(TranslationPack loc) {
    if (_selectedCategory == 'real_estate') return const SizedBox.shrink();

    final isVasita = _selectedCategory == 'vehicles';
    final items = isVasita
        ? [
            DropdownMenuItem(value: 'new', child: Text(loc.t('conditionNew'))),
            DropdownMenuItem(value: 'used', child: Text(loc.t('conditionUsed'))),
          ]
        : [
            DropdownMenuItem(value: 'new', child: Text(loc.t('conditionNew'))),
            DropdownMenuItem(value: 'like_new', child: Text(loc.t('conditionLikeNew'))),
            DropdownMenuItem(value: 'used', child: Text(loc.t('conditionUsed'))),
            DropdownMenuItem(value: 'refurbished', child: Text(loc.t('conditionRefurbished'))),
            DropdownMenuItem(value: 'damaged', child: Text(loc.t('conditionDamaged'))),
          ];

    final validCondition = items.any((i) => i.value == _selectedCondition)
        ? _selectedCondition
        : null;

    return TeqCard(
      child: DropdownButtonFormField<String>(
        key: const Key('create_listing_select_durum'),
        // ignore: deprecated_member_use
        value: validCondition,
        decoration: InputDecoration(
            labelText: loc.t('fieldCondition'), hintText: loc.t('fieldConditionHint')),
        hint: Text(loc.t('fieldConditionHint')),
        items: items,
        validator: (v) => v == null ? loc.t('validRequiredCondition') : null,
        onChanged: (v) => setState(() => _selectedCondition = v),
      ),
    );
  }


  Widget _buildExtraField(ExtraFieldDef f, TranslationPack loc) {
    final label = loc.t(f.labelKey);
    final optionalSuffix = f.optional ? '  ${loc.t('extraFieldOptional')}' : '';
    final displayLabel = '$label$optionalSuffix';

    // Brand-dependent conditional dropdown (model fields)
    if (f.dependsOn != null) {
      final parentVal = _extraValues[f.dependsOn!];
      final options = parentVal != null
          ? (f.conditionalOptions?[parentVal] ?? <FieldOption>[])
          : <FieldOption>[];
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: options.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _extraValues[f.key],
                  decoration: InputDecoration(
                      labelText: displayLabel, hintText: displayLabel),
                  hint: Text(displayLabel),
                  items: options
                      .map((o) =>
                          DropdownMenuItem(value: o.value, child: Text(loc.tOr('opt_${o.value}', o.label))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    if (v != null) _extraValues[f.key] = v;
                  }),
                  validator: f.optional
                      ? null
                      : (v) => v == null || v.isEmpty ? displayLabel : null,
                ),
              ),
      );
    }

    Widget field;
    switch (f.type) {
      case ExtraFieldType.dropdown:
        // Year field: dynamically generated dropdown (always current)
        final items = f.key == 'year'
            ? List.generate(
                DateTime.now().year - 1899,
                (i) {
                  final y = (DateTime.now().year - i).toString();
                  return DropdownMenuItem(value: y, child: Text(y));
                },
              )
            : f.options
                .map((o) => DropdownMenuItem(value: o.value, child: Text(loc.tOr('opt_${o.value}', o.label))))
                .toList();

        field = DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _extraValues[f.key],
          decoration: InputDecoration(
              labelText: displayLabel,
              hintText: displayLabel,
              suffixText: f.unit),
          hint: Text(displayLabel),
          items: items,
          onChanged: (v) => setState(() {
            if (v != null) {
              _extraValues[f.key] = v;
              // Clear any fields that depend on this one
              for (final dep in _currentFields) {
                if (dep.dependsOn == f.key) _extraValues.remove(dep.key);
              }
            }
          }),
          validator: f.optional
              ? null
              : (v) => v == null || v.isEmpty ? displayLabel : null,
        );
        break;

      case ExtraFieldType.number:
        field = TeqTextField(
          controller: _extraCtrlMap[f.key],
          labelText: displayLabel,
          floatingLabel: true,
          keyboardType: TextInputType.number,
          inputFormatters: [TeqNumericInputFormatter(fieldKey: f.key)],
          suffixIcon: f.unit != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(f.unit!,
                      style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13)),
                )
              : null,
          validator: f.optional
              ? null
              : (v) => (v == null || v.isEmpty) ? displayLabel : null,
        );
        break;

      case ExtraFieldType.text:
        field = TeqTextField(
          controller: _extraCtrlMap[f.key],
          labelText: displayLabel,
          floatingLabel: true,
          validator: f.optional
              ? null
              : (v) => (v == null || v.isEmpty) ? displayLabel : null,
        );
        break;

      case ExtraFieldType.multiselect:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TeqMultiSelect(
            label: displayLabel,
            options: f.options.map((o) {
                  return TeqMultiSelectOption(
                    value: o.value,
                    label: loc.tOr('opt_${o.value}', o.label),
                    isExclusive: o.isExclusive,
                    exclusionGroup: o.exclusionGroup,
                  );
                }).toList(),
            selected: _extraMultiValues[f.key] ?? const {},
            optional: f.optional,
            validator: f.optional
                ? null
                : (s) => s.isEmpty ? displayLabel : null,
            onChanged: (vals) => setState(() => _extraMultiValues[f.key] = vals),
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: field,
    );
  }


  Widget _buildDescriptionSection(TranslationPack loc) {
    return TeqCard(
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
            validator: (v) =>
                v == null || v.isEmpty ? loc.t('fieldDescriptionHint') : null,
            onTap: _onTapDuringAnimation,
          ),
          const SizedBox(height: 10),
          _AiDescButton(
            loading: ref.watch(aiDescProvider).status == AiDescStatus.loading || _typing,
            isPro: _isPro,
            creditsRemaining: _aiDescCreditsRemaining,
            onTap: _fetchAiDescription,
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection(TranslationPack loc) {
    return TeqCard(
      child: Column(
        children: [
          TeqTextField(
            key: const Key('create_listing_input_fiyat'),
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [const TeqNumericInputFormatter(fieldKey: 'price', allowDecimal: true)],
            labelText: loc.t('fieldPrice'),
            hintText: loc.t('fieldPriceHint'),
            prefixText: '₺ ',
            validator: (v) =>
                v == null || v.isEmpty ? loc.t('validRequiredPrice') : null,
          ),
        ],
      ),
    );
  }
}

// ── Formatters & sub-widgets ──────────────────────────────────────────────────

class _AiDescButton extends ConsumerWidget {
  final bool loading;
  final bool isPro;
  final int? creditsRemaining;
  final VoidCallback onTap;
  const _AiDescButton(
      {required this.loading,
      required this.onTap,
      this.isPro = false,
      this.creditsRemaining});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final active = !loading;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight)
              : null,
          color: active ? null : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active
                  ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                  : const Color(0xFF334155)),
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
                          valueColor:
                              AlwaysStoppedAnimation(Color(0xFF6366F1)))),
                  const SizedBox(width: 10),
                  Text(loc.t('aiDescGenerating'),
                      style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ]
              : [
                  const Text('✍️', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text(loc.t('aiDescButton'),
                          style: TextStyle(
                              color: active
                                  ? Colors.white
                                  : const Color(0xFF475569),
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis)),
                  if (isPro) ...[
                    const SizedBox(width: 8),
                    _CreditBadge(
                        remaining: creditsRemaining,
                        suffix: loc.t('aiCreditsLeftSuffix')),
                  ],
                ],
        ),
      ),
    );
  }
}

class _CreditBadge extends ConsumerWidget {
  final int? remaining;
  final String suffix;
  const _CreditBadge({required this.remaining, required this.suffix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCredits = remaining == null || remaining! > 0;
    final color =
        hasCredits ? const Color(0xFF34D399) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(FontAwesomeIcons.crown, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          hasCredits ? '${remaining ?? '…'} $suffix' : '5 teqliq',
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3),
        ),
      ]),
    );
  }
}