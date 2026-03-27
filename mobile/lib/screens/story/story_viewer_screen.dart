import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../config/api.dart';
import '../../config/theme.dart';
import '../../models/story.dart';

/// Tam ekran Instagram/Snapchat tarzı story izleyicisi.
///
/// Dış navigasyon (kullanıcılar arası): [PageView] ile sağa/sola swipe.
/// İç navigasyon (aynı kullanıcının hikayesi): ekrana dokunma.
///   - Sol %30 → önceki hikaye
///   - Sağ %70 → sonraki hikaye
///
/// Bellek yönetimi:
///   Her [_GroupPage] kendi [VideoPlayerController]'ını yönetir.
///   Hikaye değiştiğinde eski controller dispose edilir, ardından yenisi
///   başlatılır — aynı anda yalnızca 1 controller aktiftir. PageView'ın
///   sayfa dışı bıraktığı widget'lar Flutter tarafından dispose edildiğinde
///   [_GroupPageState.dispose] controller'ı da temizler.
class StoryViewerScreen extends StatefulWidget {
  final List<UserStoryGroup> groups;
  final int initialGroupIndex;

  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialGroupIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToGroup(int index) {
    if (!mounted) return;
    if (index < 0 || index >= widget.groups.length) {
      Navigator.of(context).pop();
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        physics: const ClampingScrollPhysics(),
        itemCount: widget.groups.length,
        itemBuilder: (ctx, i) => _GroupPage(
          // ValueKey: farklı kullanıcıya ait sayfaların karışmaması için
          key: ValueKey(widget.groups[i].user.id),
          group: widget.groups[i],
          onNextGroup: () => _goToGroup(i + 1),
          onPrevGroup: () => _goToGroup(i - 1),
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

// ── Tek kullanıcının hikaye sayfası ─────────────────────────────────────────

class _GroupPage extends StatefulWidget {
  final UserStoryGroup group;
  final VoidCallback onNextGroup;
  final VoidCallback onPrevGroup;
  final VoidCallback onClose;

  const _GroupPage({
    super.key,
    required this.group,
    required this.onNextGroup,
    required this.onPrevGroup,
    required this.onClose,
  });

  @override
  State<_GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<_GroupPage> {
  int _storyIndex = 0;
  VideoPlayerController? _controller;
  bool _loading = true;
  // Aynı anda birden fazla _advanceStory çağrısını önler
  bool _advancePending = false;

  @override
  void initState() {
    super.initState();
    // ref ve context initState'te henüz tam bağlı değil; post-frame güvenli
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadStory(0);
    });
  }

  @override
  void dispose() {
    _releaseController();
    super.dispose();
  }

  // ── Controller yaşam döngüsü ──────────────────────────────────────────────

  void _releaseController() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _controller = null;
  }

  /// Video ilerleyişini dinler; süre dolduğunda sıradaki hikayeye geçer.
  void _videoListener() {
    if (!mounted || _controller == null || _advancePending) return;
    final val = _controller!.value;
    if (val.isInitialized &&
        !val.isBuffering &&
        val.position >= val.duration - const Duration(milliseconds: 300)) {
      _advancePending = true;
      _controller!.removeListener(_videoListener);
      // Listener içinden doğrudan setState çağırmaktan kaçın
      Future.microtask(_advanceStory);
    }
  }

  Future<void> _loadStory(int index) async {
    if (!mounted) return;
    _advancePending = false;

    // Eski controller'ı serbest bırak
    _releaseController();
    setState(() => _loading = true);

    final story = widget.group.stories[index];
    final url = imgUrl(story.videoUrl);
    if (url.isEmpty) {
      _advanceStory();
      return;
    }

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await ctrl.initialize();
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
      await ctrl.dispose();
      if (mounted) _advanceStory();
      return;
    }

    if (!mounted) {
      await ctrl.dispose();
      return;
    }

    ctrl.addListener(_videoListener);
    await ctrl.play();

    setState(() {
      _controller = ctrl;
      _storyIndex = index;
      _loading = false;
    });
  }

  // ── Navigasyon ────────────────────────────────────────────────────────────

  void _advanceStory() {
    if (!mounted) return;
    if (_storyIndex < widget.group.stories.length - 1) {
      _loadStory(_storyIndex + 1);
    } else {
      widget.onNextGroup();
    }
  }

  void _retreatStory() {
    if (!mounted) return;
    if (_storyIndex > 0) {
      _loadStory(_storyIndex - 1);
    } else {
      widget.onPrevGroup();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoArea(),
        _buildTapNav(),
        _buildProgressBars(context),
        _buildUserOverlay(context),
      ],
    );
  }

