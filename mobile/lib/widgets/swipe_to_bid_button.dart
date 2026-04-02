import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

class SwipeToBidButton extends StatefulWidget {
  final String text;
  final VoidCallback onSwipeComplete;
  final bool isLoading;

  const SwipeToBidButton({
    super.key,
    required this.text,
    required this.onSwipeComplete,
    this.isLoading = false,
  });

  @override
  State<SwipeToBidButton> createState() => _SwipeToBidButtonState();
}

class _SwipeToBidButtonState extends State<SwipeToBidButton>
    with TickerProviderStateMixin {
  static const double _trackHeight = 56.0;
  static const double _thumbSize = 48.0;
  static const double _trackPadding = 4.0;
  static const double _completeThreshold = 0.88;

  // Thumb pozisyonu 0.0 (sol) → 1.0 (sağ)
  double _dragProgress = 0.0;
  double _maxDrag = 0.0;
  bool _isDragging = false;
  bool _completed = false;
  int _lastHapticStep = -1;

  // Spring-back için unbounded controller
  late final AnimationController _springCtrl;

  // Shimmer için ayrı controller
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();

    _springCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() {
          _dragProgress = _springCtrl.value.clamp(0.0, 1.0);
        });
      });

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _shimmerAnim = Tween<double>(begin: -0.6, end: 1.6).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _springCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails _) {
    if (widget.isLoading || _completed) return;
    _springCtrl.stop();
    _isDragging = true;
    _lastHapticStep = (_dragProgress * 10).floor();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging || widget.isLoading || _maxDrag <= 0) return;

    final newProgress =
        (_dragProgress + details.delta.dx / _maxDrag).clamp(0.0, 1.0);

    // Her ~10% adımda bir hafif titreşim
    final step = (newProgress * 10).floor();
    if (step > _lastHapticStep) {
      _lastHapticStep = step;
      HapticFeedback.selectionClick();
    }

    setState(() => _dragProgress = newProgress);

    if (newProgress >= _completeThreshold) {
      _triggerComplete();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    if (_completed) return;
    _springBack(velocity: details.velocity.pixelsPerSecond.dx / _maxDrag);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _triggerComplete() {
    if (_completed) return;
    _completed = true;
    _isDragging = false;
    HapticFeedback.heavyImpact();
    widget.onSwipeComplete();
    // İşlem bittikten kısa süre sonra geri dön
    Future.delayed(const Duration(milliseconds: 150), () {
      _completed = false;
      _springBack();
    });
  }

  void _springBack({double velocity = 0.0}) {
    // Elastik geri sekme: mass=1, stiffness=400, damping=20 → hafif overshootu olan bahar
    const spring = SpringDescription(
      mass: 1.0,
      stiffness: 400.0,
      damping: 20.0,
    );
    final simulation = SpringSimulation(spring, _dragProgress, 0.0, velocity);
    _springCtrl.animateWith(simulation);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = constraints.maxWidth - _thumbSize - _trackPadding * 2;
        final thumbLeft = _trackPadding + _dragProgress * _maxDrag;
        final fillWidth = thumbLeft + _thumbSize / 2;

        return SizedBox(
          height: _trackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Track ────────────────────────────────────────────────────
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                    child: Stack(
                      children: [
                        // Fill — thumb ile birlikte uzar
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: AnimatedContainer(
                            duration: Duration.zero,
                            width: fillWidth.clamp(0.0, constraints.maxWidth),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  kPrimary.withValues(alpha: 0.40),
                                  kPrimary.withValues(alpha: 0.15 + _dragProgress * 0.20),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Shimmer + metin
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _thumbSize + _trackPadding + 10,
                            ),
                            child: widget.isLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                          Colors.white.withValues(alpha: 0.7)),
                                    ),
                                  )
                                : _ShimmerText(
                                    text: widget.text,
                                    shimmerAnim: _shimmerAnim,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Thumb ────────────────────────────────────────────────────
              Positioned(
                left: thumbLeft,
                top: _trackPadding,
                bottom: _trackPadding,
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: _Thumb(
                    size: _thumbSize - _trackPadding * 2,
                    progress: _dragProgress,
                    isLoading: widget.isLoading,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Shimmer Text ─────────────────────────────────────────────────────────────

class _ShimmerText extends StatelessWidget {
  final String text;
  final Animation<double> shimmerAnim;

  const _ShimmerText({required this.text, required this.shimmerAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerAnim,
      builder: (_, child) {
        final s = shimmerAnim.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0x70FFFFFF),
              Color(0xCCFFFFFF),
              Color(0xFFFFFFFF),
              Color(0xCCFFFFFF),
              Color(0x70FFFFFF),
            ],
            stops: [
              (s - 0.4).clamp(0.0, 1.0),
              (s - 0.15).clamp(0.0, 1.0),
              s.clamp(0.0, 1.0),
              (s + 0.15).clamp(0.0, 1.0),
              (s + 0.4).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Thumb ─────────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  final double size;
  final double progress;
  final bool isLoading;

  const _Thumb({
    required this.size,
    required this.progress,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Color.lerp(kPrimary, Colors.white, 0.18)!,
            kPrimary,
          ],
          center: const Alignment(-0.3, -0.4),
          radius: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.45 + progress * 0.35),
            blurRadius: 10 + progress * 10,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isLoading
          ? Padding(
              padding: const EdgeInsets.all(13),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.9)),
              ),
            )
          : Stack(
              alignment: Alignment.center,
              children: [
                // progress → 0'da oklar görünür, 1'de check görünür
                Opacity(
                  opacity: (1.0 - progress * 2).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_right,
                          color: Colors.white.withValues(alpha: 0.45), size: 16),
                      const Icon(Icons.chevron_right,
                          color: Colors.white, size: 20),
                    ],
                  ),
                ),
                Opacity(
                  opacity: ((progress - 0.5) * 2).clamp(0.0, 1.0),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
    );
  }
}
