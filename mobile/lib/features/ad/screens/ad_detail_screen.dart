import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../../../core/providers/auth_provider.dart';

final adDetailProvider = FutureProvider.family<AdModel, String>((ref, id) async {
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
    final amount = double.tryParse(_bidCtrl.text.replaceAll(',', '.'));
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatPrice(double p) =>
      '₺${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context) {
    final adAsync = ref.watch(adDetailProvider(widget.adId));
    final currentUser = ref.watch(authProvider).user;

    return Scaffold(
      body: adAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
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
                flexibleSpace: FlexibleSpaceBar(
                  background: ad.images.isNotEmpty
                      ? PageView.builder(
                          itemCount: ad.images.length,
                          onPageChanged: (i) =>
                              setState(() => _currentImage = i),
                          itemBuilder: (_, i) => CachedNetworkImage(
                            imageUrl: ad.images[i],
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
                            _Chip(
                                '${ad.category!.icon} ${ad.category!.name}',
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
                                const Text('Açılış Fiyatı',
                                    style: TextStyle(
                                        color: Color(0xFF9AAAB8), fontSize: 12)),
                                Text(
                                  ad.startingBid == null
                                      ? '🔥 Serbest Teklif'
                                      : _formatPrice(ad.startingBid!),
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
                                        color: Color(0xFF9AAAB8), fontSize: 12)),
                                Text(
                                  _formatPrice(ad.price),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      decoration: TextDecoration.lineThrough,
                                      color: Color(0xFF4A5568)),
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
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
                      // Bid section
                      if (!isOwner && !ad.isExpired) ...[
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
                          // Authenticated: show bid form
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _bidCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    hintText: 'Teklif miktarı (₺)',
                                    prefixIcon: Icon(Icons.gavel),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 52,
                                child: ElevatedButton(
                                  onPressed:
                                      _bidLoading ? null : () => _placeBid(ad),
                                  child: _bidLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : const Text('Ver'),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 24),
                      ],
                      // Bid history
                      if (ad.bids.isNotEmpty) ...[
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
          style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _BidTile extends StatelessWidget {
  final BidModel bid;
  final bool isTop;
  final bool isOwner;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const _BidTile({
    required this.bid,
    required this.isTop,
    required this.isOwner,
    required this.onAccept,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final accepted = bid.status == 'ACCEPTED';
    final rejected = bid.status == 'REJECTED';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (isTop) const Text('🏆 ', style: TextStyle(fontSize: 16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bid.user?.name ?? 'Anonim',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '₺${bid.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Color(0xFF00B4CC),
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                ],
              ),
            ),
            if (accepted)
              const _StatusBadge('Kabul Edildi', Colors.green)
            else if (rejected)
              const _StatusBadge('Reddedildi', Colors.red)
            else if (isOwner)
              TextButton(
                onPressed: onAccept,
                child: const Text('Kabul Et'),
              ),
            if (isOwner && accepted)
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('İptal'),
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
