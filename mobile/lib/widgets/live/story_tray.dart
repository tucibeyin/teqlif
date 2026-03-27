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

/// Takip edilen kullanıcıların hybrid hikaye tepsisini Instagram stilinde gösterir.
///
/// Yatay liste:
///   Index 0 → "Hikayen" (+) butonu — video seçme & yükleme
///   Index 1+ → Takip edilen kullanıcıların hybrid story grupları
///
/// Scroll optimizasyonu: [ClampingScrollPhysics] kullanıldığından yatay
/// kaydırma hareketi dikey [RefreshIndicator]'ı tetiklemez.
class StoryTray extends ConsumerStatefulWidget {
  const StoryTray({super.key});

  @override
  ConsumerState<StoryTray> createState() => _StoryTrayState();
}

class _StoryTrayState extends ConsumerState<StoryTray> {
  int? _userId;
  String? _username;
  String? _fullName;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final info = await StorageService.getUserInfo();
    if (!mounted) return;
    setState(() {
      _userId = info?['id'] as int?;
      _username = info?['username'] as String?;
      _fullName = info?['full_name'] as String?;
    });
  }

  // ── Video seç → sıkıştır → yükle ─────────────────────────────────────────

  Future<void> _pickAndUpload() async {
    final l = AppLocalizations.of(context)!;

    // Kaynak seç: kamera veya galeri
    final source = await showModalBottomSheet<_VideoSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VideoSourceSheet(l: l),
    );
    if (source == null || !mounted) return;

    final XFile? picked = await ImagePicker().pickVideo(
      source: source == _VideoSource.gallery
          ? ImageSource.gallery
          : ImageSource.camera,
      maxDuration: const Duration(seconds: 15),
    );
    if (picked == null || !mounted) return;

    // Süre kontrolü — image_picker maxDuration'a rağmen bazı platformlarda
    // daha uzun video dönebilir; ekstra güvenlik katmanı.
    final info = await VideoCompress.getMediaInfo(picked.path);
    final durationMs = info.duration ?? 0;
    if (durationMs > 15500 && mounted) {
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
        quality: VideoQuality.DefaultQuality,
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

      // Listeleri yenile
      ref.invalidate(storyGroupsProvider);
      ref.invalidate(myStoriesProvider);
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
    final groupsAsync = ref.watch(storyGroupsProvider);

    return Container(
      color: AppColors.bg(context),
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
          if (i == 0) {
            return _MyStoryItem(
              userId: _userId,
              username: _username,
              fullName: _fullName,
              isUploading: _isUploading,
              onUpload: _pickAndUpload,
            );
          }
          if (isLoading) return _buildShimmerItem(context);
          return _StoryGroupItem(
            group: groups![i - 1],
            groups: groups,
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

// ── "Hikayen" butonu — kendi hikayeleri varsa gradient halka gösterir ─────────

class _MyStoryItem extends ConsumerWidget {
  final int? userId;
  final String? username;
  final String? fullName;
  final bool isUploading;
  final VoidCallback onUpload;

  const _MyStoryItem({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.isUploading,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final myStoriesAsync = ref.watch(myStoriesProvider);
    final myStories = myStoriesAsync.valueOrNull ?? [];
    final hasStories = myStories.isNotEmpty && !isUploading;
    final initial =
        (username?.isNotEmpty == true) ? username![0].toUpperCase() : '?';

    void onTap() {
      if (isUploading) return;
      if (hasStories && userId != null) {
        // Kendi hikayelerini viewer'da aç
        final selfGroup = UserStoryGroup(
          user: StoryAuthor(
            id: userId!,
            username: username ?? '',
            fullName: fullName ?? '',
            profileImageUrl: null,
            profileImageThumbUrl: null,
          ),
          items: myStories,
          latestActivityAt: myStories.first.createdAt ?? DateTime.now(),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                StoryViewerScreen(groups: [selfGroup], initialIndex: 0),
          ),
        );
      } else {
        onUpload();
      }
    }

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
                // Dış halka: hikaye varsa gradient, yoksa gri border
                if (hasStories)
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
                        child: Container(
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
                  )
                else
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
                // "+" badge — her zaman göster, tıklanınca yükleme başlatır
                if (!isUploading)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: onUpload,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: kPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
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

// ── Takip edilen kullanıcının hybrid story grubu ──────────────────────────────

class _StoryGroupItem extends StatelessWidget {
  final UserStoryGroup group;
  final List<UserStoryGroup> groups;
  final int groupIndex;

  const _StoryGroupItem({
    required this.group,
    required this.groups,
    required this.groupIndex,
  });

  /// Grubun canlı yayın içerip içermediğini kontrol eder.
  bool get _hasLive => group.items.any((i) => i.isLiveRedirect);

  @override
  Widget build(BuildContext context) {
    final avatarUrl =
        group.user.profileImageThumbUrl ?? group.user.profileImageUrl;
    final resolvedUrl = avatarUrl != null ? imgUrl(avatarUrl) : null;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            groups: groups,
            initialIndex: groupIndex,
          ),
        ),
      ),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Gradient ring → beyaz boşluk → avatar
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _hasLive
                        // Canlı yayın varsa kırmızı-turuncu halka
                        ? const LinearGradient(
                            colors: [Color(0xFFFF4136), Color(0xFFFF851B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        // Sadece video hikayesi varsa normal gradient
                        : const LinearGradient(
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
                // Canlı yayın badge'i
                if (_hasLive)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4136),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.surface(context),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'CANLI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
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

// ── Video kaynak seçimi ───────────────────────────────────────────────────────

enum _VideoSource { camera, gallery }

class _VideoSourceSheet extends StatelessWidget {
  final AppLocalizations l;
  const _VideoSourceSheet({required this.l});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          _SourceTile(
            icon: Icons.videocam_outlined,
            label: 'Kamera',
            onTap: () => Navigator.pop(context, _VideoSource.camera),
          ),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            label: 'Galeriden Seç',
            onTap: () => Navigator.pop(context, _VideoSource.gallery),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: kPrimary, size: 26),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary(context),
        ),
      ),
      onTap: onTap,
    );
  }
}
