import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_compress/video_compress.dart';

import '../../config/api.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/story.dart';
import '../../providers/story_provider.dart';
import '../../screens/story/story_viewer_screen.dart';
import '../../services/storage_service.dart';
import '../../services/story_service.dart';

/// Takip edilen kullanıcıların video hikayelerini Instagram stilinde gösterir.
///
/// Yatay liste:
///   Index 0 → "Hikayen" (+) butonu — video seçme & yükleme
///   Index 1+ → Takip edilen kullanıcıların story grupları
///
/// Scroll optimizasyonu: [ClampingScrollPhysics] kullanıldığından yatay
/// kaydırma hareketi dikey [RefreshIndicator]'ı tetiklemez.
class StoryTray extends ConsumerStatefulWidget {
  const StoryTray({super.key});

  @override
  ConsumerState<StoryTray> createState() => _StoryTrayState();
}

class _StoryTrayState extends ConsumerState<StoryTray> {
  String? _username;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final info = await StorageService.getUserInfo();
    if (!mounted) return;
    setState(() => _username = info?['username'] as String?);
  }

  // ── Video seç → sıkıştır → yükle ─────────────────────────────────────────

  Future<void> _pickAndUpload() async {
    final l = AppLocalizations.of(context)!;

    // Video seç (en fazla 12 saniye)
    final XFile? picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 12),
    );
    if (picked == null || !mounted) return;

    // Süre kontrolü — image_picker maxDuration'a rağmen bazı platformlarda
    // daha uzun video dönebilir; ekstra güvenlik katmanı.
    final rawFile = File(picked.path);
    final rawStat = await rawFile.stat();
    // 12s × ~5 Mb/s (ham) = ~60 MB; bunun üstü zaten olmamalı.
    // Video süresi için video_compress.getMediaInfo kullanılır.
    final info = await VideoCompress.getMediaInfo(picked.path);
    final durationMs = info.duration ?? 0;
    if (durationMs > 12500 && mounted) {
      // 500ms tolerans
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.storyTooLong)),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      // Sıkıştır (MediumQuality ≈ 720p — boyutu ~%60–80 oranında düşürür)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.storyProcessing),
            duration: const Duration(seconds: 30),
          ),
        );
      }

      final compressed = await VideoCompress.compressVideo(
        picked.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (compressed?.path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.storyUploadFailed)),
        );
        return;
      }

      // Yükle
      await StoryService.uploadStory(File(compressed!.path!));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.storyUploadSuccess)),
      );

      // Listeyi yenile
      ref.invalidate(groupedStoriesProvider);
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.storyUploadFailed)),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Ana build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupedStoriesProvider);

    return Container(
      color: AppColors.surface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          groupsAsync.when(
            loading: () => _buildTray(context, null, isLoading: true),
            error: (_, __) => _buildTray(context, []),
            data: (groups) => _buildTray(context, groups),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.divider(context)),
        ],
      ),
    );
  }

  Widget _buildTray(
    BuildContext context,
    List<UserStoryGroup>? groups, {
    bool isLoading = false,
  }) {
    // Index 0 = "Hikayen" + 1..N = grup öğeleri (veya shimmer)
    final extraCount = isLoading ? 3 : (groups?.length ?? 0);
    final itemCount = 1 + extraCount;

    return SizedBox(
      height: 108,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: itemCount,
        itemBuilder: (_, i) {
          if (i == 0) return _MyStoryItem(username: _username, isUploading: _isUploading, onTap: _pickAndUpload);
          if (isLoading) return _buildShimmerItem(context);
          return _StoryGroupItem(
            group: groups![i - 1],
            groups: groups!,
            groupIndex: i - 1,
          );
        },
      ),
    );
  }

  // ── Loading: shimmer yuvarlaklar ──────────────────────────────────────────

  Widget _buildShimmerItem(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
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
    );
  }
}

// ── "Hikayen" (+) butonu ─────────────────────────────────────────────────────

class _MyStoryItem extends StatelessWidget {
  final String? username;
  final bool isUploading;
  final VoidCallback onTap;

  const _MyStoryItem({
    required this.username,
    required this.isUploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final initial = (username?.isNotEmpty == true) ? username![0].toUpperCase() : '?';

    return GestureDetector(
      onTap: isUploading ? null : onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Dış halka — gri (henüz hikaye yok) veya gradient (varsa Aşama 3)
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.border(context),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: isUploading
                        ? Container(
                            color: AppColors.primaryBg(context),
                            child: const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: kPrimary,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: AppColors.primaryBg(context),
                            alignment: Alignment.center,
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                              ),
                            ),
                          ),
                  ),
                ),
                // "+" badge
                if (!isUploading)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: kPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              l.storyMyStory,
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

// ── Takip edilen kullanıcının story grubu ────────────────────────────────────

class _StoryGroupItem extends StatelessWidget {
  final UserStoryGroup group;
  final List<UserStoryGroup> groups;
  final int groupIndex;

  const _StoryGroupItem({
    required this.group,
    required this.groups,
    required this.groupIndex,
  });

  @override
  Widget build(BuildContext context) {
    // Profil küçük resmi — thumb varsa onu, yoksa tam boyutu göster
    final avatarUrl = group.user.profileImageThumbUrl ?? group.user.profileImageUrl;
    final resolvedUrl = avatarUrl != null ? imgUrl(avatarUrl) : null;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            groups: groups,
            initialGroupIndex: groupIndex,
          ),
        ),
      ),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient ring → beyaz boşluk → avatar
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
                  child: resolvedUrl != null && resolvedUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: resolvedUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => _InitialAvatar(
                            username: group.user.username,
                            context: context,
                          ),
                          errorWidget: (_, __, ___) => _InitialAvatar(
                            username: group.user.username,
                            context: context,
                          ),
                        )
                      : _InitialAvatar(
                          username: group.user.username,
                          context: context,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              group.user.username,
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
