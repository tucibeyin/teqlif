import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../config/api.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/story.dart';
import '../../services/stream_service.dart';
import 'viewer_stream_screen.dart';

/// Tam ekran Instagram/Snapchat tarzı Hybrid Story izleyicisi.
///
/// Dış navigasyon (kullanıcılar arası): [PageView] ile sağa/sola swipe.
/// İç navigasyon (aynı kullanıcının öğeleri): ekrana dokunma.
///   - Sol %30 → önceki öğe
///   - Sağ %70 → sonraki öğe
///
/// Öğe tipleri:
///   'video'         → VideoPlayer ile tam ekran (BoxFit.cover) otomatik oynatma.
///   'live_redirect' → Nabız atan avatar + "Yayına Katıl" butonu.
///
/// Bellek yönetimi:
///   Her [_GroupPage] kendi kaynaklarını yönetir.
///   Öğe değiştiğinde [_releaseAll] eski VideoPlayerController'ı ve
///   AnimationController'ları dispose eder — aynı anda tek bir aktif
///   kaynak seti mevcuttur. PageView'ın kapattığı sayfalar Flutter
///   tarafından dispose edildiğinde [_GroupPageState.dispose] her şeyi temizler.
class StoryViewerScreen extends StatefulWidget {
  final List<UserStoryGroup> groups;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialIndex,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
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

class _GroupPageState extends State<_GroupPage> with TickerProviderStateMixin {
  int _itemIndex = 0;

  // ── Video kaynakları ──────────────────────────────────────────────────────
  VideoPlayerController? _videoCtrl;
  bool _videoLoading = true;
  bool _advancePending = false;

  // ── Live redirect kaynakları ──────────────────────────────────────────────
  AnimationController? _pulseAnim;    // avatar nabız animasyonu
  AnimationController? _liveTimerAnim; // 5 saniyelik otomatik geçiş
  bool _joiningLive = false;

