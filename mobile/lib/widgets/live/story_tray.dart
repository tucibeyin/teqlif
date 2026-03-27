import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/api.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/stream.dart';
import '../../providers/live_stream_provider.dart';

/// Takip edilen aktif canlı yayınları Instagram hikayesi stilinde
/// yatay kaydırılabilir bir çubukta gösterir.
///
/// Scroll optimizasyonu: [ClampingScrollPhysics] kullanıldığından
/// yatay kaydırma hareketi dikey [RefreshIndicator]'ı tetiklemez.
class StoryTray extends ConsumerWidget {
  /// Story öğesine tıklandığında hangi yayına gidileceğini üst widget belirler.
  final void Function(StreamOut stream) onTap;

  const StoryTray({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final streamsAsync = ref.watch(followedStreamsProvider);

    return Container(
      color: AppColors.surface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              l.storyTrayTitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary(context),
                letterSpacing: 0.3,
              ),
            ),
          ),
          streamsAsync.when(
            loading: _buildSkeleton,
            error: (_, __) => _buildError(context, l),
            data: (streams) => streams.isEmpty
                ? _buildEmpty(context, l)
                : _buildList(context, streams),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.divider(context)),
        ],
      ),
    );
  }

  // ── Loading: 5 shimmer yuvarlak ──────────────────────────────────────────

  Widget _buildSkeleton() {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: 5,
        itemBuilder: (context, _) => Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Shimmer.fromColors(
                baseColor: AppColors.border(context),
                highlightColor: AppColors.surfaceVariant(context),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Shimmer.fromColors(
                baseColor: AppColors.border(context),
                highlightColor: AppColors.surfaceVariant(context),
                child: Container(
                  width: 44,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────

  Widget _buildError(BuildContext context, AppLocalizations l) {
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_outlined,
              size: 15, color: AppColors.textTertiary(context)),
          const SizedBox(width: 5),
          Text(
            l.storyTrayError,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty ────────────────────────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context, AppLocalizations l) {
    return SizedBox(
      height: 44,
      child: Center(
        child: Text(
          l.storyTrayEmpty,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }

  // ── Data: yatay story listesi ─────────────────────────────────────────────

  Widget _buildList(BuildContext context, List<StreamOut> streams) {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        // ClampingScrollPhysics: yatay kaydırma hiçbir zaman dikey
        // RefreshIndicator'a "taşmaz" — iki eksen birbirini kesmez.
        physics: const ClampingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: streams.length,
        itemBuilder: (_, i) => _StoryItem(
          stream: streams[i],
          onTap: () => onTap(streams[i]),
        ),
      ),
    );
  }
}

// ── Story öğesi ─────────────────────────────────────────────────────────────

class _StoryItem extends StatelessWidget {
  final StreamOut stream;
  final VoidCallback onTap;

  const _StoryItem({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Thumbnail varsa preview göster, yoksa yayıncı baş harfi
    final previewUrl = stream.thumbnailUrl != null
        ? imgUrl(stream.thumbnailUrl)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient ring → beyaz boşluk → içerik
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [kPrimary, kPrimaryLight, Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(2.5),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface(context),
                ),
                padding: const EdgeInsets.all(1.5),
                child: ClipOval(
                  child: previewUrl != null && previewUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: previewUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => _InitialAvatar(
                            username: stream.host.username,
                            context: context,
                          ),
                          errorWidget: (_, __, ___) => _InitialAvatar(
                            username: stream.host.username,
                            context: context,
                          ),
                        )
                      : _InitialAvatar(
                          username: stream.host.username,
                          context: context,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              stream.host.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profil fotoğrafı olmadığında: baş harf avatar ───────────────────────────

class _InitialAvatar extends StatelessWidget {
  final String username;
  final BuildContext context;

  const _InitialAvatar({required this.username, required this.context});

  @override
  Widget build(BuildContext _) {
    return Container(
      color: AppColors.primaryBg(context),
      alignment: Alignment.center,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: const TextStyle(
          color: kPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
    );
  }
}
