import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/ad.dart';
import '../../core/providers/auth_provider.dart';

final myAdsProvider = FutureProvider<List<AdModel>>((ref) async {
  final res = await ApiClient().get(Endpoints.ads, params: {'mine': 'true'});
  final list = res.data as List<dynamic>;
  return list.map((e) => AdModel.fromJson(e as Map<String, dynamic>)).toList();
});

final myBidsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient().get(Endpoints.bids);
  final list = res.data as List<dynamic>;
  return list.cast<Map<String, dynamic>>();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final myAdsAsync = ref.watch(myAdsProvider);

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
            // My Ads header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('İlanlarım',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                TextButton.icon(
                  onPressed: () => context.push('/post-ad'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Yeni İlan'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            myAdsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Hata: $e'),
              data: (ads) => ads.isEmpty
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Henüz ilan yok.')))
                  : Column(
                      children: ads.map((ad) => _MyAdTile(ad: ad)).toList(),
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
                  style: const TextStyle(
                      color: Color(0xFF9AAAB8), fontSize: 12),
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
  const _MyAdTile({required this.ad});

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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İşlem başarısız.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        trailing: ad.isExpired
            ? TextButton(
                onPressed: () => _republish(context, ref),
                child: const Text('Yenile'),
              )
            : IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/edit-ad/${ad.id}'),
              ),
        onTap: () => context.push('/ad/${ad.id}'),
      ),
    );
  }
}
