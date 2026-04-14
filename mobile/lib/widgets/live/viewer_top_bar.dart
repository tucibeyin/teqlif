import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../l10n/app_localizations.dart';

/// Canlı yayın izleyici ekranı — üst bilgi çubuğu.
///
/// Satır 1: Geri butonu, CANLI rozeti, izleyici sayacı, MOD rozeti, Ayrıl butonu.
/// Satır 2: Kayar yayın başlığı (host kullanıcı adı ile birlikte).
class ViewerTopBar extends StatelessWidget {
  final double topPad;
  final int viewerCount;
  final String title;
  final String hostUsername;
  final bool isCoHost;
  final bool streamEnded;
  final VoidCallback onLeave;
  final int? streamId;

  const ViewerTopBar({
    super.key,
    required this.topPad,
    required this.viewerCount,
    required this.title,
    required this.hostUsername,
    required this.isCoHost,
    required this.onLeave,
    this.streamEnded = false,
    this.streamId,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.only(
        top: topPad + 14,
        left: 16,
        right: 16,
        bottom: 32,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xBB000000), Colors.transparent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Satır 1: Kontroller ──────────────────────────────────
          Row(
            children: [
              // Geri
              GestureDetector(
                key: const Key('viewer_btn_geri'),
                onTap: onLeave,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // CANLI / BİTTİ rozeti
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: streamEnded ? Colors.grey : Colors.red,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  streamEnded ? l.liveEndedBadge : l.liveBadgeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // İzleyici sayısı
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '👁 $viewerCount',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),

              const Spacer(),

              // Paylaş butonu
              if (streamId != null) ...[
                Builder(
                  builder: (btnCtx) => GestureDetector(
                    key: const Key('viewer_btn_paylas'),
                    onTap: () {
                      final box = btnCtx.findRenderObject() as RenderBox?;
                      Share.share(
                        '$title — teqlif\'te canlı izle: https://www.teqlif.com/yayin/$streamId',
                        sharePositionOrigin: box == null
                            ? Rect.zero
                            : box.localToGlobal(Offset.zero) & box.size,
                      );
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.share_outlined, color: Colors.white, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // MOD rozeti — sadece co-host olduğunda
              if (isCoHost) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '🛡 MOD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Ayrıl
              GestureDetector(
                key: const Key('viewer_btn_ayril'),
                onTap: onLeave,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    l.liveLeaveBtn,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Satır 2: Kayar başlık ────────────────────────────────
          const SizedBox(height: 8),
          _MarqueeText(
            text: '@$hostUsername · $title',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              shadows: [Shadow(blurRadius: 6, color: Colors.black)],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Kayar metin widget'ı ──────────────────────────────────────────────────────

/// Metin container genişliğini aşıyorsa sağdan sola sürekli kayar.
/// Metin sığıyorsa sabit gösterilir.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  static const double _speed   = 25.0; // piksel/saniye
  static const int    _pauseMs = 800;  // tur arası bekleme (ms)

  double _textWidth      = 0;
  double _containerWidth = 0;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _rebuild(double containerW) {
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);

    final newTextW = tp.width;
    if (_textWidth == newTextW && _containerWidth == containerW) return;
    _textWidth      = newTextW;
    _containerWidth = containerW;

    _ctrl?.dispose();
    _ctrl = null;

    if (newTextW <= containerW) return;

    final totalDist = containerW + newTextW;
    final scrollMs  = (totalDist / _speed * 1000).round();

    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: scrollMs + _pauseMs),
    )..repeat();
  }

  @override
  void didUpdateWidget(_MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _textWidth = 0;
      _containerWidth = 0;
      _ctrl?.dispose();
      _ctrl = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final containerW = constraints.maxWidth;

        if (_containerWidth != containerW || _textWidth == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) { _rebuild(containerW); setState(() {}); }
          });
        }

        final ctrl = _ctrl;

        if (ctrl == null || _textWidth <= _containerWidth) {
          return Text(widget.text, style: widget.style, maxLines: 1);
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: ctrl,
            builder: (_, child) {
              final t = ctrl.value;
              final pauseFraction = _pauseMs / ctrl.duration!.inMilliseconds;
              final scrollFraction = 1.0 - pauseFraction;
              final scrollT = (t / scrollFraction).clamp(0.0, 1.0);
              final offset = scrollT * (_containerWidth + _textWidth);
              return Transform.translate(
                offset: Offset(_containerWidth - offset, 0),
                child: child,
              );
            },
            child: Text(widget.text, style: widget.style, maxLines: 1,
                softWrap: false),
          ),
        );
      },
    );
  }
}
