import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api.dart';
import '../../config/theme.dart';
import '../../core/app_exception.dart';
import '../../models/stream.dart';
import '../../providers/live_stream_provider.dart';
import '../../services/captcha_service.dart';
import '../../services/storage_service.dart';
import '../../services/stream_service.dart';
import '../../services/category_service.dart';
import '../../utils/error_helper.dart';
import '../../widgets/live/story_tray.dart';
import '../public_profile_screen.dart';
import 'host_stream_screen.dart';
import 'swipe_live_screen.dart';
import '../../l10n/app_localizations.dart';

class LiveListScreen extends ConsumerStatefulWidget {
  const LiveListScreen({super.key});

  @override
  ConsumerState<LiveListScreen> createState() => LiveListScreenState();
}

const _kCatLabels = {
  'elektronik': '📱 Elektronik',
  'giyim': '👗 Giyim',
  'ev': '🏠 Ev & Yaşam',
  'vasita': '🚗 Vasıta',
  'spor': '⚽ Spor',
  'kitap': '📚 Kitap',
  'emlak': '🏘️ Emlak',
  'diger': '📦 Diğer',
};

class LiveListScreenState extends ConsumerState<LiveListScreen> {
  List<StreamOut> _streams = [];
  bool _loading = true;
  String? _selectedCategory; // null = Tümü
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void triggerStartDialog() => _showStartDialog();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    // Takip edilen yayınları da yenile (pull-to-refresh sırasında ikisi senkronize olsun)
    ref.invalidate(followedStreamsProvider);
    try {
      final streams = await StreamService.getActiveStreams();
      if (!mounted) return;
      setState(() {
        _streams = streams;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AppException ? e.message : (mounted ? AppLocalizations.of(context)!.liveStreamsLoadError : 'error');
      });
    }
  }

  Future<void> _showStartDialog() async {
    final categories = await CategoryService.getCategories();
    final token = await StorageService.getToken();
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.liveLoginRequired)),
      );
      return;
    }

    final titleController = TextEditingController();
    String? selectedCategory;
    String? errorText;

    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(l.liveStartStreamDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('live_dialog_input_yayin_basligi'),
                controller: titleController,
                autofocus: true,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: l.liveStreamTitleHint,
                  labelText: l.liveStreamTitleLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('live_dialog_select_kategori'),
                value: selectedCategory,
                decoration: InputDecoration(
                  labelText: l.liveCategoryLabel,
                  border: const OutlineInputBorder(),
                ),
                hint: Text(l.liveCategoryHint),
                items: categories
                    .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                    .toList(),
                onChanged: (v) => setStateDialog(() => selectedCategory = v),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              key: const Key('live_dialog_btn_iptal'),
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.btnCancel),
            ),
            ElevatedButton(
              key: const Key('live_dialog_btn_baslat'),
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
              onPressed: () {
                final t = titleController.text.trim();
                if (t.isEmpty) {
                  setStateDialog(() => errorText = l.liveStreamTitleRequired);
                  return;
                }
                if (t.length < 3) {
                  setStateDialog(
                      () => errorText = l.liveStreamTitleMin);
                  return;
                }
                if (selectedCategory == null) {
                  setStateDialog(() => errorText = l.liveCategoryRequired);
                  return;
                }
                Navigator.pop(ctx, (t, selectedCategory!));
              },
              child: Text(l.liveStartBtn, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final (title, category) = result;

    if (!mounted) return;

    // Yükleniyor göstergesi — captcha + API çağrısı süresince
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(color: kPrimary),
        ),
      ),
    );

    // Güvenlik doğrulaması: görünmez Turnstile challenge
    final captchaToken = await CaptchaService.getToken(context);
    if (!mounted) return;

    try {
      final streamToken = await StreamService.startStream(
        title,
        category,
        captchaToken: captchaToken,
      );
      if (!mounted) return;
      Navigator.pop(context); // loading dialog kapat
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HostStreamScreen(streamToken: streamToken, title: title),
        ),
      ).then((_) => _load());
    } on AppException catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // loading dialog kapat
      final ll = AppLocalizations.of(context)!;
      final msg = _mapCaptchaError(e, ll);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) Navigator.pop(context); // loading dialog kapat
      showErrorSnackbar(context, e);
    }
  }

  /// 403/429 hata kodlarını kullanıcı dostu mesaja çevirir.
  String _mapCaptchaError(AppException e, AppLocalizations l) {
    if (e.statusCode == 403 || e.code == 'FORBIDDEN') {
      return l.errorCaptchaFailed;
    }
    if (e.statusCode == 429 || e.code == 'RATE_LIMIT_EXCEEDED') {
      return l.errorTooFast;
    }
    return e.message;
  }

  Future<void> _joinStream(StreamOut stream) async {
    if (!mounted) return;
    final idx = _streams.indexOf(stream);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SwipeLiveScreen(streams: _streams, initialIndex: idx),
      ),
    ).then((_) => _load());
  }

  List<String> get _categories {
    final seen = <String>{};
    return _streams.map((s) => s.category).where(seen.add).toList();
  }

  List<StreamOut> get _filtered => _selectedCategory == null
      ? _streams
      : _streams.where((s) => s.category == _selectedCategory).toList();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cats = _categories;
    final showFilter = !_loading && cats.length >= 1;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l.liveStreamsTitle,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            key: const Key('live_list_btn_yayin_ac'),
            onPressed: _showStartDialog,
            icon: const Icon(Icons.videocam_outlined, size: 18, color: Colors.red),
            label: Text(
              l.liveStartStream,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Takip edilen canlı yayınlar (Story tarzı) ───────────
          StoryTray(onTap: _joinStream),

          // ── Kategori filtre çubuğu ──────────────────────────────
          if (showFilter)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  _CategoryChip(
                    key: const Key('live_list_chip_tumü'),
                    label: l.liveAllCategory,
                    active: _selectedCategory == null,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  ...cats.map((c) => _CategoryChip(
                        key: Key('live_list_chip_$c'),
                        label: _kCatLabels[c] ?? c,
                        active: _selectedCategory == c,
                        onTap: () => setState(() => _selectedCategory = c),
                      )),
                ],
              ),
            ),
          // ── İçerik ──────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: kPrimary,
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : _error != null
                      ? _ErrorState(message: _error!)
                      : filtered.isEmpty
                          ? const _EmptyState()
                          : _selectedCategory != null || cats.length < 2
                              // Tek kategori veya filtre seçili: düz grid
                              ? GridView.builder(
                                  padding: const EdgeInsets.all(12),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 0.78,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) => _StreamGridTile(
                                    stream: filtered[i],
                                    onTap: () => _joinStream(filtered[i]),
                                  ),
                                )
                              // Tümü seçili + birden fazla kategori: section'lara böl
                              : _buildSectioned(cats, filtered),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectioned(List<String> cats, List<StreamOut> all) {
    final groups = {for (var c in cats) c: all.where((s) => s.category == c).toList()};

    return CustomScrollView(
      slivers: [
        for (final c in cats)
          if (groups[c]!.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Text(
                  _kCatLabels[c] ?? c,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _StreamGridTile(
                    stream: groups[c]![i],
                    onTap: () => _joinStream(groups[c]![i]),
                  ),
                  childCount: groups[c]!.length,
                ),
              ),
            ),
          ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CategoryChip({super.key, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? kPrimary : const Color(0xFFD1D5DB),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    // ListView + AlwaysScrollableScrollPhysics olmadan
    // RefreshIndicator parmak hareketini algılayamaz.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
        Column(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 56, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Yenilemek için aşağı çekin',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Column(
          children: [
            Icon(Icons.videocam_off_outlined, size: 56, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text(
              'Şu an aktif yayın yok',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
            ),
            SizedBox(height: 4),
            Text(
              'İlk yayını sen başlat!',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _StreamGridTile extends StatelessWidget {
  final StreamOut stream;
  final VoidCallback onTap;

  const _StreamGridTile({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = stream.thumbnailUrl != null && stream.thumbnailUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square thumbnail area
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background
                  if (hasThumbnail)
                    CachedNetworkImage(
                      imageUrl: imgUrl(stream.thumbnailUrl),
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      errorWidget: (_, __, ___) => _gradientBox(),
                    )
                  else
                    _gradientBox(),
                  // CANLI badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.liveBadgeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  // Viewer badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '👁 ${stream.viewerCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info section
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stream.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${stream.host.username}',
                    style: const TextStyle(
                      color: kPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientBox() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryDark, kPrimaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.videocam_rounded, color: Colors.white30, size: 36),
      ),
    );
  }

}

