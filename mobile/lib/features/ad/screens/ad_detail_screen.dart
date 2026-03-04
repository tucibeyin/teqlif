import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/favorites_provider.dart';
import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'fullscreen_image_viewer.dart';
import 'live_arena_host.dart';
import 'live_arena_viewer.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../../core/constants/categories.dart';

import '../providers/ad_detail_provider.dart';
import '../../../core/providers/live_room_provider.dart';

class AdDetailScreen extends ConsumerStatefulWidget {
  final String adId;
  const AdDetailScreen({super.key, required this.adId});

  @override
  ConsumerState<AdDetailScreen> createState() => _AdDetailScreenState();
}

class _AdDetailScreenState extends ConsumerState<AdDetailScreen> {
  final _bidCtrl = TextEditingController();
  final _bidFormatter = CurrencyTextInputFormatter.currency(
    locale: 'tr_TR',
    symbol: '',
    decimalDigits: 0,
  );
  int _currentImage = 0;
  bool _bidLoading = false;

  @override
  void dispose() {
    _bidCtrl.dispose();
    final notifier = ref.read(liveRoomProvider(widget.adId).notifier);
    // Explicitly clean up any lingering connections when leaving ad detail
    notifier.disconnect();
    super.dispose();
  }

  Future<void> _placeBid(AdModel ad) async {
    final rawText = _bidCtrl.text
        .replaceAll('₺', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final amount = double.tryParse(rawText);
    if (amount == null) {
      _snack('Geçerli bir teqlif miktarı girin.');
      return;
    }
    setState(() => _bidLoading = true);
    try {
      await ApiClient().post(Endpoints.bids, data: {
        'adId': ad.id,
        'amount': amount,
      });
      _bidCtrl.clear();
      ref.invalidate(adDetailProvider(widget.adId));
      ref.invalidate(myBidsProvider);
      _snack('Teqlifiniz verildi! 🎉');
    } catch (e) {
      _snack('Teqlif verilemedi.');
    } finally {
      setState(() => _bidLoading = false);
    }
  }

  Future<void> _inviteToStage(String targetUserId) async {
    try {
      final response = await ApiClient().post('/api/livekit/signal', data: {
        'adId': widget.adId,
        'targetUserId': targetUserId,
        'signal': 'INVITE_TO_STAGE',
      });
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullanıcı sahneye davet edildi!')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Davet gönderilemedi!')));
    }
  }

  Future<void> _startLiveStream(AdModel ad) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Canlı Yayını Başlat'),
        content: const Text(
            'Canlı yayını başlatmak istediğinize emin misiniz? İzleyiciler arenaya katılmaya başlayacak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Başlat'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Check Permissions Before Joining
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (cameraStatus != PermissionStatus.granted || micStatus != PermissionStatus.granted) {
      if (!mounted) return;
      _snack('Kamera ve Mikrofon izni olmadan canlı yayın başlatılamaz!');
      return;
    }

    try {
      final liveKitRoomId = ad.id;
      final response = await ApiClient().post('/api/ads/${ad.id}/live', data: {
        'isLive': true,
        'liveKitRoomId': liveKitRoomId,
      });

      if (response.statusCode == 200) {
        if (!mounted) return;
        _snack('Canlı yayın başladı! Arena yükleniyor...');
        ref.invalidate(adDetailProvider(widget.adId));
        // Direct navigation after success
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => LiveArenaHost(ad: ad)));
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Canlı yayın başlatılamadı.');
    }
  }

  Future<void> _acceptBid(String bidId) async {
    try {
      await ApiClient().patch(Endpoints.acceptBid(bidId));
      ref.invalidate(adDetailProvider(widget.adId));
      _snack('Teqlif kabul edildi. ✅');
    } catch (_) {
      _snack('İşlem başarısız.');
    }
  }

  Future<void> _cancelBid(String bidId) async {
    try {
      await ApiClient().patch(Endpoints.cancelBid(bidId));
      ref.invalidate(adDetailProvider(widget.adId));
      _snack('Teqlif iptali başarılı.');
    } catch (_) {
      _snack('İşlem başarısız.');
    }
  }

  Future<void> _finalizeSale(String bidId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Satışı Tamamla'),
        content: const Text(
            'Dikkat! Satışın gerçekleştiğini onaylıyorsunuz. Bu işlemden sonra ilan PASİF (Satıldı) durumuna düşecektir. Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Evet, Satış Yapıldı',
                  style: TextStyle(color: Colors.green))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient().post(Endpoints.finalizeBid(bidId));
      ref.invalidate(adDetailProvider(widget.adId));
      _snack('Satış başarıyla tamamlandı! ✅');
    } catch (_) {
      _snack('İşlem başarısız.');
    }
  }

  Future<void> _messageBidder(String bidderId) async {
    try {
      final res = await ApiClient().post(Endpoints.conversations, data: {
        'userId': bidderId,
        'adId': widget.adId,
      });
      final conversationId = res.data['id'];
      if (mounted) {
        context.push('/messages/$conversationId');
      }
    } catch (e) {
      _snack('Sohbet başlatılamadı.');
    }
  }

  Future<void> _contactSeller(String sellerId, String? initialMessage) async {
    try {
      final res = await ApiClient().post(Endpoints.conversations, data: {
        'userId': sellerId,
        'adId': widget.adId,
      });
      final conversationId = res.data['id'];

      if (initialMessage != null) {
        try {
          await ApiClient().post(Endpoints.messages, data: {
            'conversationId': conversationId,
            'content': initialMessage,
            'recipientId': sellerId,
          });
        } catch (_) {}
      }

      if (mounted) {
        context.push('/messages/$conversationId');
      }
    } catch (e) {
      _snack('Sohbet başlatılamadı.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatPrice(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context) {
    final adAsync = ref.watch(adDetailProvider(widget.adId));
    final currentUser = ref.watch(authProvider).user;
    final favsAsync = ref.watch(favoritesProvider);

    return Scaffold(
      body: adAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: Center(child: Text('Hata: $e')),
        ),
        data: (ad) {
          final isOwner = currentUser?.id == ad.userId;

          // Note: Automatic navigation removed to prevent "Arena Trap"
          // We will show a banner or button instead.

          final roomState = ref.watch(liveRoomProvider(widget.adId));
          final now = DateTime.now().add(roomState.serverTimeOffset);
          final isAuctionActive = ad.isAuction == true &&
              ad.auctionStartTime != null &&
              ad.auctionStartTime!.isBefore(now);

          return CustomScrollView(
            slivers: [
              // Image header
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
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
                flexibleSpace: FlexibleSpaceBar(
                  background: ad.images.isNotEmpty
                      ? PageView.builder(
                          itemCount: ad.images.length,
                          onPageChanged: (i) =>
                              setState(() => _currentImage = i),
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FullScreenImageViewer(
                                    images: ad.images,
                                    initialIndex: i,
                                  ),
                                ),
                              );
                            },
                            child: Hero(
                              tag: ad.images[i],
                              child: Container(
                                color: const Color(0xFFF4F7FA),
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl(ad.images[i]),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        )
                      : ad.isLive
                          ? Container(
                              color: Colors.black87,
                              child: const Center(
                                child: Text('🔴 CANLI YAYIN',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 24)),
                              ),
                            )
                          : Container(
                              color: const Color(0xFFF4F7FA),
                              child: Center(
                                child: Text(ad.category?.icon ?? '📦',
                                    style: const TextStyle(fontSize: 64)),
                          ),
                        ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.black87),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.8),
                    ),
                    onPressed: () {
                      Share.share('Bana Teqlif ver! ${ad.title}\nhttps://teqlif.com/ad/${ad.id}');
                    },
                  ),
                  favsAsync.when(
                    data: (favs) {
                      final isFav = favs.any((f) => f.id == ad.id);
                      return IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.red : null,
                        ),
                        onPressed: () async {
                          if (currentUser == null) {
                            context.push('/login');
                            return;
                          }
                          try {
                            if (isFav) {
                              await ApiClient()
                                  .delete(Endpoints.favoriteById(ad.id));
                            } else {
                              await ApiClient().post(Endpoints.favorites,
                                  data: {'adId': ad.id});
                            }
                            ref.invalidate(favoritesProvider);
                          } catch (e) {
                            _snack('İşlem başarısız.');
                          }
                        },
                      );
                    },
                    loading: () => const SizedBox(),
                    error: (_, __) => const SizedBox(),
                  ),
                  if (isOwner && ad.status != 'SOLD')
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => context.push('/edit-ad/${ad.id}'),
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image indicator
                      if (ad.images.length > 1)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            ad.images.length,
                            (i) => Container(
                              margin: const EdgeInsets.only(right: 4),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _currentImage
                                    ? const Color(0xFF00B4CC)
                                    : const Color(0xFFE2EBF0),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      // Breadcrumb + expired chip
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Breadcrumb: Gayrimenkul › Konut › Satılık › Daire
                          if (ad.category != null)
                            (() {
                              final path = findPath(ad.category!.slug);
                              if (path != null && path.length > 1) {
                                return Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: path.asMap().entries.map((entry) {
                                    final i = entry.key;
                                    final node = entry.value;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (i > 0)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 2),
                                            child: Text('›',
                                                style: TextStyle(
                                                    color: Color(0xFF9AAAB8),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold)),
                                          ),
                                        _Chip(
                                          node.icon.isNotEmpty
                                              ? '${node.icon} ${node.name}'
                                              : node.name,
                                          color: const Color(0xFFE6F9FC),
                                          textColor: const Color(0xFF008FA3),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                );
                              }
                              return _Chip(
                                '${ad.category!.icon} ${ad.category!.name}',
                                color: const Color(0xFFE6F9FC),
                                textColor: const Color(0xFF008FA3),
                              );
                            })(),
                          if (ad.isExpired) ...[
                            const SizedBox(height: 4),
                            _Chip('Süresi Doldu',
                                color: const Color(0xFFFEF2F2),
                                textColor: const Color(0xFFEF4444)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(ad.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 20)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 16, color: Color(0xFF9AAAB8)),
                          const SizedBox(width: 4),
                          Text(
                            '${ad.province?.name ?? ''}, ${ad.district?.name ?? ''}',
                            style: const TextStyle(
                                color: Color(0xFF9AAAB8), fontSize: 13),
                          ),
                          const Spacer(),
                          const Icon(Icons.visibility_outlined,
                              size: 16, color: Color(0xFF9AAAB8)),
                          const SizedBox(width: 4),
                          Text('${ad.views} görüntülenme',
                              style: const TextStyle(
                                  color: Color(0xFF9AAAB8), fontSize: 13)),
                        ],
                      ),
                      if (ad.expiresAt != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 16, color: Color(0xFF00B4CC)),
                            const SizedBox(width: 4),
                            Text(
                                'Bitiş: ${DateFormat('d MMMM yyyy HH:mm', 'tr_TR').format(ad.expiresAt!)}',
                                style: const TextStyle(
                                    color: Color(0xFF00B4CC),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Price section
                      if (ad.isFixedPrice)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F9FC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    const Color(0xFF00B4CC).withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Sabit Fiyatlı Ürün',
                                      style: TextStyle(
                                          color: Color(0xFF00B4CC),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatPrice(ad.price),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 24,
                                        color: Color(0xFF2D3748)),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: ad.status == 'ACTIVE'
                                      ? const Color(0xFF00B4CC).withOpacity(0.1)
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  ad.status == 'ACTIVE'
                                      ? 'Yayında'
                                      : (ad.status == 'SOLD'
                                          ? 'Satıldı'
                                          : 'Süresi Doldu'),
                                  style: TextStyle(
                                    color: ad.status == 'ACTIVE'
                                        ? const Color(0xFF00B4CC)
                                        : Colors.grey.shade600,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F9FC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      ad.bids.isNotEmpty
                                          ? 'Güncel Fiyat'
                                          : 'Açılış Fiyatı',
                                      style: const TextStyle(
                                          color: Color(0xFF9AAAB8),
                                          fontSize: 12)),
                                  Text(
                                    ad.bids.isNotEmpty
                                        ? _formatPrice(ad.bids.first.amount)
                                        : (ad.startingBid == null
                                            ? '🔥 Serbest Teqlif'
                                            : _formatPrice(ad.startingBid!)),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 22,
                                        color: Color(0xFF00B4CC)),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Piyasa Değeri',
                                      style: TextStyle(
                                          color: Color(0xFF9AAAB8),
                                          fontSize: 12)),
                                  Text(
                                    _formatPrice(ad.price),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        decoration: TextDecoration.lineThrough,
                                        color: Color(0xFF4A5568)),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('teqlif Aralığı',
                                      style: TextStyle(
                                          color: Color(0xFF9AAAB8),
                                          fontSize: 12)),
                                  Text(
                                    '+${_formatPrice(ad.minBidStep)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: Color(0xFF00B4CC)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Description
                      const Text('Açıklama',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(ad.description,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                              height: 1.6)),
                      const SizedBox(height: 24),
                      // Seller info
                      const Text('Satıcı',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF00B4CC),
                            child: Text(
                              (ad.user?.name ?? 'U')[0].toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(ad.user?.name ?? 'Satıcı'),
                          subtitle: ad.user?.phone != null
                              ? Text(ad.user!.phone!)
                              : null,
                          trailing: ad.user?.phone != null && !isOwner
                              ? IconButton(
                                  icon: const Icon(Icons.phone,
                                      color: Color(0xFF00B4CC)),
                                  onPressed: () async {
                                    final uri =
                                        Uri.parse('tel:${ad.user!.phone}');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    } else {
                                      _snack('Arama başlatılamadı.');
                                    }
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!isOwner && !ad.isExpired) ...[
                        if (currentUser == null)
                          GestureDetector(
                            onTap: () => context.push('/login'),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6F9FC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFF00B4CC)
                                        .withOpacity(0.4)),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.lock_outline,
                                      color: Color(0xFF00B4CC)),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Satıcı ile iletişime geçmek için giriş yapmanız gerekiyor.',
                                      style: TextStyle(
                                          color: Color(0xFF008FA3),
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios,
                                      size: 14, color: Color(0xFF00B4CC)),
                                ],
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final initialMsg = ad.isFixedPrice
                                    ? 'Merhaba, "${ad.title}" (İlan No: ${ad.id}) ilanınızı ${_formatPrice(ad.price)} fiyatından satın almak istiyorum.'
                                    : '"${ad.title}" (İlan No: ${ad.id}) ilanı hakkında bilgi almak istiyorum.';
                                _contactSeller(ad.userId, initialMsg);
                              },
                              icon: const Icon(Icons.message_outlined),
                              label: const Text('Satıcıya Mesaj Gönder'),
                            ),
                          ),
                      ],
                      const SizedBox(height: 24),
                      // Bid or Buy section
                      if (!isOwner && !ad.isExpired && ad.status == 'ACTIVE') ...[
                        if (ad.isFixedPrice) ...[
                          const SizedBox(height: 24),
                        ] else ...[
                          if (ad.buyItNowPrice != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFF22C55E)
                                        .withOpacity(0.4)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Hemen Al Fiyatı',
                                          style: TextStyle(
                                              color: Color(0xFF166534),
                                              fontWeight: FontWeight.w600)),
                                      Text(_formatPrice(ad.buyItNowPrice!),
                                          style: const TextStyle(
                                              color: Color(0xFF166534),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (currentUser == null)
                                    GestureDetector(
                                      onTap: () => context.push('/login'),
                                      child: const Text(
                                        'Satın almak için giriş yapın.',
                                        style: TextStyle(
                                            color: Color(0xFF166534),
                                            fontWeight: FontWeight.w500),
                                      ),
                                    )
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF22C55E),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () {
                                          final initialMsg =
                                              'Merhaba, "${ad.title}" (İlan No: ${ad.id}) ilanınızı Hemen Al fiyatı olan ${_formatPrice(ad.buyItNowPrice!)} üzerinden satın almak istiyorum.';
                                          _contactSeller(ad.userId, initialMsg);
                                        },
                                        icon: const Icon(Icons.flash_on),
                                        label: const Text('Hemen Satın Al'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          _buildBidInputSection(context, ad,
                              isOwner: isOwner, adStatus: ad.status, isFrozen: roomState.isFrozen),
                          const SizedBox(height: 24),
                        ],
                      ],

                      if (ad.isLive == true && ad.status == 'ACTIVE') ...[
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              elevation: 4,
                            ),
                            onPressed: () {
                              if (isOwner) {
                                if (mounted) {
                                  Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute(
                                      builder: (_) => LiveArenaHost(ad: ad),
                                    ),
                                  );
                                }
                              } else {
                                if (mounted) {
                                  Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute(
                                      builder: (_) => LiveArenaViewer(ad: ad),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.sensors),
                            label: const Text('🔴 Canlı Yayına Katıl',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      if (isOwner && ad.status == 'ACTIVE' && ad.isLive != true) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              elevation: 4,
                            ),
                            onPressed: () => _startLiveStream(ad),
                            icon: const Icon(Icons.videocam),
                            label: const Text('🔴 Canlı Yayını Başlat',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Bid history
                      if (!ad.isFixedPrice && ad.bids.isNotEmpty) ...[
                        Text('Teqlif Geçmişi (${ad.bids.length})',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 500),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2EBF0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: ad.bids.length,
                              itemBuilder: (context, i) {
                                final bid = ad.bids[i];
                                return _BidTile(
                                  bid: bid,
                                  isTop: i == 0,
                                  isOwner: isOwner,
                                  adStatus: ad.status,
                                  onAccept: () => _acceptBid(bid.id),
                                  onCancel: () => _cancelBid(bid.id),
                                  onFinalize: () => _finalizeSale(bid.id),
                                  onInviteToStage: () => _inviteToStage(bid.user!.id),
                                  onMessage: () => _messageBidder(bid.user!.id),
                                  formatPrice: _formatPrice,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBidInputSection(BuildContext context, AdModel ad,
      {required bool isOwner, required String adStatus, bool isFrozen = false}) {
    if (isOwner || adStatus != 'ACTIVE') {
      return const SizedBox.shrink();
    }

    if (isFrozen) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ]),
        child: const Center(
          child: Text(
            'Yayıncı bağlantısı bekleniyor...',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    final currentUser = ref.watch(authProvider).user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Teqlif Ver',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        if (currentUser != null)
          (() {
            final double currentHighest = ad.bids.isNotEmpty
                ? ad.bids.first.amount
                : 0.0;
            final double minRequiredBid = ad.bids.isNotEmpty
                ? (currentHighest + ad.minBidStep)
                : (ad.startingBid != null && ad.startingBid! > 0
                    ? ad.startingBid!
                    : ad.minBidStep.toDouble());

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bidCtrl,
                        keyboardType: const TextInputType
                            .numberWithOptions(decimal: true),
                        inputFormatters: [_bidFormatter],
                        decoration: InputDecoration(
                          hintText: 'Teqlif miktarı (₺)',
                          prefixIcon: const Icon(Icons.gavel),
                          helperText:
                              'En az ${_formatPrice(minRequiredBid)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _bidLoading
                              ? null
                              : () => _placeBid(ad),
                          child: _bidLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2))
                              : const Text('Ver'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          })(),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  const _Chip(this.label, {required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(100)),
      child: Text(label,
          style: TextStyle(
              color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _BidTile extends StatelessWidget {
  final BidModel bid;
  final bool isTop;
  final bool isOwner;
  final String adStatus;
  final VoidCallback onAccept;
  final VoidCallback onCancel;
  final VoidCallback onFinalize;
  final VoidCallback onMessage;
  final VoidCallback onInviteToStage;
  final String Function(double) formatPrice; // Added dependency for correct price formatting

  const _BidTile({
    required this.bid,
    required this.isTop,
    required this.isOwner,
    required this.adStatus,
    required this.onAccept,
    required this.onCancel,
    required this.onMessage,
    required this.onFinalize,
    required this.onInviteToStage,
    required this.formatPrice,
  });

  String _formatNameInitials(String? name) {
    if (name == null || name.isEmpty) return 'A.';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return '${parts[0][0].toUpperCase()}.';
    }
    return parts.map((p) => '${p[0].toUpperCase()}.').join('');
  }

  @override
  Widget build(BuildContext context) {
    final accepted = bid.status == 'ACCEPTED';
    final rejected = bid.status == 'REJECTED';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (isTop)
                      const Text('🏆 ', style: TextStyle(fontSize: 16)),
                    Text(_formatNameInitials(bid.user?.name),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                if (accepted)
                  const _StatusBadge('Kabul Edildi', Colors.green)
                else if (rejected)
                  const _StatusBadge('Reddedildi', Colors.red)
              ],
            ),
            const SizedBox(height: 4),
            Text(
              formatPrice(bid.amount),
              style: const TextStyle(
                  color: Color(0xFF00B4CC),
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
            if (bid.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  timeago.format(bid.createdAt!, locale: 'tr'),
                  style: const TextStyle(
                      color: Color(0xFF9AAAB8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
            if (isOwner && adStatus != 'SOLD') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (bid.status == 'PENDING') ...[
                    _ActionIconButton(
                      icon: Icons.check_circle_outline,
                      label: 'Kabul Et',
                      color: Colors.green,
                      onPressed: onAccept,
                    ),
                    const SizedBox(width: 8),
                    _ActionIconButton(
                      icon: Icons.cancel_outlined,
                      label: 'Reddet',
                      color: Colors.red,
                      onPressed: onCancel,
                    ),
                  ],
                  if (accepted) ...[
                    _ActionIconButton(
                      icon: Icons.check_circle,
                      label: 'SAT',
                      color: Colors.green,
                      onPressed: onFinalize,
                    ),
                    const SizedBox(width: 8),
                    _ActionIconButton(
                      icon: Icons.cancel_outlined,
                      label: 'İptal Et',
                      color: Colors.red,
                      onPressed: onCancel,
                    ),
                    if (bid.user?.phone != null) ...[
                      const SizedBox(width: 8),
                      _ActionIconButton(
                        icon: Icons.phone_outlined,
                        label: 'Ara',
                        color: Colors.blueGrey,
                        onPressed: () async {
                          final url = Uri.parse('tel:${bid.user!.phone}');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                      ),
                    ],
                  ],
                  if (bid.status == 'PENDING' || accepted)
                    const SizedBox(width: 8),
                  _ActionIconButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Mesaj',
                    color: const Color(0xFF00B4CC),
                    onPressed: onMessage,
                  ),
                  const SizedBox(width: 8),
                  _ActionIconButton(
                    icon: Icons.video_call,
                    label: 'Sahne',
                    color: Colors.deepPurple,
                    onPressed: onInviteToStage,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionIconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusBadge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}
