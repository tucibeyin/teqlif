import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';
import '../../config/theme.dart';
import '../../services/storage_service.dart';
import '../shimmer_loading.dart';

class RaidEndedOverlay extends StatefulWidget {
  final int streamId;
  final String hostUsername;
  final String? hostThumbnailUrl;
  final VoidCallback onClose;
  final void Function(int targetStreamId) onRaid;

  const RaidEndedOverlay({
    super.key,
    required this.streamId,
    required this.hostUsername,
    required this.onClose,
    required this.onRaid,
    this.hostThumbnailUrl,
  });

  @override
  State<RaidEndedOverlay> createState() => _RaidEndedOverlayState();
}

class _RaidEndedOverlayState extends State<RaidEndedOverlay>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>>? _targets;
  bool _loading = true;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fetchTargets();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchTargets() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final resp = await http.get(
        Uri.parse('$kBaseUrl/streams/${widget.streamId}/raid-targets'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final list = (jsonDecode(resp.body) as List)
            .cast<Map<String, dynamic>>();
        setState(() { _targets = list; _loading = false; });
      } else {
        setState(() { _targets = []; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _targets = []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xEE0D0D0D),
              Color(0xEE1A0A00),
              Color(0xEE0D0D0D),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: safeBottom > 0 ? 0 : 16,
              left: 16,
              right: 16,
            ),
            child: Column(
              children: [
                // ── Kapat butonu ────────────────────────────────────────────
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white54, size: 24),
                    padding: EdgeInsets.zero,
                  ),
                ),

                // ── Host profil fotoğrafı (soluklaşan) ─────────────────────
                _HostBanner(
                  username: widget.hostUsername,
                  thumbnailUrl: widget.hostThumbnailUrl,
                ),

                const SizedBox(height: 20),

                // ── Divider ─────────────────────────────────────────────────
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        kPrimary.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Baskın başlığı ──────────────────────────────────────────
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🔥', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Eğlence Devam Ediyor!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Diğer Yayınlara Baskın Yap',
                  style: TextStyle(
                    color: Color(0xFFFB923C),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 16),

                // ── Hedef kartlar ───────────────────────────────────────────
                Expanded(
                  child: _loading
                      ? _buildShimmer()
                      : (_targets == null || _targets!.isEmpty)
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.live_tv_outlined,
                                      color: Colors.white24, size: 40),
                                  SizedBox(height: 8),
                                  Text(
                                    'Şu an başka aktif yayın yok',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: _targets!.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _RaidTargetCard(
                                data: _targets![i],
                                onTap: () =>
                                    widget.onRaid(_targets![i]['stream_id'] as int),
                              ),
                            ),
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ShimmerBox(
            height: 80,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ── Soluklaşan Host banner ───────────────────────────────────────────────────

class _HostBanner extends StatelessWidget {
  final String username;
  final String? thumbnailUrl;

  const _HostBanner({required this.username, this.thumbnailUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.transparent],
            stops: [0.4, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: kPrimary.withValues(alpha: 0.5), width: 2),
            ),
            child: ClipOval(
              child: thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imgUrl(thumbnailUrl!),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _avatarFallback(),
                    )
                  : _avatarFallback(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '@$username',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bu yayın sona erdi. Teşekkürler! 👋',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _avatarFallback() => Container(
        color: const Color(0xFF1E293B),
        child: const Icon(Icons.person_rounded, color: Colors.white38, size: 32),
      );
}

// ── Tek raid hedef kartı ─────────────────────────────────────────────────────

class _RaidTargetCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _RaidTargetCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumbUrl = data['thumbnail_url'] as String?;
    final title = data['title'] as String? ?? '';
    final hostName = data['host_name'] as String? ?? '';
    final viewerCount = data['viewer_count'] as int? ?? 0;
    final hypeScore = data['hype_score'] as int? ?? 0;
    final category = data['category'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF1C1C1C), Color(0xFF2A1000)],
          ),
          border: Border.all(
            color: kPrimary.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(11)),
              child: SizedBox(
                width: 80,
                height: 80,
                child: thumbUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imgUrl(thumbUrl),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ShimmerBox(
                          width: 80,
                          height: 80,
                        ),
                        errorWidget: (_, __, ___) => _thumbFallback(),
                      )
                    : _thumbFallback(),
              ),
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Başlık + kategori rozeti
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (category.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: kPrimary.withValues(alpha: 0.5),
                                  width: 0.8),
                            ),
                            child: Text(
                              category,
                              style: const TextStyle(
                                color: kPrimary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Host adı
                    Text(
                      '@$hostName',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),

                    // İzleyici + hype
                    Row(
                      children: [
                        const Icon(Icons.remove_red_eye_outlined,
                            color: Colors.white38, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          '$viewerCount',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                        if (hypeScore > 0) ...[
                          const SizedBox(width: 10),
                          const Text('🔥',
                              style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 2),
                          Text(
                            '$hypeScore',
                            style: TextStyle(
                              color: hypeScore >= 80
                                  ? const Color(0xFFFB923C)
                                  : Colors.white54,
                              fontSize: 11,
                              fontWeight: hypeScore >= 80
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFEF4444),
                                Color(0xFFFB923C)
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Baskın Yap!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbFallback() => Container(
        color: const Color(0xFF1A1A1A),
        child: const Icon(Icons.live_tv_rounded,
            color: Colors.white24, size: 28),
      );
}