  StoryItem get _currentItem => widget.group.items[_itemIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadItem(0);
    });
  }

  @override
  void dispose() {
    _releaseAll();
    super.dispose();
  }

  // ── Kaynak yönetimi ───────────────────────────────────────────────────────

  /// Tüm aktif kaynakları (video + animasyon) serbest bırakır.
  /// Her öğe değişiminde ve dispose'da çağrılır.
  void _releaseAll() {
    _releaseVideo();
    _releaseLiveAnims();
  }

  void _releaseVideo() {
    _videoCtrl?.removeListener(_videoListener);
    _videoCtrl?.dispose();
    _videoCtrl = null;
  }

  void _releaseLiveAnims() {
    _pulseAnim?.dispose();
    _pulseAnim = null;
    _liveTimerAnim?.removeStatusListener(_onLiveTimerDone);
    _liveTimerAnim?.dispose();
    _liveTimerAnim = null;
  }

  // ── Öğe yükleme koordinatörü ──────────────────────────────────────────────

  Future<void> _loadItem(int index) async {
    if (!mounted) return;
    _advancePending = false;
    _releaseAll();

    setState(() {
      _itemIndex = index;
      _videoLoading = true;
      _joiningLive = false;
    });

    final item = widget.group.items[index];
    if (item.isVideo) {
      await _loadVideo(item);
    } else {
      _startLiveCard();
    }
  }

  // ── Video yükle ve oynat ──────────────────────────────────────────────────

  Future<void> _loadVideo(StoryItem item) async {
    final url = item.videoUrl != null ? imgUrl(item.videoUrl!) : '';
    if (url.isEmpty) {
      _advanceItem();
      return;
    }

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await ctrl.initialize();
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
      await ctrl.dispose();
      if (mounted) _advanceItem();
      return;
    }

    if (!mounted) {
      await ctrl.dispose();
      return;
    }

    ctrl.addListener(_videoListener);
    await ctrl.play();

    setState(() {
      _videoCtrl = ctrl;
      _videoLoading = false;
    });
  }

  /// Video sonuna yaklaştığında otomatik geçişi tetikler.
  /// Listener içinden setState çağırmamak için [Future.microtask] kullanılır.
  void _videoListener() {
    if (!mounted || _videoCtrl == null || _advancePending) return;
    final val = _videoCtrl!.value;
    if (val.isInitialized &&
        !val.isBuffering &&
        val.position >= val.duration - const Duration(milliseconds: 300)) {
      _advancePending = true;
      _videoCtrl!.removeListener(_videoListener);
      Future.microtask(_advanceItem);
    }
  }

  // ── Canlı yayın kartı ─────────────────────────────────────────────────────

  /// İki AnimationController başlatır:
  ///   [_pulseAnim]    — avatarı nefes aldırır (800ms, looping)
  ///   [_liveTimerAnim] — 5 saniye sonra sıradaki öğeye geçer
  void _startLiveCard() {
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _liveTimerAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _liveTimerAnim!.addStatusListener(_onLiveTimerDone);
    _liveTimerAnim!.forward();

    setState(() => _videoLoading = false);
  }

  void _onLiveTimerDone(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_advancePending) {
      _advancePending = true;
      Future.microtask(_advanceItem);
    }
  }

  // ── Navigasyon ────────────────────────────────────────────────────────────

  void _advanceItem() {
    if (!mounted) return;
    if (_itemIndex < widget.group.items.length - 1) {
      _loadItem(_itemIndex + 1);
    } else {
      widget.onNextGroup();
    }
  }

  void _retreatItem() {
    if (!mounted) return;
    if (_itemIndex > 0) {
      _loadItem(_itemIndex - 1);
    } else {
      widget.onPrevGroup();
    }
  }

  /// "Yayına Katıl" akışı: token çek → ViewerStreamScreen'e geç.
  Future<void> _joinLive() async {
    final item = _currentItem;
    if (item.streamId == null || !mounted) return;
    setState(() => _joiningLive = true);
    try {
      final token = await StreamService.joinStream(item.streamId!);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ViewerStreamScreen(joinToken: token),
        ),
      );
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.storyJoinLiveFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _joiningLive = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLive = _currentItem.isLiveRedirect;
    return Stack(
      fit: StackFit.expand,
      children: [
        isLive ? _buildLiveRedirectCard(context) : _buildVideoArea(),
        // Tap nav yalnızca video öğelerinde — canlı kart kendi butonunu yönetir
        if (!isLive) _buildTapNav(),
        _buildProgressBars(context),
        _buildUserOverlay(context),
      ],
    );
  }

  // ── Video alanı ───────────────────────────────────────────────────────────

  Widget _buildVideoArea() {
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized || _videoLoading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2,
          ),
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

  // ── Canlı yayın yönlendirme kartı ────────────────────────────────────────

  Widget _buildLiveRedirectCard(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final user = widget.group.user;
    final avatarUrl = user.profileImageThumbUrl ?? user.profileImageUrl;
    final resolved = avatarUrl != null ? imgUrl(avatarUrl) : null;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Nabız atan büyük avatar
            if (_pulseAnim != null)
              AnimatedBuilder(
                animation: _pulseAnim!,
                builder: (_, child) => Transform.scale(
                  scale: 1.0 + (_pulseAnim!.value * 0.08),
                  child: child,
                ),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF4136), Color(0xFFFF851B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF4136).withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: resolved != null
                        ? CachedNetworkImage(
                            imageUrl: resolved,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _InitialsBubble(username: user.username),
                          )
                        : _InitialsBubble(username: user.username),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            // "Şu an Canlı Yayında!"
            Text(
              l.storyLiveNow,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              user.username,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            // Yayına Katıl butonu
            ElevatedButton(
              onPressed: _joiningLive ? null : _joinLive,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4136),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 36,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 6,
              ),
              child: _joiningLive
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      l.storyJoinLive,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tap navigasyon (yalnızca video öğelerinde) ────────────────────────────

  Widget _buildTapNav() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _retreatItem,
            child: const SizedBox.expand(),
          ),
        ),
        Expanded(
          flex: 7,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _advanceItem,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  // ── Üst progress barlar ───────────────────────────────────────────────────

  Widget _buildProgressBars(BuildContext context) {
    final total = widget.group.items.length;
    final topPad = MediaQuery.of(context).padding.top + 10;
    return Positioned(
      top: topPad,
      left: 10,
      right: 10,
      child: Row(
        children: List.generate(total, (i) {
          final barState = i < _itemIndex
              ? _BarState.full
              : i > _itemIndex
                  ? _BarState.empty
                  : _BarState.active;
          final isActive = barState == _BarState.active;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < total - 1 ? 3.0 : 0),
              child: _StoryProgressBar(
                state: barState,
                // Video öğesi aktifse controller, canlı ise timer animasyonu ver
                videoController: isActive && _currentItem.isVideo
                    ? _videoCtrl
                    : null,
                liveAnim: isActive && _currentItem.isLiveRedirect
                    ? _liveTimerAnim
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Kullanıcı overlay (avatar + ad + kapat) ───────────────────────────────

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

/// Video öğelerinde [ValueListenableBuilder] ile video konumunu,
/// live_redirect öğelerinde [AnimatedBuilder] ile 5s timer'ı takip eder.
/// Yalnızca kendi alt ağacını rebuild ederek gereksiz yeniden çizimi önler.
class _StoryProgressBar extends StatelessWidget {
  final _BarState state;
  final VideoPlayerController? videoController;
  final AnimationController? liveAnim;

  const _StoryProgressBar({
    super.key,
    required this.state,
    this.videoController,
    this.liveAnim,
  });

  @override
  Widget build(BuildContext context) {
    if (state == _BarState.full) return _bar(1.0);
    if (state == _BarState.empty) return _bar(0.0);

    // Aktif — video
    if (videoController != null) {
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: videoController!,
        builder: (_, val, __) {
          final dur = val.duration.inMilliseconds;
          final pos = val.position.inMilliseconds;
          return _bar(dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0);
        },
      );
    }

    // Aktif — live redirect (5 saniyelik timer)
    if (liveAnim != null) {
      return AnimatedBuilder(
        animation: liveAnim!,
        builder: (_, __) => _bar(liveAnim!.value),
      );
    }

    return _bar(0.0);
  }

  Widget _bar(double value) => LinearProgressIndicator(
        value: value,
        backgroundColor: Colors.white30,
        valueColor: const AlwaysStoppedAnimation(Colors.white),
        minHeight: 2.5,
        borderRadius: BorderRadius.circular(2),
      );
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
