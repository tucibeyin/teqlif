import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../config/api.dart';
import '../../config/app_colors.dart';
import '../../core/app_exception.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/story.dart';
import '../../providers/story_provider.dart';
import '../../services/storage_service.dart';
import '../../services/story_service.dart';
import '../../services/stream_service.dart';
import '../live/viewer_stream_screen.dart';
import '../public_profile_screen.dart';

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
  int? _currentUserId;

  // ── Video kaynakları ──────────────────────────────────────────────────────
  VideoPlayerController? _videoCtrl;
  bool _videoLoading = true;
  bool _advancePending = false;

  // ── Live redirect kaynakları ──────────────────────────────────────────────
  AnimationController? _pulseAnim;    // avatar nabız animasyonu
  AnimationController? _liveTimerAnim; // 5 saniyelik otomatik geçiş
  bool _joiningLive = false;

  StoryItem get _currentItem => widget.group.items[_itemIndex];

  /// Mevcut kullanıcı bu grubun sahibi mi? (Kim Gördü? görünürlüğü için)
  bool get _isMine =>
      _currentUserId != null && _currentUserId == widget.group.user.id;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadItem(0);
    });
  }

  Future<void> _loadCurrentUserId() async {
    final info = await StorageService.getUserInfo();
    if (mounted) setState(() => _currentUserId = info?['id'] as int?);
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

    // Görüntüleme kaydı — backend kendi görüntülemesini ve tekrarları yoksayar
    StoryService.recordStoryView(item.id).catchError((_) {});
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

  // ── Kim Gördü? ────────────────────────────────────────────────────────────

  Future<void> _showViewersSheet() async {
    final item = _currentItem;
    // Videoyu durdur (sheet açıkken devam etmesin)
    _videoCtrl?.pause();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ViewersSheet(storyId: item.id),
    );

    // Sheet kapandığında videoyu sürdür
    _videoCtrl?.play();
  }

  // ── Hikaye Sil ────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteStory() async {
    // View isteği sunucuda işleniyorken DELETE gönderilmesini önlemek için
    // önce videoyu durdur, kısa süre bekle
    _videoCtrl?.pause();
    await Future.delayed(const Duration(milliseconds: 300));

    final l = AppLocalizations.of(context)!;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.storyDelete),
        content: Text(l.storyDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l.btnDelete),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      // İptal → videoyu sürdür
      _videoCtrl?.play();
      return;
    }
    try {
      await StoryService.deleteStory(_currentItem.id);
      if (!mounted) return;
      // Provider'ı geçersiz kıl → tray arka planda güncellenir
      ProviderScope.containerOf(context).invalidate(myStoriesProvider);
      // Sıradaki hikayeye geç; kalmadıysa viewer'ı kapat
      if (_itemIndex < widget.group.items.length - 1) {
        _loadItem(_itemIndex + 1);
      } else {
        widget.onClose();
      }
    } catch (e, st) {
      // Story zaten silinmişse (expired veya önceden silindi) başarı say
      if (e is AppException && (e.code == 'NOT_FOUND' || e.statusCode == 404)) {
        if (!mounted) return;
        ProviderScope.containerOf(context).invalidate(myStoriesProvider);
        if (_itemIndex < widget.group.items.length - 1) {
          _loadItem(_itemIndex + 1);
        } else {
          widget.onClose();
        }
        return;
      }
      await Sentry.captureException(e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.storyDeleteFailed)),
        );
        _videoCtrl?.play();
      }
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
    return GestureDetector(
      // Aşağı kaydır → kapat | Yukarı kaydır → profil
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 400) {
          widget.onClose();
        } else if (v < -400) {
          _goToProfile(context);
        }
      },
      child: Stack(
      fit: StackFit.expand,
      children: [
        isLive ? _buildLiveRedirectCard(context) : _buildVideoArea(),
        // Tap + swipe nav yalnızca video öğelerinde
        if (!isLive) _buildTapNav(),
        _buildProgressBars(context),
        _buildUserOverlay(context),
        // Kendi hikayesindeyse altta "Kim Gördü?" butonu göster
        if (_isMine && !isLive) _buildViewersButton(context),
      ],
      ),
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
          fit: BoxFit.contain,
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
                            errorWidget: (_, __, ___) =>
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

  // ── Tap + Swipe navigasyon ────────────────────────────────────────────────

  Widget _buildTapNav() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Sol %30 tap → geri | Sağ %70 tap → ileri
      onTapUp: (details) {
        final width = MediaQuery.of(context).size.width;
        if (details.localPosition.dx < width * 0.3) {
          _retreatItem();
        } else {
          _advanceItem();
        }
      },
      // Sola kaydır → ileri | Sağa kaydır → geri
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -300) {
          _advanceItem();
        } else if (v > 300) {
          _retreatItem();
        }
      },
      child: const SizedBox.expand(),
    );
  }

  // ── Profil navigasyonu ────────────────────────────────────────────────────

  void _goToProfile(BuildContext context) {
    final user = widget.group.user;
    _videoCtrl?.pause();
    if (_isMine) {
      // Kendi profili → normal profil ekranı
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PublicProfileScreen(
            username: user.username,
            userId: user.id,
          ),
        ))
        .then((_) => _videoCtrl?.play());
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

  // ── "Kim Gördü?" altta ortalanmış buton ──────────────────────────────────

  Widget _buildViewersButton(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final bottomPad = MediaQuery.of(context).padding.bottom + 24;
    return Positioned(
      bottom: bottomPad,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _showViewersSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.remove_red_eye_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 7),
                Text(
                  l.storyWhoViewed,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
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
          // Kendi hikayesiyse: üç nokta menü
          if (_isMine) ...[
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
                color: Colors.white,
                size: 24,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
              color: AppColors.surface(context),
              onSelected: (val) {
                if (val == 'delete') _confirmDeleteStory();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!.storyDelete,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
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

// ── Kim Gördü? bottom sheet ───────────────────────────────────────────────────

class _ViewersSheet extends StatefulWidget {
  final int storyId;
  const _ViewersSheet({required this.storyId});

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  List<StoryViewer>? _viewers;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final viewers = await StoryService.getStoryViewers(widget.storyId);
      if (mounted) setState(() { _viewers = viewers; _loading = false; });
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)!.storyViewersLoadFailed;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tutma çubuğu
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          // Başlık
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.remove_red_eye_outlined,
                    size: 18, color: AppColors.textSecondary(context)),
                const SizedBox(width: 8),
                Text(
                  l.storyWhoViewed,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                if (_viewers != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(${_viewers!.length})',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: AppColors.divider(context)),
          // İçerik
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            )
          else if (_viewers!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l.storyNoViewersYet,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.only(bottom: bottomPad + 8),
                itemCount: _viewers!.length,
                itemBuilder: (_, i) {
                  final v = _viewers![i];
                  final initial =
                      v.username.isNotEmpty ? v.username[0].toUpperCase() : '?';
                  final timeAgo = _formatTime(context, v.viewedAt);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kPrimaryLight.withOpacity(0.25),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: kPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    title: Text(
                      v.username,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      v.fullName,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                    trailing: Text(
                      timeAgo,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inHours < 1) return '${diff.inMinutes}d önce';
    if (diff.inDays < 1) return '${diff.inHours}s önce';
    return '${diff.inDays}g önce';
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