  // Video veya yükleniyor göstergesi
  Widget _buildVideoArea() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ctrl.value.size.width,
            height: ctrl.value.size.height,
            child: VideoPlayer(ctrl),
          ),
        ),
      ),
    );
  }

  // Sol %30 önceki / sağ %70 sonraki — GestureDetector'lar
  Widget _buildTapNav() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _retreatStory,
            child: const SizedBox.expand(),
          ),
        ),
        Expanded(
          flex: 7,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _advanceStory,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  // Üst ilerleme çubukları — her hikaye için 1 çizgi
  Widget _buildProgressBars(BuildContext context) {
    final total = widget.group.stories.length;
    final topPad = MediaQuery.of(context).padding.top + 10;
    return Positioned(
      top: topPad,
      left: 10,
      right: 10,
      child: Row(
        children: List.generate(total, (i) {
          final barState = i < _storyIndex
              ? _BarState.full
              : i > _storyIndex
                  ? _BarState.empty
                  : _BarState.active;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < total - 1 ? 3.0 : 0),
              child: _StoryProgressBar(
                state: barState,
                controller: barState == _BarState.active ? _controller : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  // Avatar + kullanıcı adı + kapat butonu
  Widget _buildUserOverlay(BuildContext context) {
    final user = widget.group.user;
    final avatarUrl = user.profileImageThumbUrl ?? user.profileImageUrl;
    final resolved = avatarUrl != null ? imgUrl(avatarUrl) : null;
    final topPad = MediaQuery.of(context).padding.top + 28;

    return Positioned(
      top: topPad,
      left: 12,
      right: 12,
      child: Row(
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: ClipOval(
              child: resolved != null
                  ? CachedNetworkImage(
                      imageUrl: resolved,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _InitialsBubble(username: user.username),
                    )
                  : _InitialsBubble(username: user.username),
            ),
          ),
          const SizedBox(width: 9),
          // Kullanıcı adı
          Expanded(
            child: Text(
              user.username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Kapat
          GestureDetector(
            onTap: widget.onClose,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.close,
                color: Colors.white,
                size: 24,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Progress bar ─────────────────────────────────────────────────────────────

enum _BarState { full, empty, active }

/// [_BarState.active] + controller varsa VideoPlayer pozisyonunu
/// [ValueListenableBuilder] ile günceller — sadece ilgili çubuk rebuild edilir.
class _StoryProgressBar extends StatelessWidget {
  final _BarState state;
  final VideoPlayerController? controller;

  const _StoryProgressBar({super.key, required this.state, this.controller});

  @override
  Widget build(BuildContext context) {
    if (state != _BarState.active || controller == null) {
      return LinearProgressIndicator(
        value: state == _BarState.full ? 1.0 : 0.0,
        backgroundColor: Colors.white30,
        valueColor: const AlwaysStoppedAnimation(Colors.white),
        minHeight: 2.5,
        borderRadius: BorderRadius.circular(2),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller!,
      builder: (_, val, __) {
        final dur = val.duration.inMilliseconds;
        final pos = val.position.inMilliseconds;
        return LinearProgressIndicator(
          value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0,
          backgroundColor: Colors.white30,
          valueColor: const AlwaysStoppedAnimation(Colors.white),
          minHeight: 2.5,
          borderRadius: BorderRadius.circular(2),
        );
      },
    );
  }
}

// ── Profil fotoğrafı yoksa baş harf ─────────────────────────────────────────

class _InitialsBubble extends StatelessWidget {
  final String username;

  const _InitialsBubble({required this.username});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kPrimaryDark,
      child: Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
