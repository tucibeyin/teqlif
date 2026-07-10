import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'retargeting_screen.dart';
import '../config/api.dart';
import '../services/analytics_service.dart';
import '../services/image_cache_manager.dart';
import '../services/share_service.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../widgets/async_button.dart';
import '../models/listing_offer.dart';
import '../services/cache_service.dart';
import '../services/listing_service.dart';
import '../services/storage_service.dart';
import '../widgets/shimmer_loading.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';
import 'public_profile_screen.dart';
import 'edit_listing_screen.dart';
import 'messages_screen.dart';
import 'ad_report_screen.dart';

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
  int? _campaignId;

  // Toplu Kitle Bildirimi (Mass Notification)
  bool _massNotificationSending = false;
  bool _cooldownLoading = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  // Scroll depth tracking
  late final ScrollController _scrollCtrl;
  double _maxScrollDepth = 0.0; // 0.0–1.0

  // Video player
  String? _videoUrl;
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;
  bool _videoInitialized = false;

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
  bool _offerFieldTouched = false; // teklif yazılıp submit edilmeden çıkıldı mı
  double? _offerTypedAmount;

  // Dwell süresi ölçümü
  late final DateTime _enteredAt;

  // Galeri + video analytics
  int _maxPhotoReached = 0;

  List<Map<String, dynamic>> _similarListings = [];

  @override
  void initState() {
    super.initState();
    _enteredAt = DateTime.now();
    _pageCtrl = PageController();
    final imgs = widget.listing['image_urls'] as List? ?? [];
    _images = imgs.cast<String>().map(imgUrl).toList();
    if (_images.isEmpty && widget.listing['image_url'] != null) {
      _images.add(imgUrl(widget.listing['image_url'] as String));
    }
    _isActive = widget.listing['is_active'] as bool? ?? true;
    _likesCount = widget.listing['likes_count'] as int? ?? 0;
    _isLiked = widget.listing['is_liked'] as bool? ?? false;
    _videoUrl = widget.listing['video_url'] as String?;
    _campaignId = widget.listing['campaign_id'] as int?;
    if (_videoUrl != null) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(imgUrl(_videoUrl!)));
      _videoCtrl!.initialize().then((_) {
        if (!mounted) return;
        _chewieCtrl = ChewieController(
          videoPlayerController: _videoCtrl!,
          autoPlay: widget.listing['is_highlight'] == true,
          looping: widget.listing['is_highlight'] == true,
          allowFullScreen: true,
          allowMuting: true,
          showControls: true,
        );
        setState(() => _videoInitialized = true);
      });
    }
    _scrollCtrl = ScrollController()
      ..addListener(() {
        final pos = _scrollCtrl.position;
        if (pos.maxScrollExtent > 0) {
          final depth = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
          if (depth > _maxScrollDepth) _maxScrollDepth = depth;
        }
      });
    _loadMyId();
    _loadOffers();
    _loadSimilarListings();
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
          isPremium: user.isPremium,
          onboardingCompleted: user.onboardingCompleted,
          isVerified: user.isVerified,
          phoneVerified: user.phoneVerified,
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
        _recordView(token);
      } else {
        // İlanın sahibiyiz — taze kampanya durumunu çek + bildirim cooldown'unu yükle
        _refreshCampaignStatus(token);
        final listingId = widget.listing['id'] as int?;
        if (listingId != null) {
          setState(() => _cooldownLoading = true);
          _loadNotificationCooldown(listingId);
        }
      }
    }
  }

  Future<void> _loadNotificationCooldown(int listingId) async {
    final secs = await AnalyticsService.getNotificationCooldown(listingId);
    if (!mounted) return;
    setState(() {
      _cooldownLoading = false;
      _cooldownSeconds = secs > 0 ? secs : 0;
    });
    if (secs > 0) _startCooldownTimer();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _cooldownTimer?.cancel(); return; }
      setState(() {
        if (_cooldownSeconds > 0) {
          _cooldownSeconds--;
        } else {
          _cooldownTimer?.cancel();
        }
      });
    });
  }

  String _formatCooldown(int totalSeconds) {
    final l = AppLocalizations.of(context)!;
    if (totalSeconds >= 3600) {
      return l.massNotifCooldownHours(totalSeconds ~/ 3600, (totalSeconds % 3600) ~/ 60);
    } else if (totalSeconds >= 60) {
      return l.massNotifCooldownMinutes(totalSeconds ~/ 60);
    } else {
      return l.massNotifCooldownSeconds(totalSeconds);
    }
  }

  Future<void> _recordView(String token) async {
    final id = widget.listing['id'];
    if (id == null) return;
    try {
      await http.post(
        Uri.parse('$kBaseUrl/listings/$id/view'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {}
  }

  Future<void> _refreshCampaignStatus(String token) async {
    final id = widget.listing['id'];
    if (id == null) return;
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final freshId = data['campaign_id'] as int?;
        if (freshId != _campaignId) {
          setState(() => _campaignId = freshId);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    // Optimistic UI
    HapticFeedback.lightImpact();
    final listingId = widget.listing['id'] as int?;
    final rawPrice = widget.listing['price'];
    final pricePoint = rawPrice != null ? (rawPrice as num).toDouble() : null;
    final prevLiked = _isLiked;
    final prevCount = _likesCount;
    final prevFav = _isFavorited;
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
      // Beğeni ve favori senkron: beğenince favori de güncellenir
      _isFavorited = _isLiked;
    });
    try {
      final id = widget.listing['id'] as int;
      final result = await ListingService.toggleLike(id);
      final newCount = result['likes_count'] as int? ?? _likesCount;
      final newLiked = result['is_liked'] as bool? ?? _isLiked;
      widget.listing['likes_count'] = newCount;
      widget.listing['is_liked'] = newLiked;
      // Favorites API ile senkronize et — beğeni = favoriye ekle/çıkar
      if (newLiked) {
        await http.post(
          Uri.parse('$kBaseUrl/favorites/$id'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } else {
        await http.delete(
          Uri.parse('$kBaseUrl/favorites/$id'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      if (mounted) {
        setState(() {
          _likesCount = newCount;
          _isLiked = newLiked;
          _isFavorited = newLiked;
        });
        if (listingId != null) {
          AnalyticsService.logInteraction(
            itemId: listingId,
            itemType: 'listing',
            interactionType: newLiked ? 'listing_like' : 'listing_unlike',
            pricePoint: pricePoint,
          );
        }
      }
    } catch (_) {
      widget.listing['likes_count'] = prevCount;
      widget.listing['is_liked'] = prevLiked;
      if (mounted) {
        setState(() {
          _isLiked = prevLiked;
          _likesCount = prevCount;
          _isFavorited = prevFav;
        });
      }
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
        final isFav = data['is_favorited'] as bool? ?? false;
        setState(() {
          _isFavorited = isFav;
          if (isFav) _isLiked = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'] as int?;
    final rawPrice = widget.listing['price'];
    final pricePoint = rawPrice != null ? (rawPrice as num).toDouble() : null;
    try {
      if (_isFavorited) {
        await http.delete(
          Uri.parse('$kBaseUrl/favorites/$id'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (mounted) {
          setState(() { _isFavorited = false; _isLiked = false; });
          if (id != null) AnalyticsService.logInteraction(itemId: id, itemType: 'listing', interactionType: 'listing_unfavorite', pricePoint: pricePoint);
        }
      } else {
        await http.post(
          Uri.parse('$kBaseUrl/favorites/$id'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (mounted) {
          setState(() { _isFavorited = true; _isLiked = true; });
          if (id != null) AnalyticsService.logInteraction(itemId: id, itemType: 'listing', interactionType: 'listing_favorite', pricePoint: pricePoint);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleActive() async {
    if (!mounted) return;
    final l  = AppLocalizations.of(context)!;
    final id = widget.listing['id'] as int;

    final costData = await ListingService.getReactivationCost(id);
    if (!mounted) return;

    final isPremium    = costData?['is_premium']    as bool? ?? false;
    final remaining    = costData?['free_remaining'] as int?  ?? 0;
    final cost         = costData?['cost']           as int?  ?? 10;
    final balance      = costData?['balance']        as int?  ?? 0;
    final canAfford    = costData?['can_afford']     as bool? ?? false;
    final withinWindow = costData?['within_window']  as bool? ?? false;

    if (_isActive) {
      // Aktif → Pasif
      if (!withinWindow) {
        final hintText = (isPremium && remaining > 0) 
            ? l.listingDeactivateFreeCreditHint 
            : l.listingDeactivateCostHint(cost);

        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l.listingDeactivateTitle),
            content: Text('${l.listingDeactivateWarning}\n\n$hintText'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.btnDismiss)),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.listingDeactivateConfirm, style: const TextStyle(color: Color(0xFFDC2626))),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }
    } else {
      // Pasif → Aktif
      if (!withinWindow) {
        if (!canAfford) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(l.listingReactivateTitle),
              content: Text(l.listingReactivateInsufficientBalance),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l.btnDismiss)),
              ],
            ),
          );
          return;
        }

        String subtitle;
        if (isPremium && remaining > 0) {
          subtitle = l.listingReactivateFreeCredit(remaining);
        } else if (isPremium) {
          subtitle = l.listingReactivatePaidPro(cost);
        } else {
          subtitle = l.listingReactivatePaidNormal(cost, balance);
        }
        if (!isPremium) subtitle += '\n\n${l.listingReactivateProUpsell}';

        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l.listingReactivateTitle),
            content: Text(subtitle),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.btnDismiss)),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.listingReactivateConfirm, style: const TextStyle(color: Color(0xFF6366F1))),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }
    }

    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/listings/$id/toggle'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final newActive = data['is_active'] as bool? ?? !_isActive;
        setState(() => _isActive = newActive);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newActive ? l.listingActivated : l.listingDeactivated)),
        );
      } else if (resp.statusCode == 402 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.listingReactivateInsufficientBalance)),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final durationSec = DateTime.now().difference(_enteredAt).inSeconds.toDouble();
    final listingId = widget.listing['id'] as int?;
    final rawPrice = widget.listing['price'];
    final pricePoint = rawPrice != null ? (rawPrice as num).toDouble() : null;
    if (listingId != null && durationSec >= 2) {
      AnalyticsService.logInteraction(
        itemId: listingId,
        itemType: 'listing',
        interactionType: 'view',
        durationSeconds: durationSec,
        pricePoint: pricePoint,
      );
    }
    // Detail dwell: kullanıcı 30+ saniye harcadıysa güçlü ilgi sinyali
    if (listingId != null && durationSec >= 30) {
      AnalyticsService.logInteraction(
        itemId: listingId,
        itemType: 'listing',
        interactionType: 'detail_dwell',
        durationSeconds: durationSec,
        pricePoint: pricePoint,
      );
    }
    // Photo swipe depth
    if (listingId != null && _maxPhotoReached > 0) {
      AnalyticsService.logInteraction(
        itemId: listingId,
        itemType: 'listing',
        interactionType: 'listing_photo_swipe',
        durationSeconds: _maxPhotoReached.toDouble(),
      );
    }
    // Scroll depth
    if (listingId != null && _maxScrollDepth > 0.1) {
      AnalyticsService.logInteraction(
        itemId: listingId,
        itemType: 'listing',
        interactionType: 'listing_scroll_depth',
        durationSeconds: _maxScrollDepth,
      );
    }
    _scrollCtrl.dispose();
    // Video completion
    if (listingId != null && _videoCtrl != null && _videoInitialized) {
      final dur = _videoCtrl!.value.duration.inMilliseconds;
      if (dur > 0) {
        final pos = _videoCtrl!.value.position.inMilliseconds;
        final pct = (pos / dur).clamp(0.0, 1.0);
        if (pct > 0.01) {
          AnalyticsService.logInteraction(
            itemId: listingId,
            itemType: 'listing',
            interactionType: 'listing_video_watch',
            durationSeconds: pct,
          );
        }
      }
    }
    _heartAnimCtrl?.stop();
    _heartAnimCtrl?.dispose();
    _cooldownTimer?.cancel();
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    _pageCtrl.dispose();
    if (_offerFieldTouched) {
      final id = widget.listing['id'] as int?;
      if (id != null) {
        AnalyticsService.logInteraction(
          itemId: id,
          itemType: 'listing',
          interactionType: 'bid_hesitation',
          pricePoint: _offerTypedAmount,
        );
      }
    }
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

  Future<void> _loadSimilarListings() async {
    final lid = widget.listing['id'];
    if (lid == null) return;
    try {
      final token = await StorageService.getToken();
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/$lid/similar'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as List;
        setState(() => _similarListings = data.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
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
      _offerFieldTouched = false;
      _offerTypedAmount = null;
      AnalyticsService.logInteraction(
        itemId: id,
        itemType: 'listing',
        interactionType: 'listing_offer_submit',
        pricePoint: amount.toDouble(),
      );
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
    if (diff.inSeconds < 60) return AppLocalizations.of(context)!.timeJustNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${diff.inDays} gün önce';
  }

  void _goToProfile() {
    final user = widget.listing['user'] as Map<String, dynamic>?;
    if (user == null) return;
    final sellerId = user['id'] as int?;
    if (sellerId != null && sellerId != _myUserId) {
      AnalyticsService.logInteraction(
        itemId: widget.listing['id'] as int? ?? 0,
        itemType: 'listing',
        interactionType: 'listing_profile_tap',
        metadata: {'seller_id': sellerId},
      );
    }
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

    AnalyticsService.logInteraction(
      itemId: widget.listing['id'] as int? ?? 0,
      itemType: 'listing',
      interactionType: 'listing_chat_open',
      metadata: {'seller_id': otherId},
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DirectChatScreen(
          otherUserId: otherId,
          displayName: user['full_name'] as String? ??
              user['username'] as String? ?? '',
          otherHandle: user['username'] as String? ?? '',
          listingId: widget.listing['id'] as int?,
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
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final connErr = AppLocalizations.of(context)!.errorConnection;
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
        nav.pop(true);
      } else {
        final detail = jsonDecode(resp.body)['detail'] ?? AppLocalizations.of(context)?.errSomethingWentWrong ?? 'Error';
        messenger.showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(connErr)));
      }
    }
  }

  void _openAdReport(BuildContext context) {
    final campaignId = _campaignId;
    if (campaignId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdReportScreen(
          campaignId: campaignId,
          listingTitle: widget.listing['title'] as String? ?? AppLocalizations.of(context)!.lblListingUpper,
        ),
      ),
    );
  }


  Future<void> _sendMassNotification(BuildContext ctx) async {
    setState(() => _massNotificationSending = true);
    final listingId = widget.listing['id'] as int;

    // Hedef kitle büyüklüğünü çek
    final est = await AnalyticsService.estimateAudienceForListing(listingId);
    if (est == null || !mounted) {
      setState(() => _massNotificationSending = false);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.audienceCalcError)));
      return;
    }

    final maxAudience = est['audience_size'] as int? ?? 0;
    if (maxAudience == 0) {
      setState(() => _massNotificationSending = false);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.audienceNoPotentialFound)));
      return;
    }

    final creditsLeft = est['blast_credits_remaining'] as int? ?? 0;
    final perBlastCap = est['per_blast_cap'] as int? ?? maxAudience;
    final tuciBalance = est['tuci_balance'] as int? ?? 0;
    setState(() => _massNotificationSending = false);

    // Onay penceresi (Akıllı Modal)
    final result = await showDialog<Map<String, int>>(
      context: ctx,
      builder: (_) => _MassNotificationDialog(
        maxAudience: maxAudience,
        creditsLeft: creditsLeft,
        perBlastCap: perBlastCap,
        tuciBalance: tuciBalance,
      ),
    );

    if (result == null || !mounted) return;

    setState(() => _massNotificationSending = true);
    final apiResult = await AnalyticsService.sendMassNotificationForListing(
      listingId: listingId,
      estimatedCost: result['cost']!,
      recipientCount: result['count']!,
    );
    if (!mounted) return;
    setState(() => _massNotificationSending = false);

    if (apiResult != null && apiResult['cooldown'] == true) {
      final secs = (apiResult['seconds_remaining'] as num?)?.toInt() ?? 86400;
      setState(() => _cooldownSeconds = secs);
      _startCooldownTimer();
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(_formatCooldown(secs))),
      );
    } else if (apiResult != null && apiResult.containsKey('error')) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(apiResult['error'] as String)));
    } else if (apiResult != null) {
      CacheService.clearData('user_wallet_data');
      setState(() => _cooldownSeconds = 86400);
      _startCooldownTimer();
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.audienceMassSendSuccess),
        backgroundColor: const Color(0xFF14B8A6),
      ));
    } else {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.audienceMassSendError)));
    }
  }


  void _openMassNotificationReport(BuildContext ctx) {
    final listingId = widget.listing['id'] as int?;
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => RetargetingScreen(initialIndex: 1, listingId: listingId),
      ),
    );
  }


  Future<void> _boostListing(BuildContext ctx) async {
    final boostMessenger = ScaffoldMessenger.of(ctx);
    final l = AppLocalizations.of(ctx)!;
    // Önce boost kredi durumunu çek
    int remaining = 0;
    int limit = 0;
    bool isPro = false;
    int tuciBalance = 0;
    
    // Check loading state while fetching data — spinner shown by AsyncElevatedButton
    
    try {
      final token = await StorageService.getToken();
      final cr = await http.get(
        Uri.parse('$kBaseUrl/ads/boost-credits'),
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );
      if (cr.statusCode == 200) {
        final d = jsonDecode(cr.body) as Map<String, dynamic>;
        remaining = (d['remaining'] as num).toInt();
        limit     = (d['limit'] as num).toInt();
        isPro     = d['is_pro'] == true;
        // TUCi bakiyesini de çek
        final tokenInner = await StorageService.getToken();
        final ur = await http.get(
          Uri.parse('$kBaseUrl/users/me'),
          headers: {if (tokenInner != null) 'Authorization': 'Bearer $tokenInner'},
        );
        if (ur.statusCode == 200) {
          final ud = jsonDecode(ur.body) as Map<String, dynamic>;
          tuciBalance = ((ud['wallet_balance'] ?? 0) as num).toInt();
        }
      }
    } catch (_) {}

    if (!mounted) return;

    // Pro değilse bilgilendir
    if (!isPro) {
      boostMessenger.showSnackBar(SnackBar(
        content: Text(l.boostOnlyPro),
        backgroundColor: const Color(0xFFF97316),
      ));
      return;
    }

    // Ücretli veya ücretsiz boost dialog'ını göster
    final bool isFreeMode = remaining > 0;

    // ignore: use_build_context_synchronously
    showDialog<void>(
      context: ctx,
      builder: (dlgCtx) {
        final dl = AppLocalizations.of(dlgCtx)!;
        
        Future<void> performBoost() async {
          final token = await StorageService.getToken();
          try {
            final resp = await http.post(
              Uri.parse('$kBaseUrl/ads/campaigns'),
              headers: {
                'Content-Type': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'listing_id': widget.listing['id'],
                'total_budget': 50,
                'cpc_bid': 1,
              }),
            );
            if (!mounted) return;
            Navigator.pop(dlgCtx);
            final ll = AppLocalizations.of(ctx)!;
            if (resp.statusCode == 201) {
              final data = jsonDecode(resp.body) as Map<String, dynamic>;
              final wasFree = data['is_free'] == true;
              CacheService.clearData('user_wallet_data');
              setState(() {
                _campaignId = data['id'] as int?;
                widget.listing['campaign_id'] = _campaignId;
                widget.listing['is_sponsored'] = true;
              });
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(wasFree ? ll.boostSuccessFree : ll.boostSuccessPaid),
                backgroundColor: const Color(0xFFF97316),
              ));
            } else {
              final body = jsonDecode(resp.body) as Map<String, dynamic>;
              final msg = body['detail'] ?? ll.boostErrorDefault;
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(msg.toString()),
                backgroundColor: resp.statusCode == 402 ? const Color(0xFFDC2626) : null,
              ));
            }
          } catch (_) {
            if (mounted) {
              final ll = AppLocalizations.of(ctx)!;
              Navigator.pop(dlgCtx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(ll.boostErrorConnection)),
              );
            }
          }
        }
        if (isFreeMode) {
          // Ücretsiz boost dialog'ı
          return AlertDialog(
            title: Text(dl.boostDialogTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dl.boostDialogPlanLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 10),
                _BoostRow(icon: Icons.account_balance_wallet_outlined, label: dl.boostDialogTotalBudget, value: dl.boostDialogTotalBudgetValue),
                _BoostRow(icon: Icons.ads_click, label: dl.boostDialogCpc, value: dl.boostDialogCpcValue),
                _BoostRow(icon: Icons.touch_app_outlined, label: dl.boostDialogEstClicks, value: dl.boostDialogEstClicksValue),
                const SizedBox(height: 12),
                Text(
                  dl.boostDialogFeedHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dl.boostDialogCredits(remaining, limit),
                    style: const TextStyle(fontSize: 12, color: Color(0xFFF97316), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: Text(dl.btnCancel)),
              AsyncElevatedButton(
                onPressed: performBoost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                ),
                child: Text(dl.boostDialogStart),
              ),
            ],
          );
        } else {
          // Ücretli boost dialog'ı — kredit bitti
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.monetization_on_rounded, color: Color(0xFF6366F1), size: 20),
                const SizedBox(width: 8),
                Text(dl.boostDialogPaidTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dl.boostDialogPaidBadge(limit),
                    style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                Text(dl.boostDialogPaidDesc, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 12),
                _BoostRow(icon: Icons.price_change_outlined, label: dl.boostDialogPaidCost, value: dl.boostDialogPaidCostValue),
                _BoostRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: dl.boostDialogPaidBalance,
                  value: '$tuciBalance TUCi',
                  valueColor: tuciBalance >= 50 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: Text(dl.btnCancel)),
              ElevatedButton(
                onPressed: tuciBalance >= 50 ? () => Navigator.pop(dlgCtx, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: Text(dl.boostDialogPaidConfirm),
              ),
            ],
          );
        }
      },
    );
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
                // ignore: deprecated_member_use
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
                child: AsyncElevatedButton(
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
        final detail = jsonDecode(resp.body)['detail'] ?? AppLocalizations.of(context)?.errSomethingWentWrong ?? 'Error';
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
          Builder(
            builder: (btnCtx) => IconButton(
              key: const Key('listing_detail_btn_paylasım'),
              icon: const Icon(Icons.share_outlined),
              tooltip: l.btnShare,
              onPressed: () {
                final id = listing['id'] as int?;
                final box = btnCtx.findRenderObject() as RenderBox?;
                final origin = box == null
                    ? Rect.zero
                    : box.localToGlobal(Offset.zero) & box.size;
                final imageUrl = (_images.isNotEmpty) ? _images.first : null;
                if (id != null) {
                  AnalyticsService.logInteraction(
                    itemId: id,
                    itemType: 'listing',
                    interactionType: 'listing_share',
                  );
                }
                ShareService.show(
                  btnCtx,
                  url: 'https://www.teqlif.com/ilan/$id',
                  text: l.shareListingText(listing['title'] ?? ''),
                  imageUrl: imageUrl,
                  origin: origin,
                );
              },
            ),
          ),
          if (isMine) ...[
            IconButton(
              key: const Key('listing_detail_btn_edit'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: l.editListingTitle,
              onPressed: () async {
                final updated = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => EditListingScreen(listing: listing)),
                );
                if (updated == true) {
                  if (!context.mounted) return;
                  // Reload by pushing loader
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => ListingDeepLinkLoader(listingId: listing['id'])),
                  );
                }
              },
            ),
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
                (_isFavorited || _isLiked) ? Icons.favorite : Icons.favorite_border,
                color: (_isFavorited || _isLiked) ? Colors.red : const Color(0xFF9CA3AF),
              ),
              tooltip: _isFavorited ? l.btnRemoveFavorite : l.btnAddFavorite,
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
        controller: _scrollCtrl,
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
                      // Fiyat yanı — beğeni sayısı, kişisel beğeni durumu ve (varsa) unique erişim
                      if (_likesCount > 0 || _isLiked || listing['impression_count'] != null)
                        Builder(builder: (ctx) {
                          final l = AppLocalizations.of(ctx)!;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (listing['impression_count'] != null) ...[
                                Icon(
                                  Icons.people_outline,
                                  color: AppColors.textSecondary(context),
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l.listingReach(listing['impression_count'] as int),
                                  style: TextStyle(
                                    color: AppColors.textSecondary(context),
                                    fontSize: 13,
                                  ),
                                ),
                                if (_likesCount > 0 || _isLiked)
                                  const SizedBox(width: 12),
                              ],
                            if (_likesCount > 0 || _isLiked) ...[
                              Icon(
                                _isLiked ? Icons.favorite : Icons.favorite_border,
                                color: _isLiked
                                    ? Colors.red
                                    : Colors.red.withValues(alpha: 0.5),
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_likesCount',
                                style: TextStyle(
                                  color: _isLiked
                                      ? Colors.red
                                      : AppColors.textSecondary(context),
                                  fontSize: 13,
                                  fontWeight: _isLiked
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              ],
                            ],
                          );
                        }),
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
                            if ((user['is_verified'] as bool? ?? false) ||
                                (user['is_premium'] as bool? ?? false)) ...[
                              Wrap(
                                spacing: 4,
                                children: [
                                  if (user['is_verified'] == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        const FaIcon(FontAwesomeIcons.circleCheck, size: 8, color: Colors.white),
                                        const SizedBox(width: 3),
                                        Text(AppLocalizations.of(context)!.badgeVerified,
                                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                                      ]),
                                    ),
                                  if (user['is_premium'] == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        FaIcon(FontAwesomeIcons.crown, size: 8, color: Colors.white),
                                        SizedBox(width: 3),
                                        Text('PRO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                                      ]),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                            ],
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
                            _SellerTrustRow(user: user),
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
                            onChanged: (val) {
                              final parsed = _parseFormattedPrice(val);
                              if (parsed != null && parsed > 0) {
                                _offerFieldTouched = true;
                                _offerTypedAmount = parsed;
                              } else if (val.isEmpty) {
                                _offerFieldTouched = false;
                                _offerTypedAmount = null;
                              }
                            },
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
            if (_similarListings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  AppLocalizations.of(context)!.similarListings,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(
                height: 172,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _similarListings.length,
                  itemBuilder: (ctx, i) {
                    final item = _similarListings[i];
                    final imgs = item['image_urls'] as List? ?? [];
                    final rawPhoto = imgs.isNotEmpty ? imgs[0] as String : item['image_url'] as String?;
                    final photo = rawPhoto != null ? imgUrl(rawPhoto) : null;
                    return GestureDetector(
                      onTap: () => Navigator.push(ctx, MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listing: Map<String, dynamic>.from(item)),
                      )),
                      child: Container(
                        width: 110,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.card(context),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: photo != null
                                ? CachedNetworkImage(cacheManager: TeqlifCacheManager(), imageUrl: photo,
 fit: BoxFit.cover, width: double.infinity)
                                : Container(color: AppColors.surfaceVariant(context)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title'] ?? '',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (item['price'] != null)
                                    Text(
                                      '${(item['price'] as num).toInt()} ₺',
                                      style: const TextStyle(fontSize: 11, color: kPrimary, fontWeight: FontWeight.w700),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 90),
          ],
        ),
      ),
      bottomNavigationBar: isMine
          ? (!_isActive && _campaignId == null)
              ? const SizedBox.shrink()
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Builder(builder: (ctx) {
                    final l = AppLocalizations.of(ctx)!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: (_massNotificationSending || _cooldownLoading)
                              ? null
                              : _cooldownSeconds > 0
                                  ? () => _openMassNotificationReport(context)
                                  : () => _sendMassNotification(context),
                          icon: (_massNotificationSending || _cooldownLoading)
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : _cooldownSeconds > 0
                                  ? const Icon(Icons.auto_graph, size: 18)
                                  : const Text('📢', style: TextStyle(fontSize: 16)),
                          label: Text(_cooldownLoading ? '' : _cooldownSeconds > 0 ? l.btnViewNotificationReport : l.btnSendMassNotification),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF14B8A6),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0x6614B8A6),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_cooldownSeconds > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              _formatCooldown(_cooldownSeconds),
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 8),
                        _campaignId != null
                            ? ElevatedButton.icon(
                                onPressed: () => _openAdReport(context),
                                icon: const Text('📊', style: TextStyle(fontSize: 16)),
                                label: Text(l.boostBtnReport),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              )
                            : AsyncElevatedButton(
                                onPressed: () => _boostListing(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF97316),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('🔥', style: TextStyle(fontSize: 16)),
                                    const SizedBox(width: 8),
                                    Text(l.boostBtnStart),
                                  ],
                                ),
                              ),
                      ],
                    );
                  }),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Mesaj gönder butonu (expanded — sola yaslanır)
                    Expanded(
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
                    const SizedBox(width: 8),
                    // Beğeni butonu (sağda sabit genişlik)
                    OutlinedButton(
                      key: const Key('listing_detail_btn_begeni'),
                      onPressed: _myUserId != null ? _toggleLike : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(56, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                          color: _isLiked ? Colors.red : AppColors.border(context),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked
                                ? Colors.red
                                : AppColors.textSecondary(context),
                            size: 22,
                          ),
                          if (_likesCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '$_likesCount',
                              style: TextStyle(
                                color: _isLiked
                                    ? Colors.red
                                    : AppColors.textSecondary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildVideoPlayer() {
    return GestureDetector(
      onDoubleTap: _triggerHeartAnimation,
      child: Chewie(controller: _chewieCtrl!),
    );
  }

  Widget _buildGallery() {
    final bool hasVideo = _videoUrl != null;
    final int total = _images.length + (hasVideo ? 1 : 0);

    if (total == 0) {
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
            itemCount: total,
            onPageChanged: (i) {
              setState(() => _currentImg = i);
              if (hasVideo && i != 0) _videoCtrl?.pause();
              if (i > _maxPhotoReached) _maxPhotoReached = i;
            },
            itemBuilder: (context, i) {
              if (hasVideo && i == 0) {
                if (_videoInitialized && _videoCtrl != null) {
                  return _buildVideoPlayer();
                }
                return const ShimmerBox();
              }
              final imgIdx = hasVideo ? i - 1 : i;
              return GestureDetector(
                onTap: () => _openFullscreen(imgIdx),
                onDoubleTap: _triggerHeartAnimation,
                child: CachedNetworkImage(
                  imageUrl: _images[imgIdx],
                  cacheManager: TeqlifCacheManager(),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (_, _) => const ShimmerBox(),
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
                              _images[imgIdx],
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
              );
            },
          ),
        ),
        if (total > 1 && _currentImg > 0)
          Positioned(
            left: 8, top: 0, bottom: 0,
            child: Center(child: _arrowBtn(Icons.chevron_left, -1)),
          ),
        if (total > 1 && _currentImg < total - 1)
          Positioned(
            right: 8, top: 0, bottom: 0,
            child: Center(child: _arrowBtn(Icons.chevron_right, 1)),
          ),
        if (total > 1)
          Positioned(
            bottom: 10, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentImg + 1}/$total',
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
                  builder: (_, _) {
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
    final listingId = widget.listing['id'] as int?;
    if (listingId != null) {
      AnalyticsService.logInteraction(
        itemId: listingId,
        itemType: 'listing',
        interactionType: 'listing_photo_fullscreen',
        metadata: {'photo_index': startIndex},
      );
    }
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
              cacheManager: TeqlifCacheManager(),
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
              errorWidget: (_, _, _) => const Icon(
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

/// Deep link ile sadece ilan ID'si geldiğinde kullanılır.
/// API'dan veri çekip [ListingDetailScreen]'e yönlendirir.
class _SellerTrustRow extends StatelessWidget {
  final Map<String, dynamic> user;
  const _SellerTrustRow({required this.user});

  @override
  Widget build(BuildContext context) {
    final l     = AppLocalizations.of(context)!;
    final trust = user['trust_score'] as int?;
    final rank  = user['influence_rank'] as int?;
    if (trust == null && rank == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        children: [
          if (trust != null)
            _TrustChip(
              icon: FontAwesomeIcons.shieldHalved,
              value: '$trust / 100',
              hint: l.trustScoreHint,
              title: l.trustScoreLabel,
              color: trust >= 70
                  ? const Color(0xFF10B981)
                  : trust >= 35
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF9CA3AF),
            ),
          if (rank != null)
            _TrustChip(
              icon: FontAwesomeIcons.rankingStar,
              value: '#$rank',
              hint: l.influenceRankHint,
              title: l.influenceRankLabel,
              color: const Color(0xFF8B5CF6),
            ),
        ],
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String title;
  final String hint;
  final Color color;
  const _TrustChip({
    required this.icon,
    required this.value,
    required this.title,
    required this.hint,
    required this.color,
  });

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(hint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(value, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: () => _showInfo(context),
            child: Icon(Icons.help_outline, size: 11, color: color.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

class ListingDeepLinkLoader extends StatefulWidget {
  final int listingId;
  const ListingDeepLinkLoader({super.key, required this.listingId});

  @override
  State<ListingDeepLinkLoader> createState() => _ListingDeepLinkLoaderState();
}

class _ListingDeepLinkLoaderState extends State<ListingDeepLinkLoader> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await StorageService.getToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/${widget.listingId}'),
        headers: headers,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final listing = jsonDecode(resp.body) as Map<String, dynamic>;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: listing)),
        );
      } else {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ── Yardımcı widget ───────────────────────────────────────────────────────────

class _BoostRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _BoostRow({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFF97316)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor)),
        ],
      ),
    );

  }
}

class _MassNotificationDialog extends StatefulWidget {
  final int maxAudience;
  final int creditsLeft;
  final int perBlastCap;
  final int tuciBalance;

  const _MassNotificationDialog({
    required this.maxAudience,
    required this.creditsLeft,
    required this.perBlastCap,
    required this.tuciBalance,
  });

  @override
  State<_MassNotificationDialog> createState() => _MassNotificationDialogState();
}

class _MassNotificationDialogState extends State<_MassNotificationDialog> {
  bool _useCustomCount = false;
  late TextEditingController _countCtrl;

  @override
  void initState() {
    super.initState();
    final defaultCount = widget.maxAudience < widget.perBlastCap ? widget.maxAudience : widget.perBlastCap;
    _countCtrl = TextEditingController(text: defaultCount.toString());
    _countCtrl.addListener(_onCountChanged);
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    super.dispose();
  }

  void _onCountChanged() {
    final parsed = int.tryParse(_countCtrl.text);
    if (parsed != null) {
      final maxAllowed = widget.maxAudience < widget.perBlastCap
          ? widget.maxAudience
          : widget.perBlastCap;
      final clamped = parsed.clamp(1, maxAllowed);
      if (clamped != parsed) {
        final s = clamped.toString();
        _countCtrl.value = TextEditingValue(
          text: s,
          selection: TextSelection.collapsed(offset: s.length),
        );
        return;
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    int requestedCount = int.tryParse(_countCtrl.text) ?? 0;
    if (!_useCustomCount) {
      requestedCount = widget.maxAudience < widget.perBlastCap ? widget.maxAudience : widget.perBlastCap;
    }
    if (requestedCount > widget.maxAudience) requestedCount = widget.maxAudience;

    final actualCount = requestedCount;
    final freeUsed = widget.creditsLeft < actualCount ? widget.creditsLeft : actualCount;
    final paidCount = actualCount - freeUsed;
    final tuciCost = paidCount * 10;
    final bool hasEnoughBalance = widget.tuciBalance >= tuciCost;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(AppLocalizations.of(context)!.massAudienceNotification, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.listingBlastDialogBody(widget.maxAudience),
            style: const TextStyle(color: Color(0xFF94A3B8), height: 1.5),
          ),
          const SizedBox(height: 16),
          // Checkbox for custom count
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _useCustomCount,
                  activeColor: const Color(0xFF14B8A6),
                  side: const BorderSide(color: Color(0xFF64748B)),
                  onChanged: (val) {
                    setState(() => _useCustomCount = val ?? false);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(AppLocalizations.of(context)!.audienceSendToX, style: const TextStyle(color: Color(0xFFCBD5E1)))),
            ],
          ),
          if (_useCustomCount)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0, left: 32.0),
              child: TextField(
                controller: _countCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.audiencePersonCountHint,
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Calculation Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x3314B8A6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x5514B8A6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppLocalizations.of(context)!.audienceNotificationWillGoTo, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    Text('$actualCount Kişi', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppLocalizations.of(context)!.audienceMonthlyFreeRights, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    Text('-$freeUsed Kişi', style: const TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Divider(color: Color(0x5514B8A6)),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppLocalizations.of(context)!.audienceTotalCost, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('$tuciCost TUCi', style: TextStyle(color: hasEnoughBalance ? const Color(0xFF2DD4BF) : const Color(0xFFEF4444), fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          if (!hasEnoughBalance)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(AppLocalizations.of(context)!.audienceInsufficientTuci, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(AppLocalizations.of(context)!.btnCancel, style: const TextStyle(color: Color(0xFF64748B))),
        ),
        FilledButton(
          onPressed: hasEnoughBalance && actualCount > 0
              ? () => Navigator.pop(context, {'count': actualCount, 'cost': tuciCost})
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF14B8A6),
            disabledBackgroundColor: const Color(0x6614B8A6),
          ),
          child: Text(AppLocalizations.of(context)!.btnSend, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
