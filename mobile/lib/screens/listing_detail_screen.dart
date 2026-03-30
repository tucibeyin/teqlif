import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../models/listing_offer.dart';
import '../services/listing_service.dart';
import '../services/storage_service.dart';
import '../widgets/shimmer_loading.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';
import 'public_profile_screen.dart';
import 'messages_screen.dart';

class ListingDetailScreen extends StatefulWidget {
  final Map<String, dynamic> listing;
  const ListingDetailScreen({super.key, required this.listing});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen>
    with SingleTickerProviderStateMixin {
  int _currentImg = 0;
  late final PageController _pageCtrl;
  late final List<String> _images;
  int? _myUserId;
  bool _isFavorited = false;
  bool _isActive = true;

  // Beğeni state'i
  late int _likesCount;
  late bool _isLiked;
  bool _heartVisible = false;
  AnimationController? _heartAnimCtrl;

  // Teklif state'i
  final _offersNotifier = ValueNotifier<List<ListingOffer>>([]);
  bool _offersLoading = true;
  bool _offerSubmitting = false;
  bool _isLoggedIn = false; // token var mı (form gösterimi için)
  final _offerCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    final imgs = widget.listing['image_urls'] as List? ?? [];
    _images = imgs.cast<String>().map(imgUrl).toList();
    if (_images.isEmpty && widget.listing['image_url'] != null) {
      _images.add(imgUrl(widget.listing['image_url'] as String));
    }
    _isActive = widget.listing['is_active'] as bool? ?? true;
    _likesCount = widget.listing['likes_count'] as int? ?? 0;
    _isLiked = widget.listing['is_liked'] as bool? ?? false;
    _loadMyId();
    _loadOffers();
  }

