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
import '../services/field_config_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/error_helper.dart';
import '../utils/field_labels.dart';
import '../utils/listing_fields.dart';

import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/inputs/teq_multi_select.dart';
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
  bool _aiLoading = false;
  bool _aiDescLoading = false;
  int? _aiCreditsRemaining;
  int? _aiDescCreditsRemaining;

  // Media
  final List<File> _images = [];
  final _picker = ImagePicker();
  File? _video;
  String? _videoUploadUrl;
  bool _videoUploading = false;

  bool _submitting = false;

  static const int _maxImages = 10;
  static const int _maxVideoDurationSecs = 15;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    AnalyticsService.trackEvent('listing_create_start', {});
    _loadCategories();
    CityService.getCities().then((c) {
      if (mounted) setState(() => _provinces = c);
    });
    _loadProStatus();
  }

  Future<void> _loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString('app_locale_language_code') ?? 'tr';
    final cats = await CategoryService.getCategories(locale: locale);
    if (!mounted) return;
    setState(() => _categories = cats);
  }

  void _updateSubcategories(String categoryKey) {
    final subs = kSubcategories[categoryKey] ?? [];
    setState(() {
      _subcategories = subs;
      _selectedSubcategory = null;
      _extraValues.clear();
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
    final districts = await CityService.getDistricts(province);
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
          .get(Uri.parse('$kBaseUrl/auth/me'),
              headers: {'Authorization': 'Bearer $token'})
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
    final c = await AnalyticsService.getAiPriceCredits();
    if (!mounted) return;
    setState(() => _aiCreditsRemaining = (c?['remaining'] as num?)?.toInt() ?? 20);
  }

  Future<void> _loadAiDescCredits() async {
    final c = await AnalyticsService.getAiDescCredits();
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

  Future<void> _fetchAiPriceEstimate() async {
    final l = AppLocalizations.of(context)!;
    if (!_aiReady) {
      TeqSnackBar.show(context,
          message: l.createNeedAllFieldsNew, type: TeqSnackBarType.warning);
      return;
    }
    setState(() => _aiLoading = true);
    try {
      final result = await AnalyticsService.getPriceEstimate(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: _selectedCategory ?? '',
        city: _selectedProvince ?? '',
        condition: _selectedCondition ?? '',
      );
      if (!mounted) return;
      if (result == null) {
        TeqSnackBar.show(context,
            message: l.aiPriceError, type: TeqSnackBarType.error);
        return;
      }
      final tuciSpent = (result['tuci_spent'] as num?)?.toInt() ?? 0;
      if (tuciSpent > 0) {
        CacheService.clearData('user_wallet_data');
        _loadAiCredits();
        TeqSnackBar.show(context,
            message: l.tuciSpent(tuciSpent), type: TeqSnackBarType.success);
      } else if (_aiCreditsRemaining != null && _aiCreditsRemaining! > 0) {
        setState(() => _aiCreditsRemaining = _aiCreditsRemaining! - 1);
      }
      _showPriceEstimateSheet(result);
    } on AiInsufficientTuciException catch (e) {
      if (!mounted) return;
      String msg = e.detail;
      if (msg == 'INSUFFICIENT_FUNDS_PRO') {
        msg = l.apiErrorInsufficientFundsPro(5);
      } else if (msg == 'INSUFFICIENT_FUNDS_STD') {
        msg = l.apiErrorInsufficientFundsStd(5);
      } else if (msg == 'AI_SERVICE_BUSY') {
        msg = l.apiErrorAiServiceBusy;
      } else if (msg == 'AI_SERVICE_TIMEOUT') {
        msg = l.apiErrorAiServiceTimeout;
      } else if (msg == 'VALIDATION_ERROR') {
        msg = l.createNeedAllFieldsNew;
      }
      TeqSnackBar.show(context, message: msg, type: TeqSnackBarType.error);
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _fetchAiDescription() async {
    final l = AppLocalizations.of(context)!;
    if (!_aiReady) {
      TeqSnackBar.show(context,
          message: l.createNeedAllFieldsNew, type: TeqSnackBarType.warning);
      return;
    }
    setState(() {
      _aiDescLoading = true;
      _descCtrl.text = '';
    });

    http.Client? client;
    try {
      final token = await StorageService.getToken();
      final priceRaw =
          _priceCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
      final price = double.tryParse(priceRaw);

      final req = http.Request(
          'POST', Uri.parse('$kBaseUrl/listings/generate-description'));
      req.headers['Content-Type'] = 'application/json';
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.body = jsonEncode({
        'title': _titleCtrl.text.trim(),
        'category': _selectedCategory,
        'condition': _selectedCondition,
        if (price != null && price > 0) 'price': price,
        if (_selectedProvince != null) 'location': _selectedProvince,
      });

      client = http.Client();
      final resp =
          await client.send(req).timeout(const Duration(seconds: 60));
      if (!mounted) return;

      if (resp.statusCode == 200) {
        final stream = resp.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in stream) {
          if (!mounted) break;
          if (line.startsWith('data: ')) {
            final dataStr = line.substring(6);
            try {
              final json = jsonDecode(dataStr) as Map<String, dynamic>;
              if (json.containsKey('error')) {
                TeqSnackBar.show(context,
                    message: l.aiDescError, type: TeqSnackBarType.error);
                break;
              } else if (json.containsKey('text')) {
                final newText = _descCtrl.text + (json['text'] as String);
                _descCtrl.value = _descCtrl.value.copyWith(
                  text: newText,
                  selection: TextSelection.collapsed(offset: newText.length),
                  composing: TextRange.empty,
                );
                await Future.delayed(const Duration(milliseconds: 30));
              } else if (json['done'] == true) {
                final tuciSpent = (json['tuci_spent'] as num?)?.toInt() ?? 0;
                if (tuciSpent > 0) {
                  CacheService.clearData('user_wallet_data');
                  _loadAiDescCredits();
                  TeqSnackBar.show(context,
                      message: l.tuciSpent(tuciSpent),
                      type: TeqSnackBarType.success);
                } else if (_aiDescCreditsRemaining != null &&
                    _aiDescCreditsRemaining! > 0) {
                  setState(
                      () => _aiDescCreditsRemaining = _aiDescCreditsRemaining! - 1);
                }
              }
            } catch (_) {}
          }
        }
      } else {
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        final ll = AppLocalizations.of(context)!;
        final errBody = await resp.stream.bytesToString();
        if (resp.statusCode == 402) {
          String msg;
          try {
            final detail =
                (jsonDecode(errBody) as Map<String, dynamic>)['detail']
                    as String? ??
                    ll.aiDescError;
            if (detail == 'INSUFFICIENT_FUNDS_PRO') {
              msg = ll.apiErrorInsufficientFundsPro(5);
            } else if (detail == 'INSUFFICIENT_FUNDS_STD') {
              msg = ll.apiErrorInsufficientFundsStd(5);
            } else {
              msg = detail;
            }
          } catch (_) {
            msg = ll.aiDescError;
          }
          // ignore: use_build_context_synchronously
          TeqSnackBar.show(context, message: msg, type: TeqSnackBarType.error);
        } else if (resp.statusCode == 503) {
          // ignore: use_build_context_synchronously
          TeqSnackBar.show(context,
              message: ll.aiDescUnavailable, type: TeqSnackBarType.warning);
        } else {
          // ignore: use_build_context_synchronously
          TeqSnackBar.show(context,
              message: ll.aiDescError, type: TeqSnackBarType.error);
        }
      }
    } catch (_) {
      if (mounted) {
        TeqSnackBar.show(context,
            message: AppLocalizations.of(context)!.aiDescStreamError,
            type: TeqSnackBarType.error);
      }
    } finally {
      client?.close();
      if (mounted) setState(() => _aiDescLoading = false);
    }
  }

  // ── Price sheet ────────────────────────────────────────────────────────────

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

    final Color confidenceColor = confidence == 'high'
        ? const Color(0xFF22C55E)
        : confidence == 'medium'
            ? const Color(0xFFF59E0B)
            : const Color(0xFF64748B);

    final l10n = AppLocalizations.of(context)!;
    final String confidenceLabel = confidence == 'high'
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('✨', style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.aiPriceTitle,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                        Text(l10n.aiPriceSimilar(foundSimilar),
                            style: const TextStyle(
                                color: Color(0xFF64748B), fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: confidenceColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(confidenceLabel,
                        style: TextStyle(
                            color: confidenceColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _PriceMetricCard(
                        icon: '🎯',
                        label: l10n.listingSuggestedStart,
                        value: fmt(suggested),
                        accent: const Color(0xFF6366F1)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PriceMetricCard(
                        icon: '🏆',
                        label: l10n.listingExpectedClose,
                        value: fmt(estimated),
                        accent: const Color(0xFF22C55E)),
                  ),
                ],
              ),
              if (minClose != null && maxClose != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MiniStat(
                          label: l10n.listingLowest,
                          value: fmt(minClose),
                          color: const Color(0xFFEF4444)),
                      Container(width: 1, height: 32, color: const Color(0xFF334155)),
                      _MiniStat(
                          label: l10n.listingAverage,
                          value: fmt(estimated),
                          color: const Color(0xFF94A3B8)),
                      Container(width: 1, height: 32, color: const Color(0xFF334155)),
                      _MiniStat(
                          label: l10n.listingHighest,
                          value: fmt(maxClose),
                          color: const Color(0xFF22C55E)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(advice,
                            style: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 13,
                                height: 1.55))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (suggested != null && suggested > 0)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final intVal = suggested.toInt();
                      _priceCtrl.text = intVal
                          .toString()
                          .replaceAllMapped(
                              RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l10n.aiPriceApply,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Media helpers ──────────────────────────────────────────────────────────

  Future<void> _pickVideo(ImageSource source) async {
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
          TeqSnackBar.show(context,
              message: AppLocalizations.of(context)!
                  .videoTooLong(_maxVideoDurationSecs, dur.inSeconds),
              type: TeqSnackBarType.warning);
        }
        return;
      }
    }
    setState(() {
      _video = file;
      _videoUploadUrl = null;
      _videoUploading = true;
    });
    try {
      final result = await UploadService.uploadVideo(file);
      if (mounted) setState(() => _videoUploadUrl = result.videoUrl);
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, _uploadError(e));
        _removeVideo();
      }
    } finally {
      if (mounted) setState(() => _videoUploading = false);
    }
  }

  void _removeVideo() => setState(() {
        _video = null;
        _videoUploadUrl = null;
        _videoUploading = false;
      });

  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            title: Text(AppLocalizations.of(context)!
                .createPickCamera(_maxVideoDurationSecs)),
            onTap: () {
              Navigator.pop(context);
              _pickVideo(ImageSource.camera);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _pickImages(ImageSource source) async {
    final l = AppLocalizations.of(context)!;
    if (_images.length >= _maxImages) {
      TeqSnackBar.show(context,
          message: l.listingMaxPhotos, type: TeqSnackBarType.warning);
      return;
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
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
        ]),
      ),
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_videoUploading) {
      TeqSnackBar.show(context,
          message: AppLocalizations.of(context)!.videoUploading,
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
          final result = await UploadService.uploadFile(img);
          imageUrls.add(result.url);
          thumbnailUrl ??= result.thumbUrl;
        } catch (e) {
          if (mounted) {
            TeqSnackBar.show(context,
                message: _uploadError(e), type: TeqSnackBarType.error);
          }
        }
      }

      if (!mounted) return;
      final captchaToken = await CaptchaService.getToken();
      if (!mounted) return;

      // Build extra_fields: merge controller values + dropdown values, skip blanks
      final Map<String, dynamic> extraFields = {};
      if (_selectedSubcategory != null) {
        final fields = _currentFields;
        for (final f in fields) {
          if (f.type == ExtraFieldType.multiselect) {
            final vals = _extraMultiValues[f.key];
            if (vals != null && vals.isNotEmpty) extraFields[f.key] = vals.toList();
          } else if (f.type == ExtraFieldType.dropdown) {
            final v = _extraValues[f.key];
            if (v != null && v.isNotEmpty) {
              // yil is stored as integer for consistency with existing listings
              final asInt = f.key == 'year' ? int.tryParse(v) : null;
              extraFields[f.key] = asInt ?? v;
            }
          } else {
            final ctrl = _extraCtrlMap[f.key];
            final v = ctrl?.text.trim() ?? '';
            if (v.isNotEmpty) {
              if (f.type == ExtraFieldType.number) {
                final n = num.tryParse(v.replaceAll('.', '').replaceAll(',', '.'));
                if (n != null) extraFields[f.key] = n;
              } else {
                extraFields[f.key] = v;
              }
            }
          }
        }
      }

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
      AnalyticsService.trackEvent('listing_create_complete', {
        'category': _selectedCategory,
        'subcategory': _selectedSubcategory,
        'has_video': _videoUploadUrl != null,
        'photo_count': _images.length,
        'extra_field_count': extraFields.length,
      });
      TeqSnackBar.show(context,
          message: AppLocalizations.of(context)!.msgListingPublished,
          type: TeqSnackBarType.success);
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      TeqSnackBar.show(context,
          message: _mapError(e), type: TeqSnackBarType.error);
    } catch (_) {
      if (mounted) {
        TeqSnackBar.show(context,
            message:
                AppLocalizations.of(context)!.createListingConnError,
            type: TeqSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Error helpers ──────────────────────────────────────────────────────────

  String _uploadError(Object e) {
    final s = e.toString();
    final l = AppLocalizations.of(context)!;
    if (s.contains('HTTP 413')) return l.uploadErrorTooLarge;
    if (s.contains('HTTP 502') || s.contains('HTTP 503') || s.contains('HTTP 504')) {
      return l.uploadErrorServerBusy;
    }
    if (s.contains('HTTP 401') || s.contains('HTTP 403')) {
      return l.uploadErrorAuthExpired;
    }
    if (e is NetworkException) { return l.errorNetworkMessage; }
    return l.uploadErrorGeneric;
  }

  String _mapError(AppException e) {
    final l = AppLocalizations.of(context)!;
    if (e.statusCode == 403 || e.code == 'FORBIDDEN') return l.errorCaptchaFailed;
    if (e.statusCode == 429 || e.code == 'RATE_LIMIT_EXCEEDED') return l.errorTooFast;
    if (e.code == 'CONTENT_POLICY_VIOLATION') return l.errorContentPolicy;
    if (e.code == 'PROVINCE_REQUIRED') return l.errProvinceRequired;
    if (e.code == 'INVALID_CONDITION') return l.errInvalidCondition;
    if (e.code == 'INVALID_PRICE') return l.errInvalidPrice;
    if (e.code == 'LISTING_TITLE_REQUIRED') return l.fieldListingTitleHint;
    return e.message;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
              _buildPhotoSection(l),
              const SizedBox(height: 12),
              _buildVideoSection(l),
              const SizedBox(height: 12),
              _buildMainInfoSection(l),
              const SizedBox(height: 12),
              _buildConditionSection(l),
              const SizedBox(height: 12),
              _buildLocationSection(l),
              const SizedBox(height: 12),
              _buildDescriptionSection(l),
              const SizedBox(height: 12),
              _buildPriceSection(l),
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

  // ── Section builders ───────────────────────────────────────────────────────

  Widget _buildPhotoSection(AppLocalizations l) {
    return TeqCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l.createListingPhotoCount(_images.length, _maxImages),
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (_images.length < _maxImages)
                TeqButton(
                  key: const Key('create_listing_btn_fotograf_ekle'),
                  onPressed: _showImageSourceSheet,
                  icon: Icons.add_photo_alternate_outlined,
                  text: l.btnAdd,
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
                        Text(l.btnAddPhoto,
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

  Widget _buildVideoSection(AppLocalizations l) {
    return TeqCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.videoLabel(_maxVideoDurationSecs),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              if (_video == null && !_videoUploading)
                TeqButton(
                  onPressed: _showVideoSourceSheet,
                  icon: Icons.videocam_outlined,
                  text: l.btnAdd,
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
                    child: Text(_videoUploading ? l.lblLoading : l.lblVideoReady,
                        style: const TextStyle(fontSize: 13))),
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

  Widget _buildMainInfoSection(AppLocalizations l) {
    final extraFields = _currentFields;

    return TeqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.sectionListingDetails,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 14),

          // Title input
          TeqTextField(
            key: const Key('create_listing_input_baslik'),
            controller: _titleCtrl,
            labelText: l.fieldListingTitle,
            hintText: l.fieldListingTitleHint,
            floatingLabel: true,
            validator: (v) =>
                v == null || v.isEmpty ? l.fieldListingTitleHint : null,
          ),
          const SizedBox(height: 14),

          // Category
          DropdownButtonFormField<String>(
            key: const Key('create_listing_select_kategori'),
            // ignore: deprecated_member_use
            value: _selectedCategory,
            decoration: InputDecoration(
                labelText: l.fieldCategory, hintText: l.fieldCategoryHint),
            hint: Text(l.fieldCategoryHint),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedCategory = v);
              _updateSubcategories(v);
            },
            validator: (v) => v == null ? l.fieldCategoryHint : null,
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
                            labelText: l.fieldSubcategory,
                            hintText: l.fieldSubcategoryHint),
                        hint: Text(l.fieldSubcategoryHint),
                        items: _subcategories
                            .map((s) => DropdownMenuItem(
                                value: s.$1, child: Text(subcatLabel(s.$1, l, fallback: s.$2))))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _selectedSubcategory = v);
                          _updateExtraFields(v);
                        },
                        validator: (v) =>
                            v == null ? l.validRequiredSubcategory : null,
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
                          ...extraFields.map((f) => _buildExtraField(f, l)),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(AppLocalizations l) {
    return TeqCard(
      child: Column(
        children: [
          // İl
          DropdownButtonFormField<String>(
            key: const Key('create_listing_select_il'),
            // ignore: deprecated_member_use
            value: _selectedProvince,
            decoration: InputDecoration(
                labelText: l.fieldProvince, hintText: l.fieldProvinceHint),
            hint: Text(l.fieldProvinceHint),
            items: [
              DropdownMenuItem(
                  value: null,
                  child: Text('-- ${l.fieldProvinceHint} --')),
              ..._provinces.map(
                  (p) => DropdownMenuItem(value: p, child: Text(p))),
            ],
            validator: (v) =>
                v == null || v.isEmpty ? l.validRequiredProvince : null,
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
                            labelText: l.fieldDistrict,
                            hintText: l.fieldDistrictHint),
                        hint: Text(l.fieldDistrictHint),
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

  Widget _buildConditionSection(AppLocalizations l) {
    final isVasita = _selectedCategory == 'vehicles';
    final items = isVasita
        ? [
            DropdownMenuItem(value: 'new', child: Text(l.conditionNew)),
            DropdownMenuItem(value: 'used', child: Text(l.conditionUsed)),
          ]
        : [
            DropdownMenuItem(value: 'new', child: Text(l.conditionNew)),
            DropdownMenuItem(value: 'like_new', child: Text(l.conditionLikeNew)),
            DropdownMenuItem(value: 'used', child: Text(l.conditionUsed)),
            DropdownMenuItem(value: 'refurbished', child: Text(l.conditionRefurbished)),
            DropdownMenuItem(value: 'damaged', child: Text(l.conditionDamaged)),
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
            labelText: l.fieldCondition, hintText: l.fieldConditionHint),
        hint: Text(l.fieldConditionHint),
        items: items,
        validator: (v) => v == null ? l.validRequiredCondition : null,
        onChanged: (v) => setState(() => _selectedCondition = v),
      ),
    );
  }


  Widget _buildExtraField(ExtraFieldDef f, AppLocalizations l) {
    final label = _extraFieldLabel(f.labelKey, l);
    final optionalSuffix = f.optional ? '  ${l.extraFieldOptional}' : '';
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
                          DropdownMenuItem(value: o.value, child: Text(o.label)))
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
                .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
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
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                  final pov = o.parentOptionValue;
                  return TeqMultiSelectOption(
                    value: o.value,
                    label: o.label,
                    isExclusive: o.isExclusive,
                    exclusionGroup: (pov != null && pov.startsWith('grp:'))
                        ? pov.substring(4)
                        : null,
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

  String _extraFieldLabel(String labelKey, AppLocalizations l) {
    return switch (labelKey) {
      'extraField_brand' => l.extraField_brand,
      'extraField_model' => l.extraField_model,
      'extraField_year' => l.extraField_year,
      'extraField_mileage' => l.extraField_mileage,
      'extraField_color' => l.extraField_color,
      'extraField_fuel_type' => l.extraField_fuel_type,
      'extraField_transmission' => l.extraField_transmission,
      'extraField_body_type' => l.extraField_body_type,
      'extraField_damage_status' => l.extraField_damage_status,
      'extraField_type' => l.extraField_type,
      'extraField_engine_cc' => l.extraField_engine_cc,
      'extraField_range' => l.extraField_range,
      'extraField_storage' => l.extraField_storage,
      'extraField_ram' => l.extraField_ram,
      'extraField_processor' => l.extraField_processor,
      'extraField_screen_size' => l.extraField_screen_size,
      'extraField_room_count' => l.extraField_room_count,
      'extraField_gross_sqm' => l.extraField_gross_sqm,
      'extraField_net_sqm' => l.extraField_net_sqm,
      'extraField_land_sqm' => l.extraField_land_sqm,
      'extraField_sqm' => l.extraField_sqm,
      'extraField_building_age' => l.extraField_building_age,
      'extraField_floor' => l.extraField_floor,
      'extraField_floor_count' => l.extraField_floor_count,
      'extraField_unit_count' => l.extraField_unit_count,
      'extraField_heating' => l.extraField_heating,
      'extraField_furnishing' => l.extraField_furnishing,
      'extraField_elevator' => l.extraField_elevator,
      'extraField_parking' => l.extraField_parking,
      'extraField_title_deed' => l.extraField_title_deed,
      'extraField_land_use' => l.extraField_land_use,
      'extraField_size' => l.extraField_size,
      'extraField_shoe_size' => l.extraField_shoe_size,
      'extraField_gender' => l.extraField_gender,
      'extraField_material' => l.extraField_material,
      'extraField_gold_carat' => l.extraField_gold_carat,
      'extraField_silver_purity' => l.extraField_silver_purity,
      'extraField_wheel_size' => l.extraField_wheel_size,
      'extraField_sport_type' => l.extraField_sport_type,
      'extraField_book_title' => l.extraField_book_title,
      'extraField_author' => l.extraField_author,
      'extraField_publisher' => l.extraField_publisher,
      'extraField_length' => l.extraField_length,
      'extraField_working_hours' => l.extraField_working_hours,
      'extraField_compatible_model' => l.extraField_compatible_model,
      'extraField_part_type' => l.extraField_part_type,
      'extraField_breed' => l.extraField_breed,
      _ => labelKey,
    };
  }

  Widget _buildDescriptionSection(AppLocalizations l) {
    return TeqCard(
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
            validator: (v) =>
                v == null || v.isEmpty ? l.fieldDescriptionHint : null,
          ),
          const SizedBox(height: 10),
          _AiDescButton(
            loading: _aiDescLoading,
            enabled: _aiReady,
            isPro: _isPro,
            creditsRemaining: _aiDescCreditsRemaining,
            onTap: _fetchAiDescription,
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection(AppLocalizations l) {
    return TeqCard(
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
                v == null || v.isEmpty ? l.validRequiredPrice : null,
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
    );
  }
}

// ── Formatters & sub-widgets ──────────────────────────────────────────────────

class _ThousandSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('.', '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final formatted = _addDots(digits);
    return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length));
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

class _AiPriceButton extends StatelessWidget {
  final bool loading;
  final bool isPro;
  final int? creditsRemaining;
  final VoidCallback onTap;
  const _AiPriceButton(
      {required this.loading,
      required this.isPro,
      required this.onTap,
      this.creditsRemaining});

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
                  end: Alignment.centerRight),
          color: loading ? const Color(0xFF1E293B) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: loading
                  ? const Color(0xFF334155)
                  : const Color(0xFF6366F1).withValues(alpha: 0.5)),
        ),
        child: Builder(builder: (context) {
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
                            valueColor: AlwaysStoppedAnimation(
                                Color(0xFF6366F1)))),
                    const SizedBox(width: 10),
                    Text(l.aiPriceAnalyzing,
                        style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ]
                : [
                    const Text('✨', style: TextStyle(fontSize: 15)),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(l.aiPriceButton,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis)),
                    if (isPro) ...[
                      const SizedBox(width: 8),
                      _CreditBadge(
                          remaining: creditsRemaining,
                          suffix: l.aiCreditsLeftSuffix),
                    ],
                  ],
          );
        }),
      ),
    );
  }
}

class _AiDescButton extends StatelessWidget {
  final bool loading;
  final bool enabled;
  final bool isPro;
  final int? creditsRemaining;
  final VoidCallback onTap;
  const _AiDescButton(
      {required this.loading,
      required this.enabled,
      required this.onTap,
      this.isPro = false,
      this.creditsRemaining});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final active = enabled && !loading;
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
                  Text(l.aiDescGenerating,
                      style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ]
              : [
                  const Text('✍️', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text(l.aiDescButton,
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
                        suffix: l.aiCreditsLeftSuffix),
                  ],
                ],
        ),
      ),
    );
  }
}

class _CreditBadge extends StatelessWidget {
  final int? remaining;
  final String suffix;
  const _CreditBadge({required this.remaining, required this.suffix});

  @override
  Widget build(BuildContext context) {
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
          hasCredits ? '${remaining ?? '…'} $suffix' : '5 TUCi',
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

class _PriceMetricCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color accent;
  const _PriceMetricCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.25))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(label,
                style:
                    const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }
}
