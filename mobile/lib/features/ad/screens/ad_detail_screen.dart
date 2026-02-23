import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/favorites_provider.dart';
import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';

final adDetailProvider =
    FutureProvider.family<AdModel, String>((ref, id) async {
  final res = await ApiClient().get(Endpoints.adById(id));
  return AdModel.fromJson(res.data as Map<String, dynamic>);
});

class AdDetailScreen extends ConsumerStatefulWidget {
  final String adId;
  const AdDetailScreen({super.key, required this.adId});

  @override
  ConsumerState<AdDetailScreen> createState() => _AdDetailScreenState();
}

class _AdDetailScreenState extends ConsumerState<AdDetailScreen> {
  final _bidCtrl = TextEditingController();
  int _currentImage = 0;
  bool _bidLoading = false;

  @override
  void dispose() {
    _bidCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeBid(AdModel ad) async {
    final rawText = _bidCtrl.text.replaceAll('₺', '').replaceAll(' ', '').replaceAll('.', '');
    final amount = double.tryParse(rawText);
    if (amount == null) {
      _snack('Geçerli bir teklif miktarı girin.');
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
      _snack('Teklifiniz verildi! 🎉');
    } catch (e) {
      _snack('Teklif verilemedi.');
    } finally {
      setState(() => _bidLoading = false);
    }
  }

  Future<void> _acceptBid(String bidId) async {
    try {
      await ApiClient().patch(Endpoints.acceptBid(bidId));
      ref.invalidate(adDetailProvider(widget.adId));
      _snack('Teklif kabul edildi. ✅');
    } catch (_) {
      _snack('İşlem başarısız.');
    }
  }

  Future<void> _cancelBid(String bidId) async {
    try {
      await ApiClient().patch(Endpoints.cancelBid(bidId));
      ref.invalidate(adDetailProvider(widget.adId));
      _snack('Teklif iptali başarılı.');
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
                          itemBuilder: (_, i) => CachedNetworkImage(
                            imageUrl: imageUrl(ad.images[i]),
                            fit: BoxFit.cover,
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
                  if (isOwner)
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
                      // Badge row
                      Row(
                        children: [
                          if (ad.category != null)
                            _Chip('${ad.category!.icon} ${ad.category!.name}',
                                color: const Color(0xFFE6F9FC),
                                textColor: const Color(0xFF008FA3)),
                          const SizedBox(width: 8),
                          if (ad.isExpired)
                            _Chip('Süresi Doldu',
                                color: const Color(0xFFFEF2F2),
                                textColor: const Color(0xFFEF4444)),
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
                                            ? '🔥 Serbest Teklif'
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
                                  const Text('Pey Aralığı',
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
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Bid or Buy section
                      if (!isOwner && !ad.isExpired) ...[
                        if (ad.isFixedPrice) ...[
                          const Text('Satın Al',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 8),
                          if (currentUser == null)
                            // Guest: show login prompt
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
                                  context.push('/messages/chat/${ad.userId}');
                                },
                                icon: const Icon(Icons.message_outlined),
                                label: const Text('Satıcıya Mesaj Gönder'),
                              ),
                            ),
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
                                          context.push(
                                              '/messages/chat/${ad.userId}?initialMessage=$initialMsg');
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
                          const Text('Teklif Ver',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 8),
                          if (currentUser == null)
                            // Guest: show login prompt
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
                                        'Teklif vermek için giriş yapmanız gerekiyor.',
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
                            (() {
                              final double currentHighest = ad.bids.isNotEmpty
                                  ? ad.bids.first.amount
                                  : (ad.startingBid ?? 0.0);
                              final double minRequiredBid = ad.bids.isNotEmpty
                                  ? (currentHighest + ad.minBidStep)
                                  : (ad.startingBid ?? 1.0);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _bidCtrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          inputFormatters: [
                                            CurrencyTextInputFormatter.currency(
                                              locale: 'tr_TR',
                                              symbol: '₺ ',
                                              decimalDigits: 0,
                                            )
                                          ],
                                          decoration: InputDecoration(
                                            hintText: 'Teklif miktarı (₺)',
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
                          const SizedBox(height: 24),
                        ],
                      ],
                      // Bid history
                      if (!ad.isFixedPrice && ad.bids.isNotEmpty) ...[
                        Text('Teklif Geçmişi (${ad.bids.length})',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 8),
                        ...ad.bids.asMap().entries.map(
                          (entry) {
                            final i = entry.key;
                            final bid = entry.value;
                            return _BidTile(
                              bid: bid,
                              isTop: i == 0,
                              isOwner: isOwner,
                              onAccept: () => _acceptBid(bid.id),
                              onCancel: () => _cancelBid(bid.id),
                              onMessage: () => _messageBidder(bid.user!.id),
                            );
                          },
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
  final VoidCallback onAccept;
  final VoidCallback onCancel;
  final VoidCallback onMessage;

  const _BidTile({
    required this.bid,
    required this.isTop,
    required this.isOwner,
    required this.onAccept,
    required this.onCancel,
    required this.onMessage,
  });

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
                    Text(bid.user?.name ?? 'Anonim',
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
              '₺${bid.amount.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Color(0xFF00B4CC),
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
            if (isOwner) ...[
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
                  if (accepted)
                    _ActionIconButton(
                      icon: Icons.cancel_outlined,
                      label: 'İptal Et',
                      color: Colors.red,
                      onPressed: onCancel,
                    ),
                  if (bid.status == 'PENDING' || accepted)
                    const SizedBox(width: 8),
                  _ActionIconButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Mesaj',
                    color: const Color(0xFF00B4CC),
                    onPressed: onMessage,
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
