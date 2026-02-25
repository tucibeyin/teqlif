import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/favorites_provider.dart';

final myAdsProvider = FutureProvider<List<AdModel>>((ref) async {
  ref.watch(authProvider); // React to auth state changes (login/logout)
  final res = await ApiClient().get(Endpoints.ads, params: {'mine': 'true'});
  final list = res.data as List<dynamic>;
  return list.map((e) => AdModel.fromJson(e as Map<String, dynamic>)).toList();
});

final myBidsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(authProvider); // React to auth state changes
  final res = await ApiClient().get(Endpoints.bids);
  final list = res.data as List<dynamic>;
  return list.cast<Map<String, dynamic>>();
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _tabIndex = 0; // 0 for My Ads, 1 for Favorites

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final myAdsAsync = ref.watch(myAdsProvider);
    final favsAsync = ref.watch(favoritesProvider);
    final myBidsAsync = ref.watch(myBidsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panelim'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myAdsProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // User greeting
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF00B4CC),
                      child: Text(
                        (user?.name ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Merhaba, ${user?.name ?? ''}!',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(user?.email ?? '',
                            style: const TextStyle(
                                color: Color(0xFF9AAAB8), fontSize: 13)),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => context.push('/profile/edit'),
                          child: const Text('Profilimi Düzenle',
                              style: TextStyle(
                                  color: Color(0xFF00B4CC),
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w500)),
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Stats row
            myAdsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (ads) {
                final active = ads.where((a) => !a.isExpired).length;
                final expired = ads.where((a) => a.isExpired).length;
                return Row(
                  children: [
                    _StatCard(label: 'Aktif İlan', value: '$active'),
                    const SizedBox(width: 12),
                    _StatCard(label: 'Süresi Dolan', value: '$expired'),
                    const SizedBox(width: 12),
                    _StatCard(label: 'Toplam', value: '${ads.length}'),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            // Header Tabs
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('İlanlarım')),
                  ButtonSegment(value: 1, label: Text('Favorilerim')),
                  ButtonSegment(value: 2, label: Text('Tekliflerim')),
                ],
                selected: {_tabIndex},
                onSelectionChanged: (set) =>
                    setState(() => _tabIndex = set.first),
              ),
            ),
            const SizedBox(height: 16),
            if (_tabIndex == 0)
              myAdsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Hata: $e'),
                data: (ads) => ads.isEmpty
                    ? const Center(
                        child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('Henüz ilan yok.')))
                    : Column(
                        children: ads.map((ad) => _MyAdTile(ad: ad)).toList(),
                      ),
              )
            else if (_tabIndex == 1)
              favsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Hata: $e'),
                data: (ads) => ads.isEmpty
                    ? const Center(
                        child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('Henüz favoriniz yok.')))
                    : Column(
                        children: ads
                            .map((ad) => _MyAdTile(ad: ad, isFavorite: true))
                            .toList(),
                      ),
              )
            else
              myBidsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Hata: $e'),
                data: (bids) => bids.isEmpty
                    ? const Center(
                        child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('Henüz teklifiniz yok.')))
                    : Column(
                        children: bids.map((bid) => _MyBidTile(bid: bid)).toList(),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: Color(0xFF00B4CC))),
              const SizedBox(height: 4),
              Text(label,
                  style:
                      const TextStyle(color: Color(0xFF9AAAB8), fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyAdTile extends ConsumerWidget {
  final AdModel ad;
  final bool isFavorite;
  const _MyAdTile({required this.ad, this.isFavorite = false});

  Future<void> _republish(BuildContext context, WidgetRef ref) async {
    try {
      await ApiClient().patch(Endpoints.republishAd(ad.id));
      ref.invalidate(myAdsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İlan yeniden yayınlandı! ✅')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
      }
    }
  }

  Future<void> _unfavorite(BuildContext context, WidgetRef ref) async {
    try {
      await ApiClient().delete(Endpoints.favoriteById(ad.id));
      ref.invalidate(favoritesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Favorilerden çıkarıldı')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ad.images.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl(ad.images.first),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _fallbackIcon(ad.category?.icon),
                )
              : _fallbackIcon(ad.category?.icon),
        ),
        title: Text(ad.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          ad.isExpired ? 'Süresi Doldu' : 'Aktif',
          style: TextStyle(
            color: ad.isExpired ? Colors.red : Colors.green,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: isFavorite
            ? IconButton(
                icon: const Icon(Icons.favorite, color: Colors.red),
                onPressed: () => _unfavorite(context, ref),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('İlanı Sil'),
                          content: const Text('Bu ilanı kalıcı olarak silmek istediğinize emin misiniz?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('İptal')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Sil',
                                    style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        try {
                          await ApiClient().delete('/api/ads/${ad.id}');
                          ref.invalidate(myAdsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('İlan silindi.')));
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('İlan silinemedi.')));
                          }
                        }
                      }
                    },
                  ),
                  if (ad.isExpired)
                    TextButton(
                      onPressed: () => _republish(context, ref),
                      child: const Text('Yenile'),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => context.push('/edit-ad/${ad.id}'),
                    ),
                ],
              ),
        onTap: () => context.push('/ad/${ad.id}'),
      ),
    );
  }

  Widget _fallbackIcon(String? iconString) {
    return Container(
      width: 56,
      height: 56,
      color: const Color(0xFFF4F7FA),
      alignment: Alignment.center,
      child: Text(
        iconString ?? '📦',
        style: const TextStyle(fontSize: 24),
      ),
    );
  }
}

class _MyBidTile extends StatelessWidget {
  final Map<String, dynamic> bid;
  const _MyBidTile({required this.bid});

  @override
  Widget build(BuildContext context) {
    final adMap = bid['ad'] as Map<String, dynamic>? ?? {};
    final title = adMap['title'] as String? ?? 'Bilinmiyor';
    final images = adMap['images'] as List<dynamic>? ?? [];
    final category = adMap['category'] as Map<String, dynamic>? ?? {};
    final iconString = category['icon'] as String? ?? '📦';
    final adId = bid['adId'] as String?;
    final amount = double.tryParse(bid['amount'].toString()) ?? 0.0;
    final createdAtStr = bid['createdAt'] as String?;
    final timeStr = createdAtStr != null
        ? timeago.format(DateTime.parse(createdAtStr), locale: 'tr')
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: images.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl(images.first.toString()),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _fallbackBidIcon(iconString),
                )
              : _fallbackBidIcon(iconString),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(timeStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              'Teklifim: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0).format(amount)}',
              style: const TextStyle(
                  color: Color(0xFF00B4CC), fontWeight: FontWeight.bold),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          if (adId != null) {
            context.push('/ad/$adId');
          }
        },
      ),
    );
  }

  Widget _fallbackBidIcon(String iconString) {
    return Container(
      width: 56,
      height: 56,
      color: const Color(0xFFF4F7FA),
      alignment: Alignment.center,
      child: Text(iconString, style: const TextStyle(fontSize: 24)),
    );
  }
}