  Future<void> _loadMyId() async {
    final info = await StorageService.getUserInfo();
    final token = await StorageService.getToken();
    if (!mounted) return;

    // Token varlığını hemen form gösterimi için kaydet
    if (token != null && !_isLoggedIn) {
      setState(() => _isLoggedIn = true);
    }

    int? userId = info?['id'] as int?;

    // Fallback: SharedPreferences'ta id yoksa ama token varsa backend'den çek
    if (userId == null && token != null) {
      try {
        final user = await AuthService.me();
        await StorageService.saveUserInfo(
          id: user.id,
          email: user.email,
          username: user.username,
          fullName: user.fullName,
        );
        userId = user.id;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _myUserId = userId);
    if (token != null && _myUserId != null) {
      final listingUserId = (widget.listing['user'] as Map?)?['id'];
      if (listingUserId != _myUserId) {
        _loadFavoriteStatus(token);
      }
    }
  }

  Future<void> _toggleLike() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    // Optimistic UI
    HapticFeedback.lightImpact();
    final prevLiked = _isLiked;
    final prevCount = _likesCount;
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });
    try {
      final result = await ListingService.toggleLike(widget.listing['id'] as int);
      final newCount = result['likes_count'] as int? ?? _likesCount;
      final newLiked = result['is_liked'] as bool? ?? _isLiked;
      widget.listing['likes_count'] = newCount;
      widget.listing['is_liked'] = newLiked;
      if (mounted) {
        setState(() {
          _likesCount = newCount;
          _isLiked = newLiked;
        });
      }
    } catch (_) {
      widget.listing['likes_count'] = prevCount;
      widget.listing['is_liked'] = prevLiked;
      if (mounted) setState(() { _isLiked = prevLiked; _likesCount = prevCount; });
    }
  }

  /// Galeriye çift tıklandığında büyüyüp kaybolan kalp animasyonu oynatır.
  /// Henüz beğenilmemişse otomatik olarak beğenir.
  Future<void> _triggerHeartAnimation() async {
    if (!_isLiked) _toggleLike();
    _heartAnimCtrl?.stop();
    _heartAnimCtrl?.dispose();
    _heartAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (!mounted) return;
    setState(() => _heartVisible = true);
    try {
      await _heartAnimCtrl!.forward();
    } catch (_) {}
    if (mounted) setState(() => _heartVisible = false);
    _heartAnimCtrl?.dispose();
    _heartAnimCtrl = null;
  }

  Future<void> _loadFavoriteStatus(String token) async {
    final id = widget.listing['id'];
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/favorites/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _isFavorited = data['is_favorited'] as bool? ?? false);
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'];
    try {
      if (_isFavorited) {
        await http.delete(
          Uri.parse('$kBaseUrl/favorites/$id'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (mounted) setState(() => _isFavorited = false);
      } else {
        await http.post(
          Uri.parse('$kBaseUrl/favorites/$id'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (mounted) setState(() => _isFavorited = true);
      }
    } catch (_) {}
  }

  Future<void> _toggleActive() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'];
    try {
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/listings/$id/toggle'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final newActive = data['is_active'] as bool? ?? !_isActive;
        setState(() => _isActive = newActive);
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newActive ? l.listingActivated : l.listingDeactivated)),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _heartAnimCtrl?.stop();
    _heartAnimCtrl?.dispose();
    _pageCtrl.dispose();
    _offerCtrl.dispose();
    _offersNotifier.dispose();
    super.dispose();
  }

  String _fmt(dynamic price) {
    if (price == null) return AppLocalizations.of(context)!.listingPriceNotSet;
    final s = (price as num).toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  // Noktalı formatı silerek double parse eder: "1.234" → 1234.0
  double? _parseFormattedPrice(String text) =>
      double.tryParse(text.trim().replaceAll('.', '').replaceAll(',', '.'));

  Future<void> _loadOffers() async {
    final id = widget.listing['id'] as int;
    try {
      final offers = await ListingService.getOffers(id);
      if (!mounted) return;
      _offersNotifier.value = offers;
    } finally {
      if (mounted) setState(() => _offersLoading = false);
    }
  }

  Future<void> _placeOffer() async {
    final l = AppLocalizations.of(context)!;
    final amount = _parseFormattedPrice(_offerCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.offerInvalidAmount)),
      );
      return;
    }
    setState(() => _offerSubmitting = true);
    try {
      final id = widget.listing['id'] as int;
      await ListingService.placeOffer(id, amount);
      if (!mounted) return;
      _offerCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.offerSuccess)),
      );
      final offers = await ListingService.getOffers(id);
      if (mounted) _offersNotifier.value = offers;
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.isNotEmpty ? msg : l.offerError)),
      );
    } finally {
      if (mounted) setState(() => _offerSubmitting = false);
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${diff.inDays} gün önce';
  }

  void _goToProfile() {
    final user = widget.listing['user'] as Map<String, dynamic>?;
    if (user == null) return;
    // Kendi ilanıysa kendi profil ekranına git (loop'u önle)
    if (_myUserId != null && user['id'] == _myUserId) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          username: user['username'] as String,
          userId: user['id'] as int?,
        ),
      ),
    );
  }

  void _openChat() async {
    final user = widget.listing['user'] as Map<String, dynamic>?;
    if (user == null) return;
    final otherId = user['id'] as int?;
    if (otherId == null) return;
    final l = AppLocalizations.of(context)!;

    if (_myUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.listingMsgLoginRequired)),
      );
      return;
    }
    if (_myUserId == otherId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.listingMsgOwnListing)),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DirectChatScreen(
          otherUserId: otherId,
          displayName: user['full_name'] as String? ??
              user['username'] as String? ?? '',
          otherHandle: user['username'] as String? ?? '',
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.dialogDeleteListingTitle),
        content: Text(l.listingDeleteConfirmContent),
        actions: [
          TextButton(
            key: const Key('listing_detail_dialog_btn_vazgec'),
            onPressed: () => Navigator.pop(context),
            child: Text(l.btnDismiss),
          ),
          TextButton(
            key: const Key('listing_detail_dialog_btn_sil'),
            onPressed: () async {
              Navigator.pop(context);
              await _deleteListing(context);
            },
            child: Text(l.listingDeleteConfirmYes, style: const TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteListing(BuildContext context) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'];
    try {
      final resp = await http.delete(
        Uri.parse('$kBaseUrl/listings/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        final detail = jsonDecode(resp.body)['detail'] ?? 'Bir hata oluştu';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (_) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorConnection)),
        );
      }
    }
  }

  void _openReport(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    String? selectedReason;
    final noteCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🚩 ${l.listingReportTitle}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('listing_detail_report_select_neden'),
                value: selectedReason,
                hint: Text(l.listingReportSelectHint),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  DropdownMenuItem(value: l.listingReportMisleading, child: Text(l.listingReportMisleading)),
                  DropdownMenuItem(value: l.listingReportIllegal, child: Text(l.listingReportIllegal)),
                  DropdownMenuItem(value: l.listingReportSpam, child: Text(l.listingReportSpam)),
                  DropdownMenuItem(value: l.listingReportInappropriate, child: Text(l.listingReportInappropriate)),
                  DropdownMenuItem(value: l.listingReportFraud, child: Text(l.listingReportFraud)),
                ],
                onChanged: (v) => setModalState(() => selectedReason = v),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('listing_detail_report_input_aciklama'),
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: l.listingReportNoteHint,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('listing_detail_report_btn_gonder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    if (selectedReason == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(l.listingReportSelectRequired)),
                      );
                      return;
                    }
                    final note = noteCtrl.text.trim();
                    final reason = selectedReason! + (note.isNotEmpty ? ': $note' : '');
                    Navigator.pop(ctx);
                    await _submitReport(reason);
                  },
                  child: Text(l.listingReportSubmitBtn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'];
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/reports'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'listing_id': id, 'reason': reason}),
      );
      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.listingReportSuccess)),
        );
      } else {
        final detail = jsonDecode(resp.body)['detail'] ?? 'Bir hata oluştu';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (_) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorConnection)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final listing = widget.listing;
    final user = listing['user'] as Map<String, dynamic>?;
    final isMine = _myUserId != null && user?['id'] == _myUserId;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        title: Text(
          listing['title'] ?? '',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (isMine) ...[
            IconButton(
              key: const Key('listing_detail_btn_aktif_toggle'),
              icon: Icon(
                _isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: _isActive ? const Color(0xFF6B7280) : kPrimary,
              ),
              tooltip: _isActive ? l.btnDeactivate : l.btnActivate,
              onPressed: _toggleActive,
            ),
            IconButton(
              key: const Key('listing_detail_btn_sil'),
              icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
              tooltip: l.listingDeleteTooltip,
              onPressed: () => _confirmDelete(context),
            ),
          ] else if (_myUserId != null) ...[
            IconButton(
              key: const Key('listing_detail_btn_favorile'),
              icon: Icon(
                _isFavorited ? Icons.favorite : Icons.favorite_border,
                color: _isFavorited ? Colors.red : const Color(0xFF9CA3AF),
              ),
              tooltip: _isFavorited ? l.btnRemoveFavorite : l.btnRemoveFavorite,
              onPressed: _toggleFavorite,
            ),
            IconButton(
              key: const Key('listing_detail_btn_sikayet'),
              icon: const Icon(Icons.flag_outlined, color: Color(0xFF9CA3AF), size: 22),
              tooltip: l.listingReportTooltip,
              onPressed: () => _openReport(context),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGallery(),

            // Başlık & Fiyat
            Container(
              color: AppColors.surface(context),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing['title'] ?? '',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fmt(listing['price']),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: kPrimary,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleLike,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              color: _isLiked ? Colors.red : AppColors.textSecondary(context),
                              size: 22,
                            ),
                            if (_likesCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '$_likesCount',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (listing['location'] != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 16, color: AppColors.textSecondary(context)),
                        const SizedBox(width: 4),
                        Text(
                          listing['location'],
                          style: TextStyle(
                              color: AppColors.textSecondary(context), fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Açıklama
            if (listing['description'] != null &&
                (listing['description'] as String).isNotEmpty)
              Container(
                color: AppColors.surface(context),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.listingDescriptionLabel,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(context))),
                    const SizedBox(height: 8),
                    Text(
                      listing['description'],
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary(context),
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // İlan Bilgileri
            Container(
              color: AppColors.surface(context),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.listingInfo,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context))),
                  const SizedBox(height: 12),
                  _infoRow('Kategori', listing['category'] ?? '-'),
                  if (listing['location'] != null)
                    _infoRow('Konum', listing['location']),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Satıcı — tıklanabilir
            if (user != null)
              InkWell(
                key: const Key('listing_detail_inkwell_satici'),
                onTap: _goToProfile,
                child: Container(
                  color: AppColors.surface(context),
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primaryBg(context),
                        child: Text(
                          ((user['full_name'] as String?) ??
                                  (user['username'] as String?) ??
                                  '?')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user['full_name'] ?? user['username'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              '@${user['username'] ?? ''}',
                              style: TextStyle(
                                  color: AppColors.textSecondary(context), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: AppColors.textSecondary(context), size: 20),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),

            // Teklif Ver / Teklif Geçmişi
            Container(
              color: AppColors.surface(context),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.offerHistory,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  // Form — sadece ilan sahibi değilse + giriş yapılmışsa
                  if (!isMine && _isLoggedIn) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('listing_detail_offer_input'),
                            controller: _offerCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [_PriceInputFormatter()],
                            decoration: InputDecoration(
                              hintText: l.offerAmountHint,
                              prefixText: '₺ ',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          key: const Key('listing_detail_offer_btn'),
                          onPressed: _offerSubmitting ? null : _placeOffer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            minimumSize: Size.zero, // global tema override: Row içinde sonsuz genişliği önler
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13,
                            ),
                          ),
                          child: _offerSubmitting
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  l.offerBtn,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                        ),
                      ],
                    ),
                  ],
                  if (!isMine && !_isLoggedIn) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.offerLoginRequired,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ValueListenableBuilder<List<ListingOffer>>(
                    valueListenable: _offersNotifier,
                    builder: (context, offers, _) {
                      if (_offersLoading) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      if (offers.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l.offerEmpty,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        );
                      }
                      // Bir teklif yaklaşık 50px yer kaplıyor. 5 teklif = ~250px.
                      return ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 250, // Max 5 öğe için
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            children: offers
                                .map((o) => _buildOfferRow(context, o))
                                .toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 90),
          ],
        ),
      ),
      bottomNavigationBar: isMine
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  key: const Key('listing_detail_btn_mesaj_gonder'),
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: Text(l.listingSendMessage),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildGallery() {
    if (_images.isEmpty) {
      return Builder(
        builder: (context) => Container(
          height: 260,
          color: AppColors.surfaceVariant(context),
          child: Center(
            child: Icon(Icons.image_outlined,
                size: 64, color: AppColors.border(context)),
          ),
        ),
      );
    }

    return Stack(
      children: [
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _images.length,
            onPageChanged: (i) => setState(() => _currentImg = i),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => _openFullscreen(i),
              onDoubleTap: _triggerHeartAnimation,
              child: CachedNetworkImage(
                imageUrl: _images[i],
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, __) => const ShimmerBox(),
                errorWidget: (ctx, url, err) {
                  debugPrint('IMG HATA [$url]: $err');
                  return Container(
                    color: AppColors.surfaceVariant(ctx),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_outlined,
                            size: 48, color: AppColors.border(ctx)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _images[i],
                            style: TextStyle(
                                fontSize: 9, color: AppColors.textTertiary(ctx)),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (_images.length > 1 && _currentImg > 0)
          Positioned(
            left: 8, top: 0, bottom: 0,
            child: Center(child: _arrowBtn(Icons.chevron_left, -1)),
          ),
        if (_images.length > 1 && _currentImg < _images.length - 1)
          Positioned(
            right: 8, top: 0, bottom: 0,
            child: Center(child: _arrowBtn(Icons.chevron_right, 1)),
          ),
        if (_images.length > 1)
          Positioned(
            bottom: 10, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentImg + 1}/${_images.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        // Çift tıklama kalp animasyonu
        if (_heartVisible && _heartAnimCtrl != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _heartAnimCtrl!,
                  builder: (_, __) {
                    final t = _heartAnimCtrl!.value;
                    final double scale;
                    if (t < 0.4) {
                      scale = (t / 0.4) * 1.3;
                    } else if (t < 0.6) {
                      scale = 1.3 - ((t - 0.4) / 0.2) * 0.3;
                    } else {
                      scale = 1.0;
                    }
                    final opacity =
                        t < 0.6 ? 1.0 : 1.0 - ((t - 0.6) / 0.4).clamp(0.0, 1.0);
                    return Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.white,
                          size: 90,
                          shadows: [Shadow(color: Colors.black38, blurRadius: 24)],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _arrowBtn(IconData icon, int dir) => GestureDetector(
        onTap: () => _pageCtrl.animateToPage(
          _currentImg + dir,
          duration: const Duration(milliseconds: 250),
          curve: Curves.ease,
        ),
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );

  Widget _infoRow(String label, String value) => Builder(
        builder: (context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13,
                      color: AppColors.textPrimary(context))),
            ),
          ],
        ),
      ));

  Widget _buildOfferRow(BuildContext context, ListingOffer offer) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PublicProfileScreen(
            username: offer.username,
            userId: offer.userId,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryBg(context),
              child: Text(
                offer.username.isNotEmpty
                    ? offer.username[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${offer.username}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13,
                    ),
                  ),
                  Text(
                    _timeAgo(offer.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _fmt(offer.amount),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: kPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullscreen(int startIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _FullscreenGallery(images: _images, initial: startIndex),
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  final List<String> images;
  final int initial;
  const _FullscreenGallery({required this.images, required this.initial});

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late int _current;
  late final PageController _ctrl;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _ctrl = PageController(initialPage: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.images.length}',
            style: const TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.images[i],
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
              errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kullanıcının girdiği rakamları Türkçe binlik nokta formatına çevirir.
/// Örnek: "1234567" → "1.234.567"
class _PriceInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Sadece rakamları al
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');

    // Binlik nokta ekle (_fmt ile aynı algoritma)
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
