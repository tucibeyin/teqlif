import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../screens/home_screen.dart';

final liveAdsProvider = FutureProvider.autoDispose<List<AdModel>>((ref) async {
  final params = <String, dynamic>{'status': 'ACTIVE', 'isLive': true};
  final res = await ApiClient().get(Endpoints.ads, params: params);
  final list = res.data as List<dynamic>;
  // Hem API filtresini kullan hem de istemci tarafında isLive kontrolü yap (garanti olsun)
  return list
      .map((e) => AdModel.fromJson(e as Map<String, dynamic>))
      .where((ad) => ad.isLive)
      .toList();
});

class LiveStories extends ConsumerWidget {
  const LiveStories({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveAdsAsync = ref.watch(liveAdsProvider);

    return liveAdsAsync.when(
      data: (ads) {
        if (ads.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 110,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: ads.length,
            itemBuilder: (context, index) {
              final ad = ads[index];
              return _StoryItem(ad: ad);
            },
          ),
        );
      },
      loading: () => const _LiveStoriesSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final AdModel ad;

  const _StoryItem({required this.ad});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/ad/${ad.id}'),
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00B4CC),
                        const Color(0xFF00B4CC).withOpacity(0.5),
                        Colors.purple,
                        const Color(0xFFEF4444),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFFF4F7FA),
                      backgroundImage: ad.images.isNotEmpty
                          ? CachedNetworkImageProvider(imageUrl(ad.images.first))
                          : null,
                      child: ad.images.isEmpty
                          ? Text(ad.category?.icon ?? '📦',
                              style: const TextStyle(fontSize: 24))
                          : null,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    'CANLI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ad.user?.name?.split(' ').first ?? 'Katılımcı',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF4A5568),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveStoriesSkeleton extends StatelessWidget {
  const _LiveStoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Container(
            width: 80,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
