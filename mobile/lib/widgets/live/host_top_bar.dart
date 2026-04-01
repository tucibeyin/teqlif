import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Canlı yayın host ekranı — üst bilgi çubuğu.
///
/// CANLI rozeti, izleyici sayacı (tıklanabilir), kayar başlık,
/// mikrofon/kamera/çevirme kontrolleri ve "Bitir" butonu içerir.
/// Tüm etkileşimler callback ile üst widget'a iletilir.
class HostTopBar extends StatelessWidget {
  final double topPad;
  final int viewerCount;
  final String title;
  final bool micEnabled;
  final bool cameraEnabled;
  final VoidCallback onViewersTap;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEndStream;

  const HostTopBar({
    super.key,
    required this.topPad,
    required this.viewerCount,
    required this.title,
    required this.micEnabled,
    required this.cameraEnabled,
    required this.onViewersTap,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onEndStream,
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
              // CANLI rozeti
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  l.liveBadgeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // İzleyici sayısı (tıklanabilir)
              GestureDetector(
                onTap: onViewersTap,
                child: Container(
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
              ),
              const Spacer(),

              // Mikrofon toggle
              _TopCtrlBtn(
                key: const Key('host_btn_mikrofon_toggle'),
                icon: micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                active: micEnabled,
                onTap: onToggleMic,
              ),
              const SizedBox(width: 6),

              // Kamera toggle
              _TopCtrlBtn(
                key: const Key('host_btn_kamera_toggle'),
                icon: cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                active: cameraEnabled,
                onTap: onToggleCamera,
              ),
              const SizedBox(width: 6),

              // Kamera değiştir
              _TopCtrlBtn(
                key: const Key('host_btn_kamera_cevir'),
                icon: Icons.flip_camera_ios_rounded,
                active: true,
                onTap: onSwitchCamera,
              ),
              const SizedBox(width: 10),

              // Yayını Bitir
              GestureDetector(
                key: const Key('host_btn_yayin_bitir'),
                onTap: onEndStream,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l.liveEndStreamBtn,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Satır 2: Kayar başlık ────────────────────────────────
          const SizedBox(height: 8),
          _MarqueeText(
            text: title,
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
/// Metin sığıyorsa sabit gösterilir. TextPainter ile gerçek genişlik ölçülür
/// böylece metin asla kısılmaz.
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

  /// Metin genişliğini ölç, controller'ı (yeniden) başlat.
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

    if (newTextW <= containerW) return; // sığıyor — animasyon yok

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

        // Henüz ölçülmedi veya metin sığıyor → statik
        if (ctrl == null || _textWidth <= _containerWidth) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        return AnimatedBuilder(
          animation: ctrl,
          builder: (_, __) {
            final totalDist     = _containerWidth + _textWidth;
            final scrollMs      = totalDist / _speed * 1000;
            final totalMs       = scrollMs + _pauseMs;
            final scrollFrac    = scrollMs / totalMs;
            final t             = ctrl.value;

            // Sağdan sola: containerW → -_textWidth
            final double left;
            if (t < scrollFrac) {
              left = _containerWidth - (t / scrollFrac) * totalDist;
            } else {
              left = -_textWidth; // duraklama: tamamen sol dışı
            }

            // ClipRect: containerW kadar görünür alan
            // Stack + Positioned: text hiçbir constraint almıyor
            return SizedBox(
              height: 20,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Üst bar kontrol butonu ────────────────────────────────────────────────────

/// Üst bardaki küçük dairesel kontrol butonu.
class _TopCtrlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _TopCtrlBtn({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active ? Colors.black54 : Colors.red.withValues(alpha: 0.75),
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? Colors.white30 : Colors.transparent,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
