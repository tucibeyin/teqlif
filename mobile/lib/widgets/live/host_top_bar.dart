import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Canlı yayın host ekranı — üst bilgi çubuğu.
///
/// CANLI rozeti, izleyici sayacı (tıklanabilir), kayar başlık,
/// mikrofon/kamera/çevirme kontrolleri ve "Bitir" butonu içerir.
/// Tüm etkileşimler callback ile üst widget'a iletilir.
class HostTopBar extends StatefulWidget {
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
  State<HostTopBar> createState() => _HostTopBarState();
}

class _HostTopBarState extends State<HostTopBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _marqueeCtrl;
  late final Animation<Offset> _marqueeAnim;

  // Bir turda kaç saniye? Başlık uzunluğuna göre ayarlanır.
  static const _speed = 40.0; // piksel/saniye

  @override
  void initState() {
    super.initState();
    _startMarquee();
  }

  void _startMarquee() {
    // Tahmini metin uzunluğu: karakter * ortalama 8px
    final charCount = widget.title.length;
    final estimatedWidth = (charCount * 8.0).clamp(80.0, 600.0);
    final durationMs = ((estimatedWidth / _speed) * 1000).round();

    _marqueeCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );
    // Sağdan sola: başlangıç x=1.5 (sağ dışarı), bitiş x=-1.5 (sol dışarı)
    _marqueeAnim = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: const Offset(-1.5, 0),
    ).animate(CurvedAnimation(parent: _marqueeCtrl, curve: Curves.linear));

    _marqueeCtrl.repeat();
  }

  @override
  void didUpdateWidget(HostTopBar old) {
    super.didUpdateWidget(old);
    if (old.title != widget.title) {
      _marqueeCtrl.dispose();
      _startMarquee();
    }
  }

  @override
  void dispose() {
    _marqueeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.only(
        top: widget.topPad + 14,
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
      child: Row(
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
            onTap: widget.onViewersTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '👁 ${widget.viewerCount}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Kayar başlık
          Expanded(
            child: ClipRect(
              child: SlideTransition(
                position: _marqueeAnim,
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Mikrofon toggle
          _TopCtrlBtn(
            key: const Key('host_btn_mikrofon_toggle'),
            icon: widget.micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: widget.micEnabled,
            onTap: widget.onToggleMic,
          ),
          const SizedBox(width: 6),

          // Kamera toggle
          _TopCtrlBtn(
            key: const Key('host_btn_kamera_toggle'),
            icon: widget.cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            active: widget.cameraEnabled,
            onTap: widget.onToggleCamera,
          ),
          const SizedBox(width: 6),

          // Kamera değiştir
          _TopCtrlBtn(
            key: const Key('host_btn_kamera_cevir'),
            icon: Icons.flip_camera_ios_rounded,
            active: true,
            onTap: widget.onSwitchCamera,
          ),
          const SizedBox(width: 10),

          // Yayını Bitir
          GestureDetector(
            key: const Key('host_btn_yayin_bitir'),
            onTap: widget.onEndStream,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.85),
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
    );
  }
}

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
          color: active ? Colors.black54 : Colors.red.withOpacity(0.75),
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
