import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/live_streams_provider.dart';

class LiveStories extends ConsumerWidget {
  const LiveStories({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamsAsync = ref.watch(liveStreamsProvider);

    return streamsAsync.when(
      data: (streams) {
        if (streams.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: streams.length,
            itemBuilder: (context, index) {
              return _StoryItem(stream: streams[index]);
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
  final Map<String, dynamic> stream;

  const _StoryItem({required this.stream});

  void _onTap(BuildContext context) {
    final type = stream['type'] as String?;
    if (type == 'channel') {
      context.push('/live/${stream['hostId']}');
    } else {
      context.push('/ad/${stream['adId']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String hostName = stream['hostName'] as String? ?? 'Yayıncı';
    final String? imageUrl = stream['imageUrl'] as String?;
    final int viewerCount = stream['viewerCount'] as int? ?? 0;

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Gradient border ring
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFEF4444),
                        Color(0xFFEC4899),
                        Color(0xFF8B5CF6),
                        Color(0xFF00B4CC),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0xFFF4F7FA),
                        backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                            ? CachedNetworkImageProvider(imageUrl)
                            : null,
                        child: (imageUrl == null || imageUrl.isEmpty)
                            ? const Icon(Icons.videocam_rounded,
                                size: 26, color: Color(0xFFEF4444))
                            : null,
                      ),
                    ),
                  ),
                ),
                // Viewer count badge
                Positioned(
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: viewerCount > 0
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.remove_red_eye_rounded,
                                  size: 8, color: Colors.white),
                              const SizedBox(width: 2),
                              Text(
                                '$viewerCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'CANLI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hostName.split(' ').first,
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
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Container(
            width: 80,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[200]!,
              highlightColor: Colors.white,
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
